import SwiftUI

public struct TranscriptsView: View {
    public let project: LectureProject
    public var onTranscribeNew: () -> Void

    @State private var selectedTranscript: TranscriptFile?
    @State private var searchText = ""
    @State private var isCopied = false

    public init(project: LectureProject, onTranscribeNew: @escaping () -> Void) {
        self.project = project
        self.onTranscribeNew = onTranscribeNew
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
                        List(project.transcripts, selection: $selectedTranscript) { transcript in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Image(systemName: "doc.text.fill")
                                        .foregroundColor(.accentColor)
                                    Text(transcript.name)
                                        .font(.subheadline.bold())
                                        .lineLimit(1)
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
                            .tag(transcript)
                            .contextMenu {
                                Button("Reveal in Finder") {
                                    ProjectStorageService.shared.revealInFinder(url: transcript.url)
                                }
                                Button("Open with Default App") {
                                    ProjectStorageService.shared.openFile(url: transcript.url)
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

                    // Right detail markdown viewer
                    if let active = selectedTranscript ?? project.transcripts.first {
                        TranscriptDetailView(transcript: active)
                    } else {
                        Text("Select a transcript to view")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .onAppear {
            if selectedTranscript == nil {
                selectedTranscript = project.transcripts.first
            }
        }
    }
}

struct TranscriptDetailView: View {
    let transcript: TranscriptFile

    @State private var content: String = ""
    @State private var isCopied = false

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(transcript.name + ".md")
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
                    Label(isCopied ? "Copied!" : "Copy Markdown", systemImage: isCopied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.bordered)

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
        .onChange(of: transcript.url) { _ in
            loadContent()
        }
    }

    private func loadContent() {
        content = transcript.content
    }
}
