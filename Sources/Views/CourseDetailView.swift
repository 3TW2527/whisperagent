import SwiftUI
import UniformTypeIdentifiers

/// Detail view for one course: header, audio drop bar, and Lectures / Materials tabs.
public struct CourseDetailView: View {
    public let course: Course
    /// Called with an audio file and the lecture it should go to (if one is selected).
    public var onSelectAudio: (URL, Int?) -> Void
    public var onAskAI: () -> Void

    @State private var selectedTab: DetailTab = .lectures
    @State private var lectureSelection: LectureSelection?
    @State private var isAudioDropTargeted = false
    @State private var isEditingCourse = false
    @State private var isAddingLecture = false

    public enum DetailTab: String, CaseIterable, Identifiable {
        case lectures = "Lectures"
        case materials = "Materials"

        public var id: String { rawValue }
    }

    public init(course: Course, onSelectAudio: @escaping (URL, Int?) -> Void, onAskAI: @escaping () -> Void) {
        self.course = course
        self.onSelectAudio = onSelectAudio
        self.onAskAI = onAskAI
    }

    private var selectedLectureNumber: Int? {
        if case .lecture(let number) = lectureSelection { return number }
        return nil
    }

    public var body: some View {
        VStack(spacing: 0) {
            header

            audioDropBar

            Picker("", selection: $selectedTab) {
                Text("Lectures (\(course.lectures.count))").tag(DetailTab.lectures)
                Text("Materials (\(course.materials.count))").tag(DetailTab.materials)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            switch selectedTab {
            case .lectures:
                LecturesView(
                    course: course,
                    selection: $lectureSelection,
                    onNewLecture: { isAddingLecture = true },
                    onTranscribe: { number in
                        promptForAudio(lectureNumber: number)
                    }
                )
            case .materials:
                FileAttachmentsView(course: course) { audioURL in
                    onSelectAudio(audioURL, selectedLectureNumber)
                }
            }
        }
        .sheet(isPresented: $isEditingCourse) {
            CourseEditorSheet(course: course) { isEditingCourse = false }
        }
        .sheet(isPresented: $isAddingLecture) {
            LectureEditorSheet(course: course, onSaved: { created in
                if let created {
                    lectureSelection = .lecture(created.number)
                    selectedTab = .lectures
                }
            }, onDismiss: {
                isAddingLecture = false
            })
        }
        .onReceive(NotificationCenter.default.publisher(for: .createNewLecture)) { _ in
            isAddingLecture = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .importAudioRecording)) { note in
            if let url = note.object as? URL {
                onSelectAudio(url, selectedLectureNumber)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                if !course.metadata.code.isEmpty {
                    Text(course.metadata.code)
                        .font(.system(.title3, design: .monospaced).bold())
                        .foregroundColor(.accentColor)
                }
                Text(course.name)
                    .font(.title2.bold())
                    .lineLimit(1)

                Button {
                    isEditingCourse = true
                } label: {
                    Image(systemName: "pencil")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Edit course name, code and tags")

                Spacer()

                Button {
                    isAddingLecture = true
                } label: {
                    Label("New Lecture", systemImage: "plus")
                }

                Button {
                    onAskAI()
                } label: {
                    Label("Ask an AI", systemImage: "sparkles")
                }
                .help("How to point Claude, ChatGPT/Codex or Gemini at this course")

                Button {
                    CourseStorageService.shared.revealInFinder(url: course.folderURL)
                } label: {
                    Image(systemName: "folder")
                }
                .help("Reveal course folder in Finder")
            }

            HStack(spacing: 8) {
                ForEach(course.tags, id: \.self) { tag in
                    TagChip(tag: tag)
                }
                if !course.tags.isEmpty {
                    Text("•")
                }
                Text("\(course.lectures.count) lecture\(course.lectures.count == 1 ? "" : "s")")
                Text("•")
                Text("\(course.transcripts.count) transcript file\(course.transcripts.count == 1 ? "" : "s")")
                Text("•")
                Text("\(course.materials.count) material\(course.materials.count == 1 ? "" : "s")")
                Spacer()
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var audioDropBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.title3)
                .foregroundColor(isAudioDropTargeted ? .accentColor : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text("Drop audio recordings here (.m4a, .mp3, ...)")
                    .font(.subheadline.bold())
                Text("Drop several at once to transcribe them in parallel. Other files are added to Materials.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button {
                VoiceMemosService.shared.openVoiceMemosApp()
            } label: {
                Label("Voice Memos", systemImage: "mic.fill")
            }
            .controlSize(.small)
            .help("Open Voice Memos so you can drag recordings in")

            Button("Import Audio...") {
                promptForAudio(lectureNumber: selectedLectureNumber)
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
            handleDroppedFiles(providers)
            return true
        }
    }

    private func promptForAudio(lectureNumber: Int?) {
        VoiceMemosService.shared.promptForAudioFile { url in
            if let url {
                onSelectAudio(url, lectureNumber)
            }
        }
    }

    private func handleDroppedFiles(_ providers: [NSItemProvider]) {
        let lecture = selectedLectureNumber
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                DispatchQueue.main.async {
                    if VoiceMemosService.shared.isAudioFile(url: url) {
                        onSelectAudio(url, lecture)
                    } else {
                        _ = try? CourseStorageService.shared.ingestMaterial(from: url, courseID: course.id)
                    }
                }
            }
        }
    }
}
