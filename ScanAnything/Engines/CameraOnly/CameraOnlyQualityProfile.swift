import Foundation

/// One source of truth for the camera-only Gaussian pipeline.
///
/// Real-time mobile quality profile. Source photos stay full-resolution, but the
/// learned geometry prior lets msplat converge with a much shorter optimization
/// budget suitable for an interactive 20–60 second build target.
struct CameraOnlyQualityProfile: Sendable, Equatable {
    let targetFrameCount: Int
    let minimumFrameCount: Int
    let maximumFrameCount: Int
    let minimumFeaturePoints: Int
    let maximumFeaturePoints: Int
    let minimumCaptureInterval: TimeInterval
    let minimumTranslation: Float
    let minimumRotation: Float

    let sharpnessWarmupFrames: Int
    let sharpnessFloorFraction: Float
    let azimuthSectorCount: Int
    let elevationBandCount: Int
    let minimumViewCoverage: Double

    let trainingIterations: Int32
    let shDegree: Int32
    let shDegreeInterval: Int32
    let ssimWeight: Float
    let numDownscales: Int32
    let resolutionSchedule: Int32
    let warmupLength: Int32
    let refineEvery: Int32
    let resetAlphaEvery: Int32
    let densifyGradThresh: Float
    let densifySizeThresh: Float
    let stopScreenSizeAt: Int32
    let stopDensifyAt: Int32
    let splitScreenSize: Float
    let datasetDownscaleFactor: Float

    // iPhone/iPad stability controls for the bounded real-time optimization pass.
    let imageCacheMB: Int
    let gpuSyncInterval: Int
    let memorySafetyHeadroomMB: Int
    let minimumEmergencyFinalizeIteration: Int
    let seriousThermalPauseMilliseconds: Int
    let criticalThermalPauseMilliseconds: Int

    let learnedDepthPriorEnabled: Bool
    let depthPriorKeyframeCount: Int
    let depthPriorMinimumAnchors: Int
    let depthPriorGridStride: Int
    let depthPriorMaximumPoints: Int
    let depthPriorVoxelSize: Float

    static let highDetail = CameraOnlyQualityProfile(
        targetFrameCount: 16,
        minimumFrameCount: 8,
        maximumFrameCount: 120,
        minimumFeaturePoints: 500,
        maximumFeaturePoints: 120_000,
        minimumCaptureInterval: 0.12,
        minimumTranslation: 0.020,
        minimumRotation: 0.050,
        sharpnessWarmupFrames: 8,
        sharpnessFloorFraction: 0.65,
        azimuthSectorCount: 12,
        elevationBandCount: 2,
        minimumViewCoverage: 0.25,
        trainingIterations: 5_000,
        shDegree: 3,
        shDegreeInterval: 1_000,
        ssimWeight: 0.20,
        numDownscales: 2,
        resolutionSchedule: 700,
        warmupLength: 200,
        refineEvery: 100,
        resetAlphaEvery: 30,
        densifyGradThresh: 0.00018,
        densifySizeThresh: 0.01,
        stopScreenSizeAt: 2_500,
        // Learned depth already gives the model a dense seed, so most topology
        // growth can finish early and the rest of the budget refines appearance.
        stopDensifyAt: 2_000,
        splitScreenSize: 0.045,
        datasetDownscaleFactor: 1.0,
        imageCacheMB: 192,
        gpuSyncInterval: 25,
        memorySafetyHeadroomMB: 320,
        minimumEmergencyFinalizeIteration: 3_500,
        seriousThermalPauseMilliseconds: 50,
        criticalThermalPauseMilliseconds: 250,
        learnedDepthPriorEnabled: true,
        depthPriorKeyframeCount: 10,
        depthPriorMinimumAnchors: 24,
        depthPriorGridStride: 10,
        depthPriorMaximumPoints: 70_000,
        depthPriorVoxelSize: 0.004
    )
}
