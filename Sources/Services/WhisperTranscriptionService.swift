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

@MainActor
public class WhisperTranscriptionService: ObservableObject {
    public static let shared = WhisperTranscriptionService()

    @Published public var activeJob: TranscriptionJob?
    @Published public var recentCompletedJob: TranscriptionJob?

    @Published public var isDownloading: Bool = false
    @Published public var downloadProgress: Double = 0.0
    @Published public var currentDownloadModel: String = ""

    @Published public var isTranscribing: Bool = false
    @Published public var transcriptionProgress: Double = 0.0
    @Published public var transcriptionStatusText: String = ""

    @Published public var downloadedModels: Set<String> = []

    private var activeWhisperKit: WhisperKit?
    private var activeModelLoaded: String?

    public init() {
        refreshDownloadedModels()
    }

    public func refreshDownloadedModels() {
        Task {
            var cached: Set<String> = []
            for model in WhisperModelOption.availableModels {
                let isDownloaded = await checkIfModelIsDownloaded(model.id)
                if isDownloaded {
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

        do {
            _ = try await WhisperKit.download(
                variant: variant,
                progressCallback: { [weak self] (progress: Progress) in
                    Task { @MainActor [weak self] in
                        self?.downloadProgress = progress.fractionCompleted
                    }
                }
            )
            downloadedModels.insert(variant)
        } catch {
            print("Model download error for \(variant): \(error)")
            throw error
        }
    }

    public func startBackgroundJob(
        sourceURL: URL,
        project: LectureProject,
        modelVariant: String,
        trimStart: TimeInterval,
        trimEnd: TimeInterval
    ) {
        let job = TranscriptionJob(
            sourceURL: sourceURL,
            originalFileName: sourceURL.lastPathComponent,
            projectID: project.id,
            projectTitle: project.title,
            modelVariant: modelVariant,
            trimStart: trimStart,
            trimEnd: trimEnd,
            phase: .trimming
        )
        self.activeJob = job
        self.recentCompletedJob = nil

        Task {
            do {
                // 1. Trim audio
                let trimmedAudio = try await AudioProcessingService.shared.trimAudio(
                    sourceURL: sourceURL,
                    startTime: trimStart,
                    endTime: trimEnd
                )

                // 2. Download model if needed
                if !isModelDownloaded(modelVariant) {
                    await MainActor.run {
                        self.activeJob?.phase = .downloadingModel(progress: 0.0)
                    }
                    _ = try await WhisperKit.download(
                        variant: modelVariant,
                        progressCallback: { [weak self] (progress: Progress) in
                            Task { @MainActor [weak self] in
                                self?.activeJob?.phase = .downloadingModel(progress: progress.fractionCompleted)
                            }
                        }
                    )
                    await MainActor.run {
                        self.downloadedModels.insert(modelVariant)
                    }
                }

                // 3. Transcribe with WhisperKit
                await MainActor.run {
                    self.activeJob?.phase = .transcribing(progress: 0.0)
                }

                let whisperKit: WhisperKit
                if let active = self.activeWhisperKit, self.activeModelLoaded == modelVariant {
                    whisperKit = active
                } else {
                    let kit = try await WhisperKit(model: modelVariant)
                    self.activeWhisperKit = kit
                    self.activeModelLoaded = modelVariant
                    whisperKit = kit
                }

                let results = try await whisperKit.transcribe(
                    audioPath: trimmedAudio.path,
                    callback: { [weak self] _ in
                        Task { @MainActor [weak self] in
                            if let kit = self?.activeWhisperKit {
                                self?.activeJob?.phase = .transcribing(progress: kit.progress.fractionCompleted)
                            }
                        }
                        return true
                    }
                )

                // 4. Save Markdown
                let markdown = formatResultsToMarkdown(
                    results: results,
                    lectureTitle: project.title,
                    originalRecordingName: sourceURL.lastPathComponent,
                    modelName: modelVariant
                )

                let baseName = sourceURL.deletingPathExtension().lastPathComponent + "-transcript"
                let savedURL = try ProjectStorageService.shared.saveTranscript(
                    markdown: markdown,
                    baseFileName: baseName,
                    project: project
                )

                // 5. Cleanup temporary trimmed audio
                AudioProcessingService.shared.deleteTemporaryAudio(at: trimmedAudio)

                await MainActor.run {
                    var finishedJob = job
                    finishedJob.phase = .completed(transcriptURL: savedURL)
                    self.recentCompletedJob = finishedJob
                    self.activeJob = nil
                    ProjectStorageService.shared.reloadProjects()
                }
            } catch {
                await MainActor.run {
                    var failedJob = job
                    failedJob.phase = .failed(error: error.localizedDescription)
                    self.recentCompletedJob = failedJob
                    self.activeJob = nil
                }
            }
        }
    }

    public func transcribe(
        audioURL: URL,
        modelVariant: String,
        lectureTitle: String,
        originalRecordingName: String
    ) async throws -> String {
        isTranscribing = true
        transcriptionProgress = 0.0
        transcriptionStatusText = "Preparing Whisper model..."

        defer {
            isTranscribing = false
            transcriptionProgress = 0.0
            transcriptionStatusText = ""
            // Clean up temporary audio file immediately
            AudioProcessingService.shared.deleteTemporaryAudio(at: audioURL)
        }

        // Load or re-initialize WhisperKit if model changed
        let whisperKit: WhisperKit
        if let active = activeWhisperKit, activeModelLoaded == modelVariant {
            whisperKit = active
        } else {
            transcriptionStatusText = "Loading \(modelVariant)..."
            let kit = try await WhisperKit(model: modelVariant)
            self.activeWhisperKit = kit
            self.activeModelLoaded = modelVariant
            whisperKit = kit
        }

        transcriptionStatusText = "Transcribing audio with Apple Neural Engine..."

        let results = try await whisperKit.transcribe(
            audioPath: audioURL.path,
            callback: { [weak self] _ in
                Task { @MainActor [weak self] in
                    if let kit = self?.activeWhisperKit {
                        let fraction = kit.progress.fractionCompleted
                        self?.transcriptionProgress = fraction
                        self?.transcriptionStatusText = "Transcribing: \(Int(fraction * 100))%"
                    }
                }
                return true
            }
        )

        transcriptionStatusText = "Formatting Markdown transcript..."

        // Generate formatted markdown
        let markdown = formatResultsToMarkdown(
            results: results,
            lectureTitle: lectureTitle,
            originalRecordingName: originalRecordingName,
            modelName: modelVariant
        )

        return markdown
    }

    private func formatResultsToMarkdown(
        results: [TranscriptionResult],
        lectureTitle: String,
        originalRecordingName: String,
        modelName: String
    ) -> String {
        var lines: [String] = []

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .full
        dateFormatter.timeStyle = .short
        let timestamp = dateFormatter.string(from: Date())

        lines.append("# \(lectureTitle) - Lecture Transcript")
        lines.append("")
        lines.append("> **Generated**: \(timestamp)  ")
        lines.append("> **Source**: `\(originalRecordingName)`  ")
        lines.append("> **Model**: `\(modelName)` via WhisperKit  ")
        lines.append("")
        lines.append("---")
        lines.append("")

        var fullText = ""
        var segmentsCount = 0

        for result in results {
            fullText += result.text + " "
            if let segments = result.segments as [TranscriptionSegment]? {
                for segment in segments {
                    segmentsCount += 1
                    let startFormatted = formatTime(Double(segment.start))
                    let endFormatted = formatTime(Double(segment.end))
                    let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty {
                        lines.append("**[\(startFormatted) - \(endFormatted)]** \(text)")
                        lines.append("")
                    }
                }
            }
        }

        // If no segments were found, output the accumulated text
        if segmentsCount == 0 && !fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("## Full Transcript")
            lines.append("")
            lines.append(fullText.trimmingCharacters(in: .whitespacesAndNewlines))
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    private func formatTime(_ seconds: Double) -> String {
        let totalSeconds = Int(seconds)
        let hrs = totalSeconds / 3600
        let mins = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        if hrs > 0 {
            return String(format: "%02d:%02d:%02d", hrs, mins, secs)
        } else {
            return String(format: "%02d:%02d", mins, secs)
        }
    }
}
