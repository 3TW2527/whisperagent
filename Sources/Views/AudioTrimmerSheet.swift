import SwiftUI
import AVFoundation

public struct AudioTrimmerSheet: View {
    public let audioURL: URL
    public let project: LectureProject
    public var onDismiss: () -> Void

    @StateObject private var transcriptionService = WhisperTranscriptionService.shared
    @StateObject private var appSettings = AppSettings.shared

    @State private var analysis: AudioAnalysisResult = .empty
    @State private var isLoadingAnalysis = true
    @State private var analysisError: String?

    @State private var trimStart: TimeInterval = 0
    @State private var trimEnd: TimeInterval = 0
    @State private var currentPlayhead: TimeInterval = 0

    @State private var isPlaying = false
    @State private var player: AVPlayer?
    @State private var timeObserverToken: Any?

    @State private var selectedModel: String = AppSettings.shared.selectedModelVariant
    @State private var isProcessing = false
    @State private var processingStatus = ""
    @State private var transcriptionError: String?

    public init(audioURL: URL, project: LectureProject, onDismiss: @escaping () -> Void) {
        self.audioURL = audioURL
        self.project = project
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Audio Trimmer & Transcription")
                        .font(.title2.bold())
                    Text("Source: \(audioURL.lastPathComponent)  •  Project: \(project.title)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button {
                    stopPlayback()
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
            .padding(.top)

            Divider()

            if isLoadingAnalysis {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Analyzing audio waveform and detecting silence...")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: 200)
            } else if let error = analysisError {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                        .font(.largeTitle)
                    Text("Could not analyze audio: \(error)")
                        .font(.callout)
                }
                .frame(maxWidth: .infinity, maxHeight: 200)
            } else {
                VStack(spacing: 16) {
                    // Waveform Display
                    WaveformView(
                        samples: analysis.samples,
                        duration: analysis.duration,
                        trimStart: $trimStart,
                        trimEnd: $trimEnd,
                        currentPlayhead: $currentPlayhead,
                        onSeek: { seekTime in
                            seekAudio(to: seekTime)
                        }
                    )
                    .padding(.horizontal)

                    // Timing & Silence Stats
                    HStack(spacing: 24) {
                        Label {
                            Text("Total: \(formatDuration(analysis.duration))")
                        } icon: {
                            Image(systemName: "clock")
                        }

                        Label {
                            Text("Trimmed: \(formatDuration(max(0, trimEnd - trimStart)))")
                                .fontWeight(.semibold)
                        } icon: {
                            Image(systemName: "scissors")
                        }

                        if analysis.leadingSilenceDuration > 0.5 {
                            Label {
                                Text("Leading Silence: \(formatDuration(analysis.leadingSilenceDuration))")
                                    .foregroundColor(.orange)
                            } icon: {
                                Image(systemName: "speaker.slash")
                                    .foregroundColor(.orange)
                            }
                        }

                        Spacer()

                        if analysis.leadingSilenceDuration > 0.5 && trimStart < analysis.detectedSpeechStart {
                            Button {
                                trimStart = analysis.detectedSpeechStart
                                seekAudio(to: trimStart)
                            } label: {
                                Label("Auto-Trim Initial Silence", systemImage: "wand.and.stars")
                                    .foregroundColor(.green)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .font(.caption)
                    .padding(.horizontal)

                    // Audio Playback Controls
                    HStack(spacing: 16) {
                        Button {
                            seekAudio(to: trimStart)
                        } label: {
                            Image(systemName: "backward.end.fill")
                        }
                        .help("Jump to Trim Start")

                        Button {
                            togglePlayback()
                        } label: {
                            Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 36))
                                .foregroundColor(.accentColor)
                        }
                        .buttonStyle(.plain)

                        Button {
                            seekAudio(to: trimEnd)
                        } label: {
                            Image(systemName: "forward.end.fill")
                        }
                        .help("Jump to Trim End")

                        Text("\(formatDuration(currentPlayhead)) / \(formatDuration(analysis.duration))")
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundColor(.secondary)

                        Spacer()
                    }
                    .padding(.horizontal)

                    Divider()

                    // Model Selection & Retention Notice
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Whisper Model:")
                                .font(.subheadline.bold())

                            Picker("", selection: $selectedModel) {
                                ForEach(WhisperModelOption.availableModels) { option in
                                    Text("\(option.displayName) (\(option.sizeDescription))")
                                        .tag(option.id)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 320)

                            if transcriptionService.isModelDownloaded(selectedModel) {
                                Label("Ready", systemImage: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.caption)
                            } else {
                                Label("Will download on first run", systemImage: "arrow.down.circle")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }

                            Spacer()
                        }

                        HStack(spacing: 8) {
                            Image(systemName: "info.circle")
                                .foregroundColor(.blue)
                            Text("The audio file will be trimmed and transcribed to Markdown (.md). The original audio will be discarded after transcription to save iCloud and disk space.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal)
                }
            }

            // Progress or Error
            if isProcessing {
                VStack(spacing: 8) {
                    ProgressView(value: transcriptionService.transcriptionProgress)
                        .progressViewStyle(.linear)
                    Text(processingStatus)
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
            } else if let error = transcriptionError {
                HStack {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundColor(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
                .padding(.horizontal)
            }

            Spacer()

            // Footer Action Bar
            HStack {
                Button("Cancel") {
                    stopPlayback()
                    onDismiss()
                }
                .keyboardShortcut(.cancelAction)
                .disabled(isProcessing)

                Spacer()

                Button {
                    startTranscription()
                } label: {
                    Label(isProcessing ? "Transcribing..." : "Transcribe & Generate Markdown", systemImage: "waveform.badge.magnifyingglass")
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isProcessing || isLoadingAnalysis || analysis.duration == 0)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(minWidth: 700, minHeight: 460)
        .onAppear {
            setupAudio()
        }
        .onDisappear {
            stopPlayback()
        }
    }

    private func setupAudio() {
        Task {
            do {
                let result = try await AudioProcessingService.shared.analyzeAudio(
                    url: audioURL,
                    silenceThresholdDB: appSettings.silenceThresholdDB
                )
                await MainActor.run {
                    self.analysis = result
                    self.trimStart = result.detectedSpeechStart
                    self.trimEnd = result.duration
                    self.currentPlayhead = result.detectedSpeechStart
                    self.isLoadingAnalysis = false

                    // Initialize AVPlayer for live preview
                    let item = AVPlayerItem(url: audioURL)
                    self.player = AVPlayer(playerItem: item)
                    self.addTimeObserver()
                    seekAudio(to: trimStart)
                }
            } catch {
                await MainActor.run {
                    self.analysisError = error.localizedDescription
                    self.isLoadingAnalysis = false
                }
            }
        }
    }

    private func addTimeObserver() {
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserverToken = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            let seconds = time.seconds
            if self.isPlaying {
                self.currentPlayhead = seconds
                if seconds >= self.trimEnd {
                    self.player?.pause()
                    self.isPlaying = false
                }
            }
        }
    }

    private func togglePlayback() {
        guard let player = player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            if currentPlayhead >= trimEnd {
                seekAudio(to: trimStart)
            }
            player.play()
            isPlaying = true
        }
    }

    private func seekAudio(to time: TimeInterval) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        currentPlayhead = time
    }

    private func stopPlayback() {
        player?.pause()
        isPlaying = false
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
            timeObserverToken = nil
        }
        player = nil
    }

    private func startTranscription() {
        stopPlayback()
        isProcessing = true
        transcriptionError = nil
        processingStatus = "Trimming audio file..."

        Task {
            do {
                // Step 1: Trim Audio to temporary file
                let trimmedAudioURL = try await AudioProcessingService.shared.trimAudio(
                    sourceURL: audioURL,
                    startTime: trimStart,
                    endTime: trimEnd
                )

                // Step 2: Download model if necessary
                if !transcriptionService.isModelDownloaded(selectedModel) {
                    await MainActor.run {
                        self.processingStatus = "Downloading \(selectedModel)..."
                    }
                    try await transcriptionService.downloadModel(variant: selectedModel)
                }

                // Step 3: Transcribe with WhisperKit
                await MainActor.run {
                    self.processingStatus = "Transcribing with WhisperKit..."
                }

                let markdown = try await transcriptionService.transcribe(
                    audioURL: trimmedAudioURL,
                    modelVariant: selectedModel,
                    lectureTitle: project.title,
                    originalRecordingName: audioURL.lastPathComponent
                )

                // Step 4: Save Markdown in Project Folder
                let baseName = audioURL.deletingPathExtension().lastPathComponent + "-transcript"
                _ = try ProjectStorageService.shared.saveTranscript(
                    markdown: markdown,
                    baseFileName: baseName,
                    project: project
                )

                await MainActor.run {
                    self.isProcessing = false
                    self.onDismiss()
                }
            } catch {
                await MainActor.run {
                    self.transcriptionError = "Transcription failed: \(error.localizedDescription)"
                    self.isProcessing = false
                }
            }
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
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
