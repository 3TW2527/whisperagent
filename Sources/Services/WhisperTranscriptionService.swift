import Foundation
import WhisperKit
import AVFoundation

public struct WhisperModelOption: Identifiable, Hashable, Sendable {
    public let id: String
    public let displayName: String
    public let sizeDescription: String
    public let speedBadge: String
    public let accuracyBadge: String
    public let description: String

    public static let availableModels: [WhisperModelOption] = [
        WhisperModelOption(
            id: "openai_whisper-tiny",
            displayName: "Whisper Tiny",
            sizeDescription: "~75 MB",
            speedBadge: "Lightning Fast",
            accuracyBadge: "Basic",
            description: "Fastest transcription, ideal for quick testing or clear audio with minimal background noise."
        ),
        WhisperModelOption(
            id: "openai_whisper-base",
            displayName: "Whisper Base (Recommended)",
            sizeDescription: "~140 MB",
            speedBadge: "Very Fast",
            accuracyBadge: "Good",
            description: "The best balance of speed, low memory usage, and high accuracy for typical lectures."
        ),
        WhisperModelOption(
            id: "openai_whisper-small",
            displayName: "Whisper Small",
            sizeDescription: "~460 MB",
            speedBadge: "Moderate",
            accuracyBadge: "High",
            description: "Significantly higher accuracy on accents and technical terminology, with moderate memory usage."
        ),
        WhisperModelOption(
            id: "distil-whisper_distil-large-v3",
            displayName: "Distil Large v3",
            sizeDescription: "~1.5 GB",
            speedBadge: "Fast",
            accuracyBadge: "State of the Art",
            description: "Distilled model delivering large-model accuracy at 6x speed on Apple Silicon."
        ),
        WhisperModelOption(
            id: "openai_whisper-large-v3-turbo",
            displayName: "Whisper Large v3 Turbo",
            sizeDescription: "~1.6 GB",
            speedBadge: "Moderate",
            accuracyBadge: "Maximum",
            description: "Highest possible transcription accuracy for noisy lecture halls and complex domain jargon."
        )
    ]
}

/// Thread-safe flag WhisperKit's progress callback can read to stop early.
final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock(); cancelled = true; lock.unlock()
    }
}

/// Runs transcription jobs in parallel, up to `AppSettings.maxConcurrentJobs` at once.
///
/// Each running job uses its own WhisperKit instance, because one instance can't safely transcribe
/// two files at the same time. Finished instances are kept idle and reused for the next job with
/// the same model.
@MainActor
public class WhisperTranscriptionService: ObservableObject {
    public static let shared = WhisperTranscriptionService()

    @Published public private(set) var jobs: [TranscriptionJob] = []

    @Published public var isDownloading: Bool = false
    @Published public var downloadProgress: Double = 0.0
    @Published public var currentDownloadModel: String = ""

    @Published public var downloadedModels: Set<String> = []

    private var runningTasks: [UUID: Task<Void, Never>] = [:]
    private var cancellationFlags: [UUID: CancellationFlag] = [:]
    private var idleKits: [String: [WhisperKit]] = [:]
    private var modelDownloads: [String: Task<Void, Error>] = [:]

    public init() {
        refreshDownloadedModels()
    }

    public var activeJobs: [TranscriptionJob] {
        jobs.filter { !$0.phase.isTerminal }
    }

    public var finishedJobs: [TranscriptionJob] {
        jobs.filter { $0.phase.isTerminal }
    }

    // MARK: - Models

    public func refreshDownloadedModels() {
        Task {
            var cached: Set<String> = []
            for model in WhisperModelOption.availableModels {
                if await checkIfModelIsDownloaded(model.id) {
                    cached.insert(model.id)
                }
            }
            self.downloadedModels = cached
        }
    }

    public func isModelDownloaded(_ modelId: String) -> Bool {
        downloadedModels.contains(modelId)
    }

    private func checkIfModelIsDownloaded(_ modelId: String) async -> Bool {
        // WhisperKit stores models in Application Support or Hugging Face cache
        let hubFolder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("huggingface/models/argmaxinc/whisperkit-coreml")

        if let hubFolder = hubFolder {
            let modelDir = hubFolder.appendingPathComponent(modelId)
            if FileManager.default.fileExists(atPath: modelDir.path) {
                return true
            }
        }

        // Also check default download base
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("argmaxinc/whisperkit-coreml/\(modelId)")
        if let cacheDir = cacheDir, FileManager.default.fileExists(atPath: cacheDir.path) {
            return true
        }

        return false
    }

