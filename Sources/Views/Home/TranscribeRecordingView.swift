import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

/// The Transcribe Recording tool: transcribe one audio file with a Whisper model and save the transcript into any
/// folder, without adding it to a course or project.
struct TranscribeRecordingView: View {
    @ObservedObject private var service = WhisperTranscriptionService.shared
    @ObservedObject private var settings = AppSettings.shared

    @State private var recordingURL: URL?
    @State private var duration: TimeInterval = 0
    @State private var speechStart: TimeInterval = 0
    @State private var isAnalyzing = false
    @State private var analysisError: String?
    @State private var skipLeadingSilence = true

    @State private var customName = ""
    @State private var model = AppSettings.shared.selectedModelVariant
    @State private var formats: Set<TranscriptFormat> = AppSettings.shared.transcriptFormats
    @State private var isDropTargeted = false
    @State private var startError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                recordingCard
                if recordingURL != nil {
                    optionsCard
                }
                jobsSection
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .onDrop(of: VoiceMemosService.droppableTypes, isTargeted: $isDropTargeted) { providers in
            guard let provider = providers.first else { return false }
            VoiceMemosService.shared.loadDroppedFile(from: provider) { url in
                if let url { select(url) }
            }
            return true
        }
        .onAppear {
            service.refreshDownloadedModels()
        }
    }

    // MARK: - Recording

    private var recordingCard: some View {
        HStack(spacing: 14) {
            Image(systemName: recordingURL == nil ? "waveform.badge.plus" : "waveform")
                .font(.system(size: 30))
                .foregroundColor(isDropTargeted ? .accentColor : .orange)
                .frame(width: 40)
            VStack(alignment: .leading, spacing: 3) {
                if let url = recordingURL {
                    Text(url.lastPathComponent)
                        .font(.title3.bold())
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(recordingDetails)
                        .font(.caption)
                        .foregroundColor(analysisError == nil ? .secondary : .red)
                } else {
                    Text("Choose a recording")
                        .font(.title3.bold())
                    Text("Drop an audio file here, or choose one. The transcript is saved to a folder you pick, outside your courses and projects.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            if recordingURL != nil {
                Button {
                    if let url = recordingURL { CourseStorageService.shared.revealInFinder(url: url) }
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(.borderless)
                .help("Show the recording in Finder")
            }
            Button(recordingURL == nil ? "Choose Recording..." : "Choose Another...") {
                VoiceMemosService.shared.promptForAudioFile { url in
                    if let url { select(url) }
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(isDropTargeted ? Color.accentColor.opacity(0.12) : Color(NSColor.controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(isDropTargeted ? Color.accentColor : Color.primary.opacity(0.08)))
    }

    private var recordingDetails: String {
        if isAnalyzing { return "Reading the recording..." }
        if let analysisError { return "Couldn't read the recording: \(analysisError)" }
        return "Length \(TranscriptFormatter.clock(duration))"
    }

    // MARK: - Options

    private var optionsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            row("Save to") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: "folder")
                            .foregroundColor(.secondary)
                        Text(outputFolder.map(Self.displayPath) ?? "Choose a folder for the transcript")
                            .foregroundColor(outputFolder == nil ? .secondary : .primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(outputFolder?.path ?? "")
                        Spacer()
                        Button("Choose Folder...") { chooseFolder() }
                    }
                    if !settings.transcribeToolFolderPath.isEmpty && !isDroppedCopy {
                        Button("Save next to the recording instead") {
                            settings.transcribeToolFolderPath = ""
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                    }
                }
            }

            row("File name") {
                VStack(alignment: .leading, spacing: 4) {
                    TextField(defaultName, text: $customName)
                        .textFieldStyle(.roundedBorder)
                    Text("If a file with this name is already there, a number is added, e.g. \u{201C}\(baseName) 2\u{201D}.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            row("Model") {
                VStack(alignment: .leading, spacing: 4) {
                    Picker("", selection: $model) {
                        ForEach(WhisperModelOption.availableModels) { option in
                            Text(service.isModelDownloaded(option.id)
                                 ? option.displayName
                                 : "\(option.displayName) (downloads \(option.sizeDescription))")
                                .tag(option.id)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 360)
                    // A menu picker keeps the item titles it was first built with, so rebuild it when the set of
                    // downloaded models changes; otherwise it can keep saying a downloaded model still needs downloading.
                    .id(service.downloadedModels)
                    if !service.isModelDownloaded(model) {
                        Text("This model isn't downloaded yet. It's downloaded before transcribing, or pick one you already have.")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }

            row("Formats") {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(TranscriptFormat.allCases) { format in
                        Toggle(format.displayName, isOn: Binding(
                            get: { formats.contains(format) },
                            set: { isOn in
                                if isOn { formats.insert(format) } else { formats.remove(format) }
                            }
                        ))
                        .disabled(formats == [format])
                    }
                }
            }

            row("Start") {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Skip silence at the start", isOn: $skipLeadingSilence)
                        .disabled(speechStart < 1)
                    Text(speechStart < 1
                         ? "No silence found at the start."
                         : "Speech starts at \(TranscriptFormatter.clock(speechStart)). Whisper can invent text during long silences.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            HStack {
                if let startError {
                    Text(startError)
                        .font(.caption)
                        .foregroundColor(.red)
                }
                Spacer()
                Button {
                    startTranscription()
                } label: {
                    Label("Transcribe", systemImage: "waveform")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(isAnalyzing || analysisError != nil || duration <= 0 || outputFolder == nil || formats.isEmpty)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.08)))
    }

    private func row<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.subheadline.bold())
                .frame(width: 80, alignment: .leading)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Jobs

    private var folderJobs: [TranscriptionJob] {
        service.jobs.filter { $0.outputFolder != nil }
    }

    @ViewBuilder
    private var jobsSection: some View {
        if !folderJobs.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Transcriptions")
                    .font(.headline)
                ForEach(folderJobs) { job in
                    JobRowView(job: job, showsCourse: true)
                }
            }
        }
    }

    // MARK: - Actions

    /// The chosen folder, or the recording's own folder when none is chosen.
    private var outputFolder: URL? {
        if !settings.transcribeToolFolderPath.isEmpty {
            return URL(fileURLWithPath: settings.transcribeToolFolderPath, isDirectory: true)
        }
        // A recording dragged in as data (e.g. from Voice Memos) is a copy in the app's own folder, which is no place
        // for a transcript, so the user picks a folder instead.
        guard let recordingURL, !isDroppedCopy else { return nil }
        return recordingURL.deletingLastPathComponent()
    }

    private var isDroppedCopy: Bool {
        recordingURL.map(VoiceMemosService.shared.isDroppedRecordingCopy) ?? false
    }

    private var defaultName: String {
        recordingURL?.deletingPathExtension().lastPathComponent ?? "Transcript"
    }

    private var baseName: String {
        let trimmed = customName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultName : trimmed
    }

    private func select(_ url: URL) {
        guard VoiceMemosService.shared.isAudioFile(url: url) else {
            startError = "\u{201C}\(url.lastPathComponent)\u{201D} isn't a supported audio file."
            return
        }
        recordingURL = url
        customName = ""
        startError = nil
        analysisError = nil
        duration = 0
        speechStart = 0
        isAnalyzing = true
        let threshold = settings.silenceThresholdDB
        Task {
            do {
                let result = try await AudioProcessingService.shared.analyzeAudio(url: url, silenceThresholdDB: threshold)
                guard recordingURL == url else { return }
                if result.duration > 0 {
                    duration = result.duration
                    speechStart = result.detectedSpeechStart
                } else {
                    duration = try await AVURLAsset(url: url).load(.duration).seconds
                }
            } catch {
                guard recordingURL == url else { return }
                analysisError = error.localizedDescription
            }
            if recordingURL == url { isAnalyzing = false }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose where to save transcripts"
        panel.prompt = "Choose"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = outputFolder
        panel.begin { response in
            if response == .OK, let url = panel.url {
                settings.transcribeToolFolderPath = url.path
            }
        }
    }

    private func startTranscription() {
        guard let recordingURL, let outputFolder else { return }
        startError = nil
        let start = skipLeadingSilence && speechStart >= 1 ? speechStart : 0
        let trimmed = customName.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try service.enqueue(
                sourceURL: recordingURL,
                destination: .folder(outputFolder),
                customName: trimmed.isEmpty ? nil : trimmed,
                modelVariant: model,
                trimStart: start,
                trimEnd: duration,
                formats: TranscriptFormat.allCases.filter { formats.contains($0) }
            )
            self.recordingURL = nil
            customName = ""
        } catch {
            startError = error.localizedDescription
        }
    }

    /// The path with the home folder shortened to `~`.
    private static func displayPath(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = url.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}
