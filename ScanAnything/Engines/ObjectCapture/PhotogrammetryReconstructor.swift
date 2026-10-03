import Foundation
import RealityKit
import os

/// Wraps `PhotogrammetrySession`: a directory of stills in, a USDZ out.
///
/// Runs entirely on device. It is CPU/GPU heavy and iOS will suspend it if the
/// app is backgrounded, which is why the caller keeps the screen awake and the
/// checkpoint directory is on disk.
struct PhotogrammetryReconstructor {
    private static let logger = Logger(subsystem: "com.example.ObjectScanner", category: "photogrammetry")

    /// The model plus what the solver had to say about the input that produced it.
    struct Output {
        let modelURL: URL
        /// Nil when the poses request was unavailable or failed — it is a
        /// diagnostic, never a requirement.
        let poses: PoseDiagnostics?
    }

    /// - Parameters:
    ///   - maskRect: region of every frame that contains the object, in 0…1 image
    ///     coordinates. Only meaningful when the device was stationary — see
    ///     `MaskedSampleSequence`. Nil feeds the images directly and lets the
    ///     session work out the object itself.
    ///   - enableObjectMasking: lets the session segment a single subject out of
    ///     each frame. Right for an object on a table, actively wrong for a room —
    ///     there the room *is* the subject, and asking for an object gets part of it
    ///     cut away.
    ///   - framing: whether the cameras surrounded the subject or stood inside it.
    ///     Decides which pose measurements are meaningful.
    ///   - onWarning: non-fatal problems worth telling the user about, such as
    ///     masking being unavailable.
    ///   - onProgress: merged progress, always delivered on the main actor.
    func reconstruct(
        workspace: ScanWorkspace,
        detail: ReconstructionDetail,
        maskRect: CGRect? = nil,
        enableObjectMasking: Bool = true,
        framing: PoseDiagnostics.Framing = .orbit,
        maximumInputImages: Int = 28,
        onWarning: @escaping @MainActor (String) -> Void = { _ in },
        onProgress: @escaping @MainActor (ReconstructionProgress) -> Void
    ) async throws -> Output {

        guard PhotogrammetrySession.isSupported else {
            throw ScanEngineError.reconstructionFailed(String(localized: "Bu cihaz cihaz-üstü fotogrametriyi desteklemiyor."))
        }

        let allImageURLs = ((try? FileManager.default.contentsOfDirectory(
            at: workspace.imagesURL,
            includingPropertiesForKeys: nil
        )) ?? [])
            .filter { !$0.lastPathComponent.hasPrefix(".") }
            // Capture order is the orbit order, which is what `.sequential` promises
            // the solver — directory enumeration order is not.
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        let imageURLs = Self.evenlySample(
            allImageURLs,
            maximumCount: max(8, maximumInputImages)
        )
        let imageCount = imageURLs.count
        guard imageCount > 0 else { throw ScanEngineError.noImagesCaptured }

        var configuration = PhotogrammetrySession.Configuration(checkpointDirectory: workspace.checkpointURL)
        // Guided capture and turntable capture both write images in orbit order,
        // which spares the solver an all-pairs matching search.
        configuration.sampleOrdering = .sequential
        configuration.featureSensitivity = .normal
        configuration.isObjectMaskingEnabled = enableObjectMasking

        // Remove a stale model from a previous attempt; the session refuses to
        // overwrite and the error it throws is opaque.
        try? FileManager.default.removeItem(at: workspace.modelURL)

        // Probe one file before committing to the sample path. `PhotogrammetrySample`
        // does not necessarily read every HEIC we produce, and an earlier version
        // swallowed those failures with `try?` — leaving an empty sequence and an
        // opaque session error. Better to find out on one file than on eighty.
        var effectiveMask = maskRect
        if maskRect != nil, let probe = imageURLs.first {
            do {
                _ = try await PhotogrammetrySample(contentsOf: probe)
            } catch {
                effectiveMask = nil
                Self.logger.error("Örnek okunamadı, maske devre dışı: \(error.localizedDescription, privacy: .public)")
                await onWarning("Maske uygulanamadı, arka plan dahil edildi: \(error.localizedDescription)")
            }
        }

        do {
            return try await run(
                workspace: workspace,
                imageURLs: imageURLs,
                imageCount: imageCount,
                detail: detail,
                maskRect: effectiveMask,
                configuration: configuration,
                framing: framing,
                onProgress: onProgress
            )
        } catch where effectiveMask != nil {
            // Masking is an optimisation, not the point. If the masked run fails for
            // any reason, fall back to the plain folder path so the user still gets a
            // model instead of nothing.
            Self.logger.error("Maskeli çalışma başarısız, maskesiz deneniyor")
            await onWarning(String(localized: "Maskeli işleme başarısız oldu, maskesiz tekrar denendi."))
            try? FileManager.default.removeItem(at: workspace.modelURL)
            return try await run(
                workspace: workspace,
                imageURLs: imageURLs,
                imageCount: imageCount,
                detail: detail,
                maskRect: nil,
                configuration: configuration,
                framing: framing,
                onProgress: onProgress
            )
        }
    }

    private static func evenlySample(
        _ urls: [URL],
        maximumCount: Int
    ) -> [URL] {
        guard maximumCount > 0, urls.count > maximumCount else { return urls }
        guard maximumCount > 1 else { return [urls[0]] }

        let step = Double(urls.count - 1) / Double(maximumCount - 1)
        return (0..<maximumCount).map { index in
            let sourceIndex = min(
                urls.count - 1,
                Int((Double(index) * step).rounded())
            )
            return urls[sourceIndex]
        }
    }

