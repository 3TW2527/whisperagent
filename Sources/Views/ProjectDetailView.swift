import SwiftUI
import UniformTypeIdentifiers

public struct ProjectDetailView: View {
    public let project: LectureProject
    public var onSelectAudio: (URL) -> Void

    @State private var selectedTab: DetailTab = .transcripts
    @State private var isAudioDropTargeted = false
    @State private var isRenaming = false
    @State private var renameTitle = ""

    public enum DetailTab: String, CaseIterable, Identifiable {
        case transcripts = "Transcripts (.md)"
        case files = "Lecture Files & Slides"

        public var id: String { self.rawValue }
    }

    public init(project: LectureProject, onSelectAudio: @escaping (URL) -> Void) {
        self.project = project
        self.onSelectAudio = onSelectAudio
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center) {
                    if isRenaming {
                        TextField("Lecture Title", text: $renameTitle, onCommit: {
                            commitRename()
                        })
                        .textFieldStyle(.roundedBorder)
                        .font(.title2.bold())
                        .frame(maxWidth: 350)

                        Button("Save") {
                            commitRename()
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Cancel") {
                            isRenaming = false
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text(project.title)
                            .font(.title2.bold())
                            .lineLimit(1)

                        Button {
                            renameTitle = project.title
                            isRenaming = true
                        } label: {
                            Image(systemName: "pencil")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()

                    // Action buttons
                    Button {
                        VoiceMemosService.shared.openVoiceMemosApp()
                    } label: {
                        Label("Open Voice Memos", systemImage: "mic.fill")
                    }
                    .help("Open the macOS Voice Memos app to easily drag recordings into this project")

                    Button {
                        VoiceMemosService.shared.promptForAudioFile { selectedURL in
                            if let url = selectedURL {
                                onSelectAudio(url)
                            }
                        }
                    } label: {
                        Label("Import Audio...", systemImage: "waveform.badge.plus")
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        ProjectStorageService.shared.revealInFinder(url: project.folderURL)
                    } label: {
                        Image(systemName: "folder")
                    }
                    .help("Reveal lecture folder in Finder")
                }

                HStack {
                    Label(project.formattedDate, systemImage: "calendar")
                    Text("•")
                    Text("\(project.transcripts.count) transcript\(project.transcripts.count == 1 ? "" : "s")")
                    Text("•")
                    Text("\(project.files.count) file\(project.files.count == 1 ? "" : "s")")
                    Spacer()
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            // Audio Drop Strip (Method A: Direct Drag & Drop)
            HStack(spacing: 12) {
                Image(systemName: "waveform")
                    .font(.title3)
                    .foregroundColor(isAudioDropTargeted ? .accentColor : .secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Drag Audio Recordings Here (.m4a, .mp3, etc.)")
                        .font(.subheadline.bold())
                    Text("Drop directly from the Voice Memos app or iCloud Drive to preview, trim silence, and transcribe.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button("Browse iCloud...") {
                    VoiceMemosService.shared.promptForAudioFile { url in
                        if let url = url {
                            onSelectAudio(url)
                        }
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(10)
            .background(isAudioDropTargeted ? Color.accentColor.opacity(0.12) : Color(NSColor.windowBackgroundColor))
            .overlay(
                Rectangle()
                    .stroke(isAudioDropTargeted ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: 1)
            )
            .onDrop(of: [.fileURL], isTargeted: $isAudioDropTargeted) { providers in
                handleDroppedAudio(providers)
                return true
            }

            // Tab Picker
            Picker("", selection: $selectedTab) {
                ForEach(DetailTab.allCases) { tab in
                    Text(tab == .transcripts ? "Transcripts (\(project.transcripts.count))" : "Lecture Files (\(project.files.count))")
                        .tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // Main Content Area
            switch selectedTab {
            case .transcripts:
                TranscriptsView(project: project) {
                    VoiceMemosService.shared.promptForAudioFile { url in
                        if let url = url {
                            onSelectAudio(url)
                        }
                    }
                }
            case .files:
                FileAttachmentsView(project: project) { audioURL in
                    onSelectAudio(audioURL)
                }
            }
        }
    }

    private func commitRename() {
        guard !renameTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            isRenaming = false
            return
        }
        ProjectStorageService.shared.renameProject(project, to: renameTitle)
        isRenaming = false
    }

    private func handleDroppedAudio(_ providers: [NSItemProvider]) {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url = url else { return }
                DispatchQueue.main.async {
                    if VoiceMemosService.shared.isAudioFile(url: url) {
                        onSelectAudio(url)
                    } else {
                        // If user dropped non-audio onto this bar, still copy to project
                        try? ProjectStorageService.shared.copyFile(from: url, into: project)
                    }
                }
            }
        }
    }
}
