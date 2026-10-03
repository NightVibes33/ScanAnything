import UIKit

@MainActor
enum CaptureImageProcessor {
    static func jpegData(from image: UIImage) throws -> Data {
        let maxDimension: CGFloat = 2_048
        let width = image.size.width
        let height = image.size.height
        let largest = max(width, height)
        let scale = largest > maxDimension ? maxDimension / largest : 1
        let target = CGSize(width: width * scale, height: height * scale)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        let normalized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }

        for quality in stride(from: 0.90, through: 0.55, by: -0.07) {
            if let data = normalized.jpegData(compressionQuality: quality),
               data.count <= 2_800_000 {
                return data
            }
        }

        guard let data = normalized.jpegData(compressionQuality: 0.5) else {
            throw OnDevice3DError.invalidImage
        }
        return data
    }
}