    /// Downloads a model from Settings, showing progress there.
    public func downloadModel(variant: String) async throws {
        guard !isDownloading else { return }

        isDownloading = true
        downloadProgress = 0.0
        currentDownloadModel = variant

        defer {
            isDownloading = false
            currentDownloadModel = ""
            refreshDownloadedModels()
        }

        try await ensureModelDownloaded(variant) { [weak self] fraction in
            self?.downloadProgress = fraction
        }
    }

    /// Downloads a model once, even when several jobs ask for it at the same time.
    private func ensureModelDownloaded(_ variant: String, onProgress: @escaping @MainActor (Double) -> Void) async throws {
        if isModelDownloaded(variant) { return }
        if let existing = modelDownloads[variant] {
            try await existing.value
            return
        }
        let task = Task<Void, Error> {
            _ = try await WhisperKit.download(
                variant: variant,
                progressCallback: { (progress: Progress) in
                    let fraction = progress.fractionCompleted
                    Task { @MainActor in onProgress(fraction) }
                }
            )
        }
        modelDownloads[variant] = task
        defer { modelDownloads[variant] = nil }
        try await task.value
        downloadedModels.insert(variant)
    }

    private func checkOutKit(for variant: String) async throws -> WhisperKit {
        if var pool = idleKits[variant], let kit = pool.popLast() {
            idleKits[variant] = pool
            return kit
        }
        // Free idle instances of other models before loading a new one, to limit memory use.
        idleKits = idleKits.filter { $0.key == variant }
        return try await WhisperKit(model: variant)
    }

    private func returnKit(_ kit: WhisperKit, for variant: String) {
        let limit = AppSettings.shared.maxConcurrentJobs
        var pool = idleKits[variant] ?? []
        if pool.count < limit {
            pool.append(kit)
        }
        idleKits[variant] = pool
    }

    // MARK: - Job Queue

    /// Adds a job. Its recording name is reserved immediately, so it shows in the UI and parallel
    /// jobs for the same lecture get different numbers.
    @discardableResult
    public func enqueue(
        sourceURL: URL,
        courseID: String,
        lectureNumber: Int,
        customName: String?,
        modelVariant: String,
        trimStart: TimeInterval,
        trimEnd: TimeInterval
    ) throws -> TranscriptionJob {
        let storage = CourseStorageService.shared
        guard let course = storage.course(id: courseID) else { throw StorageError.courseNotFound }
        let slot = try storage.reserveRecording(courseID: courseID, lectureNumber: lectureNumber, customName: customName)

        let job = TranscriptionJob(
            sourceURL: sourceURL,
            courseID: courseID,
            courseName: course.name,
            lectureNumber: lectureNumber,
            customName: customName,
            modelVariant: modelVariant,
            trimStart: trimStart,
            trimEnd: trimEnd,
            formats: AppSettings.shared.orderedTranscriptFormats,
            slot: slot
        )
        jobs.append(job)
        pump()
        return job
    }

