import SwiftUI
import UniformTypeIdentifiers

public struct FileAttachmentsView: View {
    public let project: LectureProject
    public var onAudioDropped: (URL) -> Void

    @ObservedObject private var settings = AppSettings.shared
    @State private var isTargeted = false
    @State private var previewFile: LectureFile?
    @State private var isShowingQuickLook = false

    public init(project: LectureProject, onAudioDropped: @escaping (URL) -> Void) {
        self.project = project
        self.onAudioDropped = onAudioDropped
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Action Mode Bar (Copy vs Move)
            HStack {
                Text("File action:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Picker("", selection: $settings.fileIngestionAction) {
                    ForEach(FileIngestionAction.allCases) { action in
                        Text(action.rawValue).tag(action)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 140)

                Text(settings.fileIngestionAction == .copy ? "(Copies original file)" : "(Moves file into lecture folder)")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Spacer()

                Button("Add Files...") {
                    selectAndAddFiles()
                }
                .controlSize(.small)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Drop & File List
            if project.files.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 44))
                        .foregroundColor(isTargeted ? .accentColor : .secondary.opacity(0.6))

                    Text("Drop Lecture Files Here")
                        .font(.headline)

                    Text("Drag & drop lecture slides (PDF, PPTX), notes, syllabus, or documents. Files will be \(settings.fileIngestionAction == .copy ? "copied" : "moved") into this lecture's folder.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 400)

                    Button("Choose Files...") {
                        selectAndAddFiles()
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(isTargeted ? Color.accentColor : Color.secondary.opacity(0.2), style: StrokeStyle(lineWidth: 2, dash: [8]))
                        .padding(24)
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 16)], spacing: 16) {
                        ForEach(project.files) { file in
                            FileCardView(file: file) {
                                previewFile = file
                                isShowingQuickLook = true
                            }
                        }
                    }
                    .padding()
                }
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(isTargeted ? Color.accentColor : Color.clear, lineWidth: 2)
                )
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            handleDroppedItems(providers)
            return true
        }
        .sheet(isPresented: $isShowingQuickLook) {
            if let file = previewFile {
                QuickLookModal(fileURL: file.url) {
                    isShowingQuickLook = false
                    previewFile = nil
                }
            }
        }
    }

    private func handleDroppedItems(_ providers: [NSItemProvider]) {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url = url else { return }
                DispatchQueue.main.async {
                    if VoiceMemosService.shared.isAudioFile(url: url) {
                        onAudioDropped(url)
                    } else {
                        do {
                            _ = try ProjectStorageService.shared.ingestFile(
                                from: url,
                                into: project,
                                action: settings.fileIngestionAction
                            )
                        } catch {
                            print("Failed to \(settings.fileIngestionAction.rawValue.lowercased()) dropped file: \(error)")
                        }
                    }
                }
            }
        }
    }

    private func selectAndAddFiles() {
        let panel = NSOpenPanel()
        panel.title = "Select Lecture Files to Add"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true

        panel.begin { response in
            if response == .OK {
                for url in panel.urls {
                    if VoiceMemosService.shared.isAudioFile(url: url) {
                        onAudioDropped(url)
                    } else {
                        try? ProjectStorageService.shared.ingestFile(
                            from: url,
                            into: project,
                            action: settings.fileIngestionAction
                        )
                    }
                }
            }
        }
    }
}

struct FileCardView: View {
    let file: LectureFile
    let onOpenPreview: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: file.systemIconName)
                .font(.system(size: 38))
                .foregroundColor(file.iconColor)
                .frame(height: 50)

            Text(file.name)
                .font(.caption.bold())
                .lineLimit(2)
                .multilineTextAlignment(.center)

            Text(file.formattedSize)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(width: 150, height: 130)
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            onOpenPreview()
        }
        .contextMenu {
            Button("Quick Look Preview (Space)") {
                onOpenPreview()
            }
            Button("Open with Default App") {
                ProjectStorageService.shared.openFile(url: file.url)
            }
            Button("Reveal in Finder") {
                ProjectStorageService.shared.revealInFinder(url: file.url)
            }
            Divider()
            Button("Delete", role: .destructive) {
                try? FileManager.default.removeItem(at: file.url)
                ProjectStorageService.shared.reloadProjects()
            }
        }
    }
}
