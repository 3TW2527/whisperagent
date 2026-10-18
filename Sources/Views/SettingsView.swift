import SwiftUI

public struct SettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var transcriptionService = WhisperTranscriptionService.shared
    public var onDismiss: () -> Void

    public init(onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Preferences")
                    .font(.title2.bold())
                Spacer()
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    // Storage Location Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Root Storage Location")
                            .font(.headline)

                        Text("Each course is a subfolder of this directory, next to the generated INDEX.md and AGENTS.md files that AI assistants read. Choose a local folder, or an iCloud Drive folder to sync across devices.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Image(systemName: settings.isUsingiCloud ? "icloud.fill" : "folder.fill")
                                        .foregroundColor(settings.isUsingiCloud ? .blue : .accentColor)
                                    Text(settings.rootFolderURL.path)
                                        .font(.system(.subheadline, design: .monospaced))
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }

                                if settings.isUsingiCloud {
                                    Text("Synced via iCloud Drive")
                                        .font(.caption2)
                                        .foregroundColor(.green)
                                }
                            }

                            Spacer()

                            Button("Choose Folder...") {
                                chooseStorageFolder()
                            }

                            Button("Use iCloud Default") {
                                settings.setCustomRootDirectory(AppSettings.defaultRootDirectory())
                                CourseStorageService.shared.reload()
                            }
                        }
                        .padding(12)
                        .background(Color(NSColor.controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    Divider()

                    // File Ingestion Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Adding Materials (Copy vs Move)")
                            .font(.headline)

                        Text("Choose whether files dragged into a course are copied or moved from their original location.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Picker("Default Action:", selection: $settings.fileIngestionAction) {
                            ForEach(FileIngestionAction.allCases) { action in
                                Text(action.description).tag(action)
                            }
                        }
                        .pickerStyle(.radioGroup)
                    }

                    Divider()

                    // Whisper Models Section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Whisper Speech-to-Text Models")
                                .font(.headline)
                            Spacer()
                            Text("Apple Neural Engine Accelerated")
                                .font(.caption2)
                                .foregroundColor(.green)
                        }

                        Text("Models run 100% locally on your Mac using CoreML and Apple Silicon. Select which model to use and manage downloaded model files.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        VStack(spacing: 10) {
                            ForEach(WhisperModelOption.availableModels) { model in
                                ModelRowView(
                                    model: model,
                                    isSelected: settings.selectedModelVariant == model.id,
                                    isDownloaded: transcriptionService.isModelDownloaded(model.id),
                                    isDownloading: transcriptionService.isDownloading && transcriptionService.currentDownloadModel == model.id,
                                    downloadProgress: transcriptionService.downloadProgress,
                                    onSelect: {
                                        settings.selectedModelVariant = model.id
                                    },
                                    onDownload: {
                                        Task {
                                            try? await transcriptionService.downloadModel(variant: model.id)
                                        }
                                    }
                                )
                            }
                        }
                    }

                    Divider()

                    // Transcript Output Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Transcript Output")
                            .font(.headline)

                        Text("Every new transcription is saved in each format you select. Timing data is kept as well, so you can export an existing transcript to another format later from its menu.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        ForEach(TranscriptFormat.allCases) { format in
                            Toggle(isOn: Binding(
                                get: { settings.transcriptFormats.contains(format) },
                                set: { isOn in
                                    if isOn {
                                        settings.transcriptFormats.insert(format)
                                    } else {
                                        settings.transcriptFormats.remove(format)
                                    }
                                }
                            )) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(format.displayName)
                                    Text(format.description)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .toggleStyle(.checkbox)
                            .disabled(settings.transcriptFormats == [format])
                        }

                        Stepper(value: $settings.maxConcurrentJobs, in: AppSettings.concurrentJobsRange) {
                            HStack {
                                Text("Parallel transcriptions:")
                                Text("\(settings.maxConcurrentJobs)")
                                    .font(.system(.body, design: .monospaced).bold())
                            }
                        }
                        Text("How many recordings can be transcribed at the same time. Each one loads its own copy of the model, so large models with several jobs need a lot of memory. Extra jobs wait in a queue.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    Divider()

                    // Silence Detection Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Silence Detection Sensitivity")
                            .font(.headline)

                        Text("Whisper can hallucinate or fail if recordings begin with long silence. The app automatically scans audio waveforms to detect when human speech begins.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack {
                            Text("Noise Gate Threshold:")
                                .font(.subheadline)
                            Slider(value: $settings.silenceThresholdDB, in: -50...(-20), step: 1)
                            Text("\(Int(settings.silenceThresholdDB)) dB")
                                .font(.system(.subheadline, design: .monospaced))
                                .frame(width: 60, alignment: .trailing)
                        }
                    }
                }
                .padding(24)
            }

            Divider()

            HStack {
                Spacer()
                Button("Done") {
                    onDismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 680, height: 600)
    }

    private func chooseStorageFolder() {
        let panel = NSOpenPanel()
        panel.title = "Select Study Library Folder"
        panel.prompt = "Select Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = settings.rootFolderURL

        panel.begin { response in
            if response == .OK, let selectedURL = panel.url {
                settings.setCustomRootDirectory(selectedURL)
                CourseStorageService.shared.reload()
            }
        }
    }
}

struct ModelRowView: View {
    let model: WhisperModelOption
    let isSelected: Bool
    let isDownloaded: Bool
    let isDownloading: Bool
    let downloadProgress: Double
    let onSelect: () -> Void
    let onDownload: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                onSelect()
            } label: {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(model.displayName)
                        .font(.subheadline.bold())
                    
                    Text(model.sizeDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(model.accuracyBadge)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.15))
                        .foregroundColor(.blue)
                        .clipShape(Capsule())

                    Text(model.speedBadge)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.15))
                        .foregroundColor(.orange)
                        .clipShape(Capsule())
                }

                Text(model.description)
                    .font(.caption)
                    .foregroundColor(.secondary)

                if isDownloading {
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: downloadProgress)
                            .progressViewStyle(.linear)
                        Text("Downloading: \(Int(downloadProgress * 100))%")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 4)
                }
            }

            Spacer()

            if isDownloaded {
                Label("Downloaded", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.green)
                    .padding(.top, 2)
            } else if !isDownloading {
                Button("Download") {
                    onDownload()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
        )
    }
}
