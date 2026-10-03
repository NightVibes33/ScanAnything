import CoreImage
@preconcurrency @preconcurrency import CoreML
import Foundation
import ImageIO
import SceneKit
import Vision

enum OnDevice3DError: LocalizedError {
    case modelMissing(String)
    case invalidImage
    case foregroundExtractionFailed
    case invalidModelOutput(String)
    case emptyMesh
    case exportFailed

    var errorDescription: String? {
        switch self {
        case .modelMissing(let name):
            "The on-device 3D model \(name) is missing from this build."
        case .invalidImage:
            "The selected image could not be decoded."
        case .foregroundExtractionFailed:
            "The subject could not be isolated from the photo."
        case .invalidModelOutput(let name):
            "The on-device 3D model returned an invalid \(name) output."
        case .emptyMesh:
            "The on-device model did not produce usable 3D geometry."
        case .exportFailed:
            "The generated 3D model could not be saved."
        }
    }
}

struct OnDevice3DResult: Sendable {
    let previewPNG: Data
    let usdz: Data
    let vertexCount: Int
    let triangleCount: Int
    let resolution: Int
}

actor OnDeviceTripoSREngine {
    static let shared = OnDeviceTripoSREngine()

    private static let encoderName = "ImageToTriplane"
    private static let decoderName = "NeRFQuery"
    private static let queryCount = 262_144
    private static let fieldRadius: Float = 0.87
    private static let densityThreshold: Float = 25

    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    private var encoder: MLModel?
    private var decoder: MLModel?

    static var recommendedResolution: Int {
        let memoryGB = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
        if memoryGB >= 7.5 { return 256 }
        if memoryGB >= 5.5 { return 224 }
        return 192
    }

    func generate(jpegData: Data) async throws -> OnDevice3DResult {
        let prepared = try prepareImage(jpegData)
        let models = try loadModels()

        let imageArray = try rgbTensor(from: prepared)
        let encoderInput = try MLDictionaryFeatureProvider(
            dictionary: ["image": MLFeatureValue(multiArray: imageArray)]
        )
        let encoderOutput = try await models.encoder.prediction(from: encoderInput)
        guard let triplane = encoderOutput.featureValue(for: "triplane")?.multiArrayValue else {
            throw OnDevice3DError.invalidModelOutput("triplane")
        }

        let resolution = Self.recommendedResolution
        let field = try await queryField(
            decoder: models.decoder,
            triplane: triplane,
            resolution: resolution
        )

        let mesh = DenseMarchingCubes.extract(
            densities: field.densities,
            colors: field.colors,
            resolution: resolution,
            threshold: Self.densityThreshold,
            radius: Self.fieldRadius
        )

        guard mesh.positions.count >= 3 else {
            throw OnDevice3DError.emptyMesh
        }

        let usdzData = try exportUSDZ(mesh: mesh)

        return OnDevice3DResult(
            previewPNG: prepared.pngData(),
            usdz: usdzData,
            vertexCount: mesh.positions.count,
            triangleCount: mesh.positions.count / 3,
            resolution: resolution
        )
    }

    private func loadModels() throws -> (encoder: MLModel, decoder: MLModel) {
        if let encoder, let decoder {
            return (encoder, decoder)
        }

        guard let encoderURL = Self.modelURL(named: Self.encoderName) else {
            throw OnDevice3DError.modelMissing(Self.encoderName)
        }
        guard let decoderURL = Self.modelURL(named: Self.decoderName) else {
            throw OnDevice3DError.modelMissing(Self.decoderName)
        }

        let encoderConfig = MLModelConfiguration()
        encoderConfig.computeUnits = .all
        encoderConfig.allowLowPrecisionAccumulationOnGPU = true

        let decoderConfig = MLModelConfiguration()
        // The published Core ML conversion benchmarks the NeRF query model on
        // CPU. Keeping it CPU-only also avoids repeatedly copying the triplane
        // and query chunks between execution devices.
        decoderConfig.computeUnits = .cpuOnly

        let loadedEncoder = try MLModel(contentsOf: encoderURL, configuration: encoderConfig)
        let loadedDecoder = try MLModel(contentsOf: decoderURL, configuration: decoderConfig)

        encoder = loadedEncoder
        decoder = loadedDecoder
        return (loadedEncoder, loadedDecoder)
    }

    private static func modelURL(named name: String) -> URL? {
        if let direct = Bundle.main.url(forResource: name, withExtension: "mlmodelc") {
            return direct
        }

        if let nested = Bundle.main.urls(
            forResourcesWithExtension: "mlmodelc",
            subdirectory: "TripoSRCoreML"
        )?.first(where: { $0.deletingPathExtension().lastPathComponent == name }) {
            return nested
        }

        guard let resources = Bundle.main.resourceURL,
              let enumerator = FileManager.default.enumerator(
                at: resources,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
              )
        else {
            return nil
        }

        for case let url as URL in enumerator
            where url.pathExtension == "mlmodelc" &&
                  url.deletingPathExtension().lastPathComponent == name {
            return url
        }
        return nil
    }

    private func prepareImage(_ data: Data) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let rawImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw OnDevice3DError.invalidImage
        }

        let sourceCI = CIImage(cgImage: rawImage)
        let gray = CIImage(
            color: CIColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)
        ).cropped(to: sourceCI.extent)

        let handler = VNImageRequestHandler(cgImage: rawImage)
        let request = VNGenerateForegroundInstanceMaskRequest()

        do {
            try handler.perform([request])
            guard let observation = request.results?.first else {
                return try fallbackPreparedImage(rawImage)
            }

            let maskBuffer = try observation.generateScaledMaskForImage(
                forInstances: observation.allInstances,
                from: handler
            )
            guard let maskBounds = Self.maskBounds(maskBuffer) else {
                return try fallbackPreparedImage(rawImage)
            }

            let maskCI = CIImage(cvPixelBuffer: maskBuffer)
            let filter = CIFilter(name: "CIBlendWithMask")
            filter?.setValue(sourceCI, forKey: kCIInputImageKey)
            filter?.setValue(gray, forKey: kCIInputBackgroundImageKey)
            filter?.setValue(maskCI, forKey: kCIInputMaskImageKey)

            guard let blended = filter?.outputImage else {
                return try fallbackPreparedImage(rawImage)
            }

            let imageHeight = CGFloat(CVPixelBufferGetHeight(maskBuffer))
            let cropRect = CGRect(
                x: maskBounds.minX,
                y: imageHeight - maskBounds.maxY,
                width: maskBounds.width,
                height: maskBounds.height
            ).intersection(sourceCI.extent)

            guard cropRect.width > 4, cropRect.height > 4 else {
                return try fallbackPreparedImage(rawImage)
            }

            let cropped = blended.cropped(to: cropRect)
            return try renderToModelCanvas(cropped)
        } catch {
            return try fallbackPreparedImage(rawImage)
        }
    }

    private func fallbackPreparedImage(_ image: CGImage) throws -> CGImage {
        try renderToModelCanvas(CIImage(cgImage: image))
    }

    private func renderToModelCanvas(_ image: CIImage) throws -> CGImage {
        let target: CGFloat = 512
        let foreground: CGFloat = 0.85
        let extent = image.extent
        let scale = min(
            target * foreground / extent.width,
            target * foreground / extent.height
        )

        let scaled = image.transformed(
            by: CGAffineTransform(scaleX: scale, y: scale)
        )
        let scaledExtent = scaled.extent
        let dx = (target - scaledExtent.width) * 0.5 - scaledExtent.minX
        let dy = (target - scaledExtent.height) * 0.5 - scaledExtent.minY
        let centered = scaled.transformed(
            by: CGAffineTransform(translationX: dx, y: dy)
        )

        let canvasRect = CGRect(x: 0, y: 0, width: target, height: target)
        let gray = CIImage(
            color: CIColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)
        ).cropped(to: canvasRect)
        let composited = centered.composited(over: gray).cropped(to: canvasRect)

        guard let output = ciContext.createCGImage(composited, from: canvasRect) else {
            throw OnDevice3DError.invalidImage
        }
        return output
    }

    private static func maskBounds(_ buffer: CVPixelBuffer) -> CGRect? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }

        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        let format = CVPixelBufferGetPixelFormatType(buffer)

        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1
        let step = 2

        if format == kCVPixelFormatType_OneComponent8 {
            let ptr = base.assumingMemoryBound(to: UInt8.self)
            for y in stride(from: 0, to: height, by: step) {
                let row = ptr.advanced(by: y * rowBytes)
                for x in stride(from: 0, to: width, by: step) where row[x] > 24 {
                    minX = min(minX, x)
                    minY = min(minY, y)
                    maxX = max(maxX, x)
                    maxY = max(maxY, y)
                }
            }
        } else if format == kCVPixelFormatType_OneComponent32Float {
            for y in stride(from: 0, to: height, by: step) {
                let row = base
                    .advanced(by: y * rowBytes)
                    .assumingMemoryBound(to: Float.self)
                for x in stride(from: 0, to: width, by: step) where row[x] > 0.1 {
                    minX = min(minX, x)
                    minY = min(minY, y)
                    maxX = max(maxX, x)
                    maxY = max(maxY, y)
                }
            }
        } else {
            return nil
        }

        guard maxX >= minX, maxY >= minY else { return nil }

        let paddingX = max(8, Int(Double(maxX - minX + 1) * 0.08))
        let paddingY = max(8, Int(Double(maxY - minY + 1) * 0.08))

        let x0 = max(0, minX - paddingX)
        let y0 = max(0, minY - paddingY)
        let x1 = min(width - 1, maxX + paddingX)
        let y1 = min(height - 1, maxY + paddingY)

        return CGRect(
            x: x0,
            y: y0,
            width: x1 - x0 + 1,
            height: y1 - y0 + 1
        )
    }

    private func rgbTensor(from image: CGImage) throws -> MLMultiArray {
        let width = 512
        let height = 512
        let bytesPerRow = width * 4
        var rgba = [UInt8](repeating: 0, count: height * bytesPerRow)

        guard let context = CGContext(
            data: &rgba,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw OnDevice3DError.invalidImage
        }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        let tensor = try MLMultiArray(
            shape: [
                NSNumber(value: 1),
                NSNumber(value: 3),
                NSNumber(value: 512),
                NSNumber(value: 512),
            ],
            dataType: .float32
        )
        let ptr = tensor.dataPointer.assumingMemoryBound(to: Float.self)
        let plane = width * height

        for y in 0..<height {
            for x in 0..<width {
                let pixel = (y * width + x) * 4
                let index = y * width + x
                ptr[index] = Float(rgba[pixel]) / 255
                ptr[plane + index] = Float(rgba[pixel + 1]) / 255
                ptr[2 * plane + index] = Float(rgba[pixel + 2]) / 255
            }
        }

        return tensor
    }

    private struct Field {
        let densities: [Float]
        let colors: [SIMD3<Float>]
    }

    private func queryField(
        decoder: MLModel,
        triplane: MLMultiArray,
        resolution: Int
    ) async throws -> Field {
        let total = resolution * resolution * resolution
        var densities = [Float](repeating: 0, count: total)
        var colors = [SIMD3<Float>](repeating: .zero, count: total)

        let xyz = try MLMultiArray(
            shape: [
                NSNumber(value: Self.queryCount),
                NSNumber(value: 3),
            ],
            dataType: .float32
        )
        let xyzPtr = xyz.dataPointer.assumingMemoryBound(to: Float.self)

        let denom = Float(max(1, resolution - 1))
        let span = Self.fieldRadius * 2

        var start = 0
        while start < total {
            try Task.checkCancellation()
            let count = min(Self.queryCount, total - start)

            for local in 0..<Self.queryCount {
                let linear = start + min(local, max(0, count - 1))
                let x = linear % resolution
                let y = (linear / resolution) % resolution
                let z = linear / (resolution * resolution)

                xyzPtr[local * 3] =
                    -Self.fieldRadius + Float(x) / denom * span
                xyzPtr[local * 3 + 1] =
                    -Self.fieldRadius + Float(y) / denom * span
                xyzPtr[local * 3 + 2] =
                    -Self.fieldRadius + Float(z) / denom * span
            }

            let input = try MLDictionaryFeatureProvider(
                dictionary: [
                    "triplane": MLFeatureValue(multiArray: triplane),
                    "xyz": MLFeatureValue(multiArray: xyz),
                ]
            )
            let output = try await decoder.prediction(from: input)

            guard let density = output.featureValue(for: "density")?.multiArrayValue else {
                throw OnDevice3DError.invalidModelOutput("density")
            }
            guard let color = output.featureValue(for: "color")?.multiArrayValue else {
                throw OnDevice3DError.invalidModelOutput("color")
            }

            for local in 0..<count {
                let destination = start + local
                densities[destination] = Self.floatValue(density, linearIndex: local)
                colors[destination] = SIMD3<Float>(
                    Self.floatValue(color, linearIndex: local * 3),
                    Self.floatValue(color, linearIndex: local * 3 + 1),
                    Self.floatValue(color, linearIndex: local * 3 + 2)
                )
            }

            start += count
        }

        return Field(densities: densities, colors: colors)
    }

    private static func floatValue(
        _ array: MLMultiArray,
        linearIndex: Int
    ) -> Float {
        switch array.dataType {
        case .float16:
            let ptr = array.dataPointer.assumingMemoryBound(to: Float16.self)
            return Float(ptr[linearIndex])
        case .float32:
            let ptr = array.dataPointer.assumingMemoryBound(to: Float.self)
            return ptr[linearIndex]
        case .double:
            let ptr = array.dataPointer.assumingMemoryBound(to: Double.self)
            return Float(ptr[linearIndex])
        default:
            return array[linearIndex].floatValue
        }
    }

    private func exportUSDZ(mesh: DenseMarchingCubes.Mesh) throws -> Data {
        let vertices = mesh.positions.map {
            // TripoSR uses Z-up. SceneKit/USD is Y-up. Rotate the generated
            // object into an upright, front-facing frame before export.
            SCNVector3(-$0.y, $0.z, -$0.x)
        }

        var normals = [SCNVector3]()
        normals.reserveCapacity(vertices.count)

        for index in stride(from: 0, to: vertices.count, by: 3) {
            let p0 = SIMD3<Float>(vertices[index])
            let p1 = SIMD3<Float>(vertices[index + 1])
            let p2 = SIMD3<Float>(vertices[index + 2])
            let cross = simd_cross(p1 - p0, p2 - p0)
            let length = simd_length(cross)
            let normal = length > 0.000_001
                ? cross / length
                : SIMD3<Float>(0, 1, 0)
            let scn = SCNVector3(normal)
            normals.append(contentsOf: [scn, scn, scn])
        }

        let vertexSource = SCNGeometrySource(vertices: vertices)
        let normalSource = SCNGeometrySource(normals: normals)

        var colorFloats = [Float]()
        colorFloats.reserveCapacity(mesh.colors.count * 4)
        for color in mesh.colors {
            colorFloats.append(min(1, max(0, color.x)))
            colorFloats.append(min(1, max(0, color.y)))
            colorFloats.append(min(1, max(0, color.z)))
            colorFloats.append(1)
        }

        let colorData = colorFloats.withUnsafeBytes { Data($0) }
        let colorSource = SCNGeometrySource(
            data: colorData,
            semantic: .color,
            vectorCount: mesh.colors.count,
            usesFloatComponents: true,
            componentsPerVector: 4,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<Float>.size * 4
        )

        let indices = (0..<vertices.count).map(UInt32.init)
        let indexData = indices.withUnsafeBytes { Data($0) }
        let element = SCNGeometryElement(
            data: indexData,
            primitiveType: .triangles,
            primitiveCount: vertices.count / 3,
            bytesPerIndex: MemoryLayout<UInt32>.size
        )

        let geometry = SCNGeometry(
            sources: [vertexSource, normalSource, colorSource],
            elements: [element]
        )
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = CGColor(
            red: 1,
            green: 1,
            blue: 1,
            alpha: 1
        )
        material.roughness.contents = 0.72
        material.metalness.contents = 0
        material.isDoubleSided = false
        geometry.materials = [material]

        let scene = SCNScene()
        scene.rootNode.addChildNode(SCNNode(geometry: geometry))

        let folder = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: folder) }

        let url = folder.appending(path: "model.usdz")
        let ok = scene.write(
            to: url,
            options: nil,
            delegate: nil,
            progressHandler: nil
        )
        guard ok, FileManager.default.fileExists(atPath: url.path) else {
            throw OnDevice3DError.exportFailed
        }

        return try Data(contentsOf: url)
    }
}

private extension CGImage {
    func pngData() -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            "public.png" as CFString,
            1,
            nil
        ) else {
            return Data()
        }
        CGImageDestinationAddImage(destination, self, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }
}

private extension SIMD3 where Scalar == Float {
    init(_ vector: SCNVector3) {
        self.init(vector.x, vector.y, vector.z)
    }
}
