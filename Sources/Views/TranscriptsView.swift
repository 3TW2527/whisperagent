import SwiftUI

public struct TranscriptsView: View {
    public let project: LectureProject
    public var onTranscribeNew: () -> Void

    @State private var selectedTranscriptID: String?
    @State private var quickLookURL: URL?
    @State private var isShowingQuickLook = false

    public init(project: LectureProject, onTranscribeNew: @escaping () -> Void) {
        self.project = project
        self.onTranscribeNew = onTranscribeNew
    }

    private var activeTranscript: TranscriptFile? {
        if let id = selectedTranscriptID, let match = project.transcripts.first(where: { $0.id == id }) {
            return match
        }
        return project.transcripts.first
    }

    public var body: some View {
        Group {
            if project.transcripts.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "waveform.badge.magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary.opacity(0.6))
                    
                    Text("No Transcripts Yet")
                        .font(.title3.bold())
                    
                    Text("Import an audio recording from iCloud Drive or drag one directly from the macOS Voice Memos app to transcribe it with Whisper.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)

                    Button {
                        onTranscribeNew()
                    } label: {
                        Label("Transcribe Audio Recording", systemImage: "plus.circle.fill")
                            .padding(.horizontal, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                HSplitView {
                    // Left list of transcripts
                    VStack(alignment: .leading, spacing: 0) {
                        List(selection: $selectedTranscriptID) {
                            ForEach(project.transcripts) { transcript in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Image(systemName: transcript.isMarkdown ? "doc.text.fill" : "doc.plaintext.fill")
                                            .foregroundColor(transcript.isMarkdown ? .accentColor : .blue)
                                        Text(transcript.name)
                                            .font(.subheadline.bold())
                                            .lineLimit(1)
                                        Spacer()
                                        Text(transcript.fileExtension.uppercased())
                                            .font(.system(size: 9, weight: .bold))
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(Color.secondary.opacity(0.12))
                                            .clipShape(RoundedRectangle(cornerRadius: 3))
                                            .foregroundColor(.secondary)
                                    }

                                    HStack {
                                        Text(transcript.formattedModifiedDate)
                                        Spacer()
                                        Text(transcript.formattedSize)
                                    }
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 4)
                                .tag(transcript.id)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedTranscriptID = transcript.id
                                }
                                .contextMenu {
                                    Button("Quick Look Preview (Space)") {
                                        quickLookURL = transcript.url
                                        isShowingQuickLook = true
                                    }
                                    Button("Open with Default App") {
                                        ProjectStorageService.shared.openFile(url: transcript.url)
                                    }
                                    Button("Reveal in Finder") {
                                        ProjectStorageService.shared.revealInFinder(url: transcript.url)
                                    }
                                }
                            }
                        }
                        .listStyle(.inset)

                        Divider()

                        HStack {
                            Button {
                                onTranscribeNew()
                            } label: {
                                Label("New Transcript", systemImage: "plus")
                            }
                            .buttonStyle(.plain)
                            .padding(8)

                            Spacer()
                        }
                        .background(Color(NSColor.controlBackgroundColor))
                    }
                    .frame(minWidth: 200, maxWidth: 300)

                    // Right detail viewer
                    if let active = activeTranscript {
                        TranscriptDetailView(
                            transcript: active,
                            onQuickLook: {
                                quickLookURL = active.url
                                isShowingQuickLook = true
                            }
                        )
                        .id(active.id)
                    } else {
                        Text("Select a transcript to view")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .onAppear {
            validateSelection()
        }
        .onChange(of: project.id) {
            validateSelection()
        }
        .onChange(of: project.transcripts) {
            validateSelection()
        }
        .sheet(isPresented: $isShowingQuickLook) {
            if let url = quickLookURL ?? activeTranscript?.url {
                QuickLookModal(fileURL: url) {
                    isShowingQuickLook = false
                    quickLookURL = nil
                }
            }
        }
        .background(
            Button("") {
                if let active = activeTranscript {
                    quickLookURL = active.url
                    isShowingQuickLook = true
                }
            }
            .keyboardShortcut(.space, modifiers: [])
            .opacity(0)
            .frame(width: 0, height: 0)
        )
    }

    private func validateSelection() {
        if let currentID = selectedTranscriptID, project.transcripts.contains(where: { $0.id == currentID }) {
            return
        }
        selectedTranscriptID = project.transcripts.first?.id
    }
}

struct TranscriptDetailView: View {
    let transcript: TranscriptFile
    var onQuickLook: (() -> Void)? = nil

    @State private var content: String = ""
    @State private var isCopied = false

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(transcript.url.lastPathComponent)
                        .font(.headline)
                    Text("Modified: \(transcript.formattedModifiedDate)  •  Size: \(transcript.formattedSize)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(content, forType: .string)
                    isCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        isCopied = false
                    }
                } label: {
                    Label(isCopied ? "Copied!" : (transcript.isMarkdown ? "Copy Markdown" : "Copy Text"), systemImage: isCopied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.bordered)

                if let onQuickLook = onQuickLook {
                    Button {
                        onQuickLook()
                    } label: {
                        Image(systemName: "eye")
                    }
                    .help("Quick Look Preview (Space)")
                }

                Button {
                    ProjectStorageService.shared.revealInFinder(url: transcript.url)
                } label: {
                    Image(systemName: "folder")
                }
                .help("Reveal in Finder")
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Scrollable Content
            ScrollView {
                Text(content)
                    .textSelection(.enabled)
                    .font(.system(.body, design: .default))
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        }
        .onAppear {
            loadContent()
        }
        .onChange(of: transcript.url) {
            loadContent()
        }
    }

    private func loadContent() {
        content = transcript.content
    }
}
