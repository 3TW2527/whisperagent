import SwiftUI
import AVFoundation

public struct AudioTrimmerSheet: View {
    public let audioURL: URL
    public let course: Course
    public var onDismiss: () -> Void

    /// Sentinel lecture value meaning "create a new lecture".
    private static let newLectureTag = 0

    @ObservedObject private var transcriptionService = WhisperTranscriptionService.shared
    @ObservedObject private var appSettings = AppSettings.shared
    @ObservedObject private var storage = CourseStorageService.shared

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
    @State private var transcriptionError: String?

    @State private var lectureTag: Int
    @State private var newLectureTitle = ""
    @State private var newLectureDate: Date
    @State private var customName = ""

    public init(audioURL: URL, course: Course, initialLecture: Int?, onDismiss: @escaping () -> Void) {
        self.audioURL = audioURL
        self.course = course
        self.onDismiss = onDismiss
        let fallback = course.lectures.last?.number ?? Self.newLectureTag
        _lectureTag = State(initialValue: initialLecture.flatMap { course.lecture(number: $0)?.number } ?? fallback)
        // A new lecture defaults to when the audio was recorded.
        let values = try? audioURL.resourceValues(forKeys: [.creationDateKey])
        _newLectureDate = State(initialValue: values?.creationDate ?? Date())
    }

    /// The course as currently loaded, so numbering reflects lectures created meanwhile.
    private var liveCourse: Course {
        storage.course(id: course.id) ?? course
    }

    private var proposedName: String {
        if lectureTag == Self.newLectureTag {
            return String(format: "%@_L%02d_R1", liveCourse.filePrefix, liveCourse.metadata.nextLectureNumber)
        }
        return storage.proposedRecordingName(courseID: course.id, lectureNumber: lectureTag) ?? ""
    }

    public var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Audio Trimmer & Transcription")
                        .font(.title2.bold())
                    Text("Source: \(audioURL.lastPathComponent)  •  Course: \(course.displayName)")
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

                    // Destination: lecture and file name
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Lecture:")
                                .font(.subheadline.bold())
                                .frame(width: 110, alignment: .leading)
                            Picker("", selection: $lectureTag) {
                                ForEach(liveCourse.lectures.reversed()) { lecture in
                                    Text("\(lecture.label) · \(lecture.title.isEmpty ? DateFormats.display.string(from: lecture.date) : lecture.title)")
                                        .tag(lecture.number)
                                }
                                Divider()
                                Text("New lecture (L\(String(format: "%02d", liveCourse.metadata.nextLectureNumber)))")
                                    .tag(Self.newLectureTag)
                            }
                            .labelsHidden()
                            .frame(width: 320)
                            Spacer()
                        }

                        if lectureTag == Self.newLectureTag {
                            HStack {
                                Text("")
                                    .frame(width: 110)
                                TextField("Title (optional)", text: $newLectureTitle)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 200)
                                DatePicker("", selection: $newLectureDate)
                                    .labelsHidden()
                                Spacer()
                            }
                        }

                        HStack {
                            Text("File name:")
                                .font(.subheadline.bold())
                                .frame(width: 110, alignment: .leading)
                            TextField(proposedName, text: $customName)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 320)
                            Text(".\(appSettings.orderedTranscriptFormats.map(\.fileExtension).joined(separator: " / ."))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                        }

                        HStack {
                            Text("Whisper model:")
                                .font(.subheadline.bold())
                                .frame(width: 110, alignment: .leading)

                            Picker("", selection: $selectedModel) {
                                ForEach(WhisperModelOption.availableModels) { option in
                                    Text("\(option.displayName) (\(option.sizeDescription))")
                                        .tag(option.id)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(width: 320)

                            if transcriptionService.isModelDownloaded(selectedModel) {
                                Label("Ready", systemImage: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.caption)
                            } else {
                                Label("Downloads on first run", systemImage: "arrow.down.circle")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }

                            Spacer()
                        }

                        HStack(spacing: 8) {
                            Image(systemName: "info.circle")
                                .foregroundColor(.blue)
                            Text("Leave the file name empty to use the automatic name. Transcription runs in the background, and you can queue more recordings straight away. Your original audio file isn't changed.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal)
                }
            }

            if let error = transcriptionError {
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

                Spacer()

                Button {
                    startTranscription()
                } label: {
                    Label("Start Transcription", systemImage: "waveform.badge.magnifyingglass")
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoadingAnalysis || analysis.duration == 0)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(minWidth: 720, minHeight: 520)
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
            Task { @MainActor in
                if self.isPlaying {
                    self.currentPlayhead = seconds
                    if seconds >= self.trimEnd {
                        self.player?.pause()
                        self.isPlaying = false
                    }
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
        transcriptionError = nil
        do {
            var lectureNumber = lectureTag
            if lectureTag == Self.newLectureTag {
                lectureNumber = try storage.addLecture(courseID: course.id, title: newLectureTitle, date: newLectureDate).number
                lectureTag = lectureNumber
            }
            let trimmedName = customName.trimmingCharacters(in: .whitespacesAndNewlines)
            try transcriptionService.enqueue(
                sourceURL: audioURL,
                courseID: course.id,
                lectureNumber: lectureNumber,
                customName: trimmedName.isEmpty ? nil : trimmedName,
                modelVariant: selectedModel,
                trimStart: trimStart,
                trimEnd: trimEnd
            )
            stopPlayback()
            onDismiss()
        } catch {
            transcriptionError = error.localizedDescription
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