    private func run(
        workspace: ScanWorkspace,
        imageURLs: [URL],
        imageCount: Int,
        detail: ReconstructionDetail,
        maskRect: CGRect?,
        configuration: PhotogrammetrySession.Configuration,
        framing: PoseDiagnostics.Framing,
        onProgress: @escaping @MainActor (ReconstructionProgress) -> Void
    ) async throws -> Output {

        let session: PhotogrammetrySession
        do {
            // Always use the streaming sample sequence. Besides supporting an
            // optional mask, this lets us cap the exact images given to the solver
            // without copying a second folder of full-resolution photos.
            session = try PhotogrammetrySession(
                input: MaskedSampleSequence(
                    imageURLs: imageURLs,
                    normalizedRect: maskRect
                ),
                configuration: configuration
            )
        } catch {
            throw ScanEngineError.reconstructionFailed(error.localizedDescription)
        }

        let modelRequest = PhotogrammetrySession.Request.modelFile(
            url: workspace.modelURL,
            detail: detail.apiDetail
        )
        // The poses request rides along on alignment work the session already does,
        // so it costs almost nothing and turns "kalite kötü" into three numbers.
        try session.process(requests: [modelRequest, .poses])

        // Fraction and stage arrive on two different outputs and interleave, so
        // both are accumulated here and emitted as one value.
        var progress = ReconstructionProgress()
        var diagnostics: PoseDiagnostics?
        let startedAt = ProcessInfo.processInfo.systemUptime
        var smoothedRemaining: TimeInterval?

        func smoothRemaining(_ value: TimeInterval) -> TimeInterval {
            let safe = max(0.25, value)
            if let previous = smoothedRemaining {
                let next = previous * 0.65 + safe * 0.35
                smoothedRemaining = next
                return next
            }
            smoothedRemaining = safe
            return safe
        }

        func measuredRemaining(for fraction: Double) -> TimeInterval? {
            guard fraction > 0.02, fraction < 1 else { return nil }
            let elapsed = max(
                0.001,
                ProcessInfo.processInfo.systemUptime - startedAt
            )
            return elapsed * (1 - fraction) / fraction
        }

        for try await output in session.outputs {
            switch output {
            case .requestProgress(let request, let fraction):
                // Two requests report progress independently; showing both would
                // make the bar jump backwards.
                guard request == modelRequest else { break }
                progress.fraction = fraction
                if let measured = measuredRemaining(for: fraction) {
                    progress.estimatedRemaining = smoothRemaining(measured)
                }
                await onProgress(progress)

            case .requestProgressInfo(let request, let info):
                guard request == modelRequest else { break }
                progress.stage = info.processingStage.flatMap(ReconstructionStage.init)
                if let remaining = info.estimatedRemainingTime,
                   remaining.isFinite,
                   remaining > 0 {
                    progress.estimatedRemaining = smoothRemaining(remaining)
                }
                await onProgress(progress)

            case .requestComplete(let request, let result):
                if case .poses(let poses) = result {
                    diagnostics = PoseDiagnostics(poses: poses, totalSamples: imageCount, framing: framing)
                }
                guard request == modelRequest else { break }
                progress.fraction = 1
                progress.estimatedRemaining = 0
                await onProgress(progress)

            case .processingComplete:
                Self.logger.info("Yeniden yapılandırma tamamlandı: \(imageCount, privacy: .public) görüntü")
                if let diagnostics {
                    Self.logger.info("Poz teşhisi: \(diagnostics.summaryText, privacy: .public)")
                }
                return Output(modelURL: workspace.modelURL, poses: diagnostics)

            case .requestError(let request, let error):
                // A failed poses request must not cost the user their model.
                guard request == modelRequest else {
                    Self.logger.error("Poz isteği başarısız: \(error.localizedDescription, privacy: .public)")
                    break
                }
                throw ScanEngineError.reconstructionFailed(error.localizedDescription)

            case .processingCancelled:
                throw ScanEngineError.cancelled

            case .invalidSample(let id, let reason):
                Self.logger.debug("Geçersiz örnek \(id, privacy: .public): \(reason, privacy: .public)")

            case .skippedSample, .automaticDownsampling, .inputComplete, .stitchingIncomplete:
                break

            @unknown default:
                break
            }
        }

        // The stream ended without `.processingComplete`. Trust the file system
        // rather than guessing.
        guard FileManager.default.fileExists(atPath: workspace.modelURL.path(percentEncoded: false)) else {
            throw ScanEngineError.reconstructionFailed(String(localized: "Oturum model üretmeden sona erdi."))
        }
        return Output(modelURL: workspace.modelURL, poses: diagnostics)
    }
}

private extension ReconstructionDetail {
    /// See `ReconstructionDetail`: iOS declares only `.reduced`.
    var apiDetail: PhotogrammetrySession.Request.Detail {
        switch self {
        case .reduced: .reduced
        }
    }
}

private extension ReconstructionStage {
    init?(_ stage: PhotogrammetrySession.Output.ProcessingStage) {
        switch stage {
        case .preProcessing: self = .preProcessing
        case .imageAlignment: self = .imageAlignment
        case .pointCloudGeneration: self = .pointCloudGeneration
        case .meshGeneration: self = .meshGeneration
        case .textureMapping: self = .textureMapping
        case .optimization: self = .optimization
        @unknown default: return nil
        }
    }
}