    public func cancel(jobID: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }), !jobs[index].phase.isTerminal else { return }
        cancellationFlags[jobID]?.cancel()
        runningTasks[jobID]?.cancel()
        if jobs[index].phase == .queued {
            finish(jobID: jobID, phase: .cancelled)
        }
    }

    /// Re-runs a failed or cancelled job with a fresh recording number.
    public func retry(jobID: UUID) {
        guard let old = jobs.first(where: { $0.id == jobID }), old.phase.isTerminal else { return }
        dismiss(jobID: jobID)
        do {
            try enqueue(
                sourceURL: old.sourceURL,
                courseID: old.courseID,
                lectureNumber: old.lectureNumber,
                customName: old.customName,
                modelVariant: old.modelVariant,
                trimStart: old.trimStart,
                trimEnd: old.trimEnd
            )
        } catch {
            var failed = old
            failed.phase = .failed(error: error.localizedDescription)
            jobs.append(failed)
        }
    }

    public func dismiss(jobID: UUID) {
        jobs.removeAll { $0.id == jobID && $0.phase.isTerminal }
    }

    public func clearFinished() {
        jobs.removeAll { $0.phase.isTerminal }
    }

    private func pump() {
        let limit = AppSettings.shared.maxConcurrentJobs
        while runningTasks.count < limit, let next = jobs.first(where: { $0.phase == .queued }) {
            let flag = CancellationFlag()
            cancellationFlags[next.id] = flag
            setPhase(next.id, .trimming)
            runningTasks[next.id] = Task { [weak self] in
                await self?.run(job: next, flag: flag)
            }
        }
    }

    private func setPhase(_ jobID: UUID, _ phase: JobPhase) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }), !jobs[index].phase.isTerminal else { return }
        jobs[index].phase = phase
    }

    private func finish(jobID: UUID, phase: JobPhase) {
        if let index = jobs.firstIndex(where: { $0.id == jobID }) {
            if !phase.isCompleted, let slot = jobs[index].slot {
                CourseStorageService.shared.releaseRecording(slot)
            }
            jobs[index].phase = phase
        }
        runningTasks[jobID] = nil
        cancellationFlags[jobID] = nil
        pump()
    }

    private func run(job: TranscriptionJob, flag: CancellationFlag) async {
        var trimmedAudio: URL?
        defer {
            if let trimmedAudio {
                AudioProcessingService.shared.deleteTemporaryAudio(at: trimmedAudio)
            }
        }

        do {
            guard let slot = job.slot else { throw StorageError.lectureNotFound }

            // 1. Trim audio
            let trimmed = try await AudioProcessingService.shared.trimAudio(
                sourceURL: job.sourceURL,
                startTime: job.trimStart,
                endTime: job.trimEnd
            )
            trimmedAudio = trimmed
            try checkCancelled(flag)

            // 2. Download model if needed
            if !isModelDownloaded(job.modelVariant) {
                setPhase(job.id, .downloadingModel(progress: 0))
                try await ensureModelDownloaded(job.modelVariant) { [weak self] fraction in
                    self?.setPhase(job.id, .downloadingModel(progress: fraction))
                }
            }
            try checkCancelled(flag)

            // 3. Transcribe on a dedicated WhisperKit instance
            setPhase(job.id, .loadingModel)
            let kit = try await checkOutKit(for: job.modelVariant)
            setPhase(job.id, .transcribing(progress: 0))

            let results: [TranscriptionResult]
            let progress = kit.progress
            do {
                results = try await kit.transcribe(
                    audioPath: trimmed.path,
                    callback: { [weak self] _ in
                        let fraction = progress.fractionCompleted
                        Task { @MainActor [weak self] in
                            self?.setPhase(job.id, .transcribing(progress: fraction))
                        }
                        return !flag.isCancelled
                    }
                )
                returnKit(kit, for: job.modelVariant)
            } catch {
                returnKit(kit, for: job.modelVariant)
                throw error
            }
            try checkCancelled(flag)

            // 4. Save every selected format plus timing data
            setPhase(job.id, .saving)
            let storage = CourseStorageService.shared
            guard let course = storage.course(id: job.courseID) else { throw StorageError.courseNotFound }
            guard let lecture = course.lecture(number: job.lectureNumber) else { throw StorageError.lectureNotFound }

            let segments = Self.segments(from: results)
            var context = TranscriptContext(
                courseName: course.name,
                courseCode: course.metadata.code,
                lectureNumber: lecture.number,
                lectureTitle: lecture.title,
                lectureDate: lecture.date,
                recordingNumber: slot.recordingNumber,
                sourceAudio: job.sourceURL.lastPathComponent,
                model: job.modelVariant
            )
            context.update(course: course, lecture: lecture)
            let files = try storage.saveRecording(
                slot: slot,
                document: SegmentsDocument(context: context, segments: segments),
                formats: job.formats,
                durationSeconds: max(0, job.trimEnd - job.trimStart)
            )
            finish(jobID: job.id, phase: .completed(files: files))
        } catch is CancellationError {
            finish(jobID: job.id, phase: .cancelled)
        } catch {
            finish(jobID: job.id, phase: flag.isCancelled ? .cancelled : .failed(error: error.localizedDescription))
        }
    }

    private func checkCancelled(_ flag: CancellationFlag) throws {
        if flag.isCancelled || Task.isCancelled {
            throw CancellationError()
        }
    }

    /// Converts WhisperKit output to app segments, dropping special tokens like `<|0.00|>`.
    static func segments(from results: [TranscriptionResult]) -> [TranscriptSegment] {
        var segments: [TranscriptSegment] = []
        for result in results {
            if result.segments.isEmpty {
                let text = cleanText(result.text)
                if !text.isEmpty {
                    segments.append(TranscriptSegment(start: 0, end: 0, text: text))
                }
                continue
            }
            for segment in result.segments {
                let text = cleanText(segment.text)
                if !text.isEmpty {
                    segments.append(TranscriptSegment(start: Double(segment.start), end: Double(segment.end), text: text))
                }
            }
        }
        return segments
    }

    static func cleanText(_ text: String) -> String {
        text.replacingOccurrences(of: "<\\|[^|]*\\|>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension JobPhase {
    var isCompleted: Bool {
        if case .completed = self { return true }
        return false
    }
}
