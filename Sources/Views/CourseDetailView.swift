import SwiftUI
import UniformTypeIdentifiers

/// Main area for one course: header, audio drop bar, and either the lecture workspace or a document preview,
/// depending on the sidebar's tab.
public struct CourseDetailView: View {
    public let course: Course
    @ObservedObject var nav: CourseNavigation
    /// Called with an audio file and the lecture it should go to (if one is selected).
    public var onSelectAudio: (URL, Int?) -> Void

    @State private var isAudioDropTargeted = false

    init(course: Course, nav: CourseNavigation, onSelectAudio: @escaping (URL, Int?) -> Void) {
        self.course = course
        self.nav = nav
        self.onSelectAudio = onSelectAudio
    }

    private var selectedLectureNumber: Int? { nav.selectedLectureNumber }

    public var body: some View {
        VStack(spacing: 0) {
            audioDropBar

            Divider()

            switch nav.sidebarTab {
            case .lectures:
                LecturesView(
                    course: course,
                    nav: nav,
                    onNewLecture: { nav.isAddingLecture = true },
                    onTranscribe: { number in
                        promptForAudio(lectureNumber: number)
                    }
                )
            case .documents:
                DocumentPane(course: course, nav: nav)
            }
        }
        .sheet(isPresented: $nav.isAddingLecture) {
            LectureEditorSheet(course: course, onSaved: { created in
                if let created {
                    nav.lectureSelection = .lecture(created.number)
                    nav.sidebarTab = .lectures
                }
            }, onDismiss: {
                nav.isAddingLecture = false
            })
        }
        .onAppear(perform: validateSelections)
        .onChange(of: course.lectures) { validateSelections() }
        .onChange(of: course.materials) { validateSelections() }
        .onReceive(NotificationCenter.default.publisher(for: .createNewLecture)) { _ in
            nav.isAddingLecture = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .importAudioRecording)) { note in
            if let url = note.object as? URL {
                onSelectAudio(url, selectedLectureNumber)
            }
        }
    }

    /// Keeps the lecture and document selections pointing at things that exist, defaulting to the latest lecture.
    private func validateSelections() {
        switch nav.lectureSelection {
        case .lecture(let number) where course.lecture(number: number) != nil:
            break
        case .unassigned where !course.unassignedRecordingGroups.isEmpty:
            break
        default:
            if let latest = course.lectures.last {
                nav.lectureSelection = .lecture(latest.number)
            } else if !course.unassignedRecordingGroups.isEmpty {
                nav.lectureSelection = .unassigned
            } else {
                nav.lectureSelection = nil
            }
        }

        if nav.documentID == nil || !course.materials.contains(where: { $0.id == nav.documentID }) {
            nav.documentID = course.materials.first?.id
        }
    }

    private var audioDropBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform")
                .foregroundColor(isAudioDropTargeted ? .accentColor : .secondary)

            Text("Drop audio here to transcribe it. Other files are added to Documents.")
                .font(.caption)
                .foregroundColor(isAudioDropTargeted ? .accentColor : .secondary)
                .lineLimit(1)

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
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isAudioDropTargeted ? Color.accentColor.opacity(0.12) : Color(NSColor.controlBackgroundColor))
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
