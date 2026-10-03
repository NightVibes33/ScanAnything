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
    let maximumProcessingSeconds: TimeInterval
    let maximumTrainingSeconds: TimeInterval
    let minimumUsefulTrainingIterations: Int
    let maximumSafeSplatCount: Int
    let minimumAcceptableSplatCount: Int

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
        maximumFeaturePoints: 60_000,
        minimumCaptureInterval: 0.12,
        minimumTranslation: 0.020,
        minimumRotation: 0.050,
        sharpnessWarmupFrames: 8,
        sharpnessFloorFraction: 0.65,
        azimuthSectorCount: 12,
        elevationBandCount: 2,
        minimumViewCoverage: 0.25,
        trainingIterations: 3_000,
        shDegree: 3,
        shDegreeInterval: 1_000,
        ssimWeight: 0.20,
        numDownscales: 1,
        resolutionSchedule: 500,
        warmupLength: 120,
        refineEvery: 100,
        resetAlphaEvery: 30,
        densifyGradThresh: 0.00018,
        densifySizeThresh: 0.01,
        stopScreenSizeAt: 1_200,
        // Learned depth already gives the model a dense seed, so most topology
        // growth can finish early and the rest of the budget refines appearance.
        stopDensifyAt: 900,
        splitScreenSize: 0.045,
        datasetDownscaleFactor: 1.0,
        imageCacheMB: 96,
        gpuSyncInterval: 10,
        memorySafetyHeadroomMB: 700,
        minimumEmergencyFinalizeIteration: 250,
        seriousThermalPauseMilliseconds: 0,
        criticalThermalPauseMilliseconds: 0,
        maximumProcessingSeconds: 55,
        maximumTrainingSeconds: 38,
        minimumUsefulTrainingIterations: 200,
        maximumSafeSplatCount: 350_000,
        minimumAcceptableSplatCount: 15_000,
        learnedDepthPriorEnabled: true,
        depthPriorKeyframeCount: 6,
        depthPriorMinimumAnchors: 24,
        depthPriorGridStride: 12,
        depthPriorMaximumPoints: 40_000,
        depthPriorVoxelSize: 0.005
    )

    /// Room scans prioritize reconstruction fidelity over the old sub-minute
    /// deadline. High-resolution source frames are trained at native dataset
    /// resolution, with a long densification window and a six-figure Gaussian
    /// floor so a sparse blob cloud can never be reported as a finished room.
    static let roomHighDetail = CameraOnlyQualityProfile(
        targetFrameCount: 96,
        minimumFrameCount: 48,
        maximumFrameCount: 120,
        minimumFeaturePoints: 4_000,
        maximumFeaturePoints: 180_000,
        minimumCaptureInterval: 0.10,
        minimumTranslation: 0.020,
        minimumRotation: 0.050,
        sharpnessWarmupFrames: 10,
        sharpnessFloorFraction: 0.72,
        azimuthSectorCount: 16,
        elevationBandCount: 3,
        minimumViewCoverage: 0.50,
        trainingIterations: 7_000,
        shDegree: 3,
        shDegreeInterval: 1_000,
        ssimWeight: 0.20,
        numDownscales: 1,
        resolutionSchedule: 1_000,
        warmupLength: 250,
        refineEvery: 100,
        resetAlphaEvery: 30,
        densifyGradThresh: 0.00012,
        densifySizeThresh: 0.01,
        stopScreenSizeAt: 3_500,
        stopDensifyAt: 4_500,
        splitScreenSize: 0.035,
        datasetDownscaleFactor: 1.0,
        imageCacheMB: 160,
        gpuSyncInterval: 10,
        memorySafetyHeadroomMB: 850,
        minimumEmergencyFinalizeIteration: 5_000,
        seriousThermalPauseMilliseconds: 0,
        criticalThermalPauseMilliseconds: 0,
        maximumProcessingSeconds: 900,
        maximumTrainingSeconds: 840,
        minimumUsefulTrainingIterations: 5_000,
        maximumSafeSplatCount: 900_000,
        minimumAcceptableSplatCount: 150_000,
        learnedDepthPriorEnabled: true,
        depthPriorKeyframeCount: 16,
        depthPriorMinimumAnchors: 32,
        depthPriorGridStride: 8,
        depthPriorMaximumPoints: 120_000,
        depthPriorVoxelSize: 0.003
    )

}
