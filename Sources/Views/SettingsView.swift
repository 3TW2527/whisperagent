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

                        Text("All lecture projects are created as subfolders inside this directory. You can choose a local folder or an iCloud Drive directory to automatically sync across devices.")
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
                                ProjectStorageService.shared.reloadProjects()
                            }
                        }
                        .padding(12)
                        .background(Color(NSColor.controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
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
        panel.title = "Select Lectures Root Directory"
        panel.prompt = "Select Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = settings.rootFolderURL

        panel.begin { response in
            if response == .OK, let selectedURL = panel.url {
                settings.setCustomRootDirectory(selectedURL)
                ProjectStorageService.shared.reloadProjects()
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
