import Foundation
import simd

enum DenseMarchingCubes {
    struct Mesh: Sendable {
        var positions: [SIMD3<Float>]
        var colors: [SIMD3<Float>]
    }

    static func extract(
        densities: [Float],
        colors: [SIMD3<Float>],
        resolution: Int,
        threshold: Float,
        radius: Float
    ) -> Mesh {
        guard resolution >= 2,
              densities.count == resolution * resolution * resolution,
              colors.count == densities.count
        else {
            return Mesh(positions: [], colors: [])
        }

        var positions = [SIMD3<Float>]()
        var outputColors = [SIMD3<Float>]()
        positions.reserveCapacity(350_000)
        outputColors.reserveCapacity(350_000)

        let step = (radius * 2) / Float(resolution - 1)

        @inline(__always)
        func index(_ x: Int, _ y: Int, _ z: Int) -> Int {
            (z * resolution + y) * resolution + x
        }

        @inline(__always)
        func position(_ x: Int, _ y: Int, _ z: Int) -> SIMD3<Float> {
            SIMD3<Float>(
                -radius + Float(x) * step,
                -radius + Float(y) * step,
                -radius + Float(z) * step
            )
        }

        for z in 0..<(resolution - 1) {
            for y in 0..<(resolution - 1) {
                for x in 0..<(resolution - 1) {
                    var values = [Float](repeating: 0, count: 8)
                    var cornerColors = [SIMD3<Float>](repeating: .zero, count: 8)
                    var cornerPositions = [SIMD3<Float>](repeating: .zero, count: 8)

                    var caseIndex = 0
                    for corner in 0..<8 {
                        let offset = mcCornerOffsets[corner]
                        let cx = x + offset.0
                        let cy = y + offset.1
                        let cz = z + offset.2
                        let i = index(cx, cy, cz)
                        let value = densities[i]
                        values[corner] = value
                        cornerColors[corner] = colors[i]
                        cornerPositions[corner] = position(cx, cy, cz)
                        if value >= threshold {
                            caseIndex |= 1 << corner
                        }
                    }

                    if caseIndex == 0 || caseIndex == 255 { continue }

                    let edgeMask = mcEdgeTable[caseIndex]
                    if edgeMask == 0 { continue }

                    var edgePositions = [SIMD3<Float>](repeating: .zero, count: 12)
                    var edgeColors = [SIMD3<Float>](repeating: .zero, count: 12)

                    for edge in 0..<12 where (edgeMask & UInt16(1 << edge)) != 0 {
                        let pair = mcEdgeVertexPairs[edge]
                        let a = pair.0
                        let b = pair.1
                        let va = values[a]
                        let vb = values[b]
                        let denominator = vb - va
                        let t: Float = abs(denominator) < 0.000_001
                            ? 0.5
                            : min(1, max(0, (threshold - va) / denominator))

                        edgePositions[edge] =
                            cornerPositions[a] +
                            (cornerPositions[b] - cornerPositions[a]) * t
                        edgeColors[edge] =
                            cornerColors[a] +
                            (cornerColors[b] - cornerColors[a]) * t
                    }

                    let row = mcTriangleTable[caseIndex]
                    var cursor = 0
                    while cursor + 2 < row.count, row[cursor] >= 0 {
                        let e0 = Int(row[cursor])
                        let e1 = Int(row[cursor + 1])
                        let e2 = Int(row[cursor + 2])

                        // TripoSR's density field is inside-positive. Reverse the
                        // standard table winding so exported faces point outward.
                        positions.append(edgePositions[e0])
                        positions.append(edgePositions[e2])
                        positions.append(edgePositions[e1])
                        outputColors.append(edgeColors[e0])
                        outputColors.append(edgeColors[e2])
                        outputColors.append(edgeColors[e1])
                        cursor += 3
                    }
                }
            }
        }

        return Mesh(positions: positions, colors: outputColors)
    }
}
