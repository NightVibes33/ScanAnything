import Foundation

/// Shared processing progress for every reconstruction backend.
struct ReconstructionProgress: Equatable, Sendable {
    var fraction: Double = 0
    var stage: ReconstructionStage?
    var estimatedRemaining: TimeInterval?

    /// Live countdown. The number is intentionally precise because it is fed by
    /// measured throughput or a framework-provided estimate, not a fixed animation.
    var remainingText: String? {
        ProcessingTimeText.remaining(estimatedRemaining)
    }
}

enum ProcessingTimeText {
    static func remaining(_ interval: TimeInterval?) -> String? {
        guard let interval, interval.isFinite, interval > 0 else { return nil }
        let seconds = max(1, Int(ceil(interval)))
        if seconds < 60 {
            return "\(seconds)s"
        }

        let minutes = seconds / 60
        let remainder = seconds % 60
        return String(format: "%d:%02d", minutes, remainder)
    }
}

enum ReconstructionStage: Int, Equatable, Sendable, CaseIterable, Identifiable {
    case preProcessing
    case imageAlignment
    case pointCloudGeneration
    case meshGeneration
    case textureMapping
    case optimization

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .preProcessing: "Preparing images"
        case .imageAlignment: "Aligning views"
        case .pointCloudGeneration: "Building geometry"
        case .meshGeneration: "Building mesh"
        case .textureMapping: "Applying textures"
        case .optimization: "Optimizing model"
        }
    }

    var symbolName: String {
        switch self {
        case .preProcessing: "photo.stack"
        case .imageAlignment: "camera.metering.matrix"
        case .pointCloudGeneration: "aqi.medium"
        case .meshGeneration: "grid"
        case .textureMapping: "paintbrush"
        case .optimization: "wand.and.sparkles"
        }
    }

    var isLongRunning: Bool {
        self == .imageAlignment || self == .meshGeneration
    }
}
