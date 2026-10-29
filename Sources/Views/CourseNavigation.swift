import SwiftUI

/// Where the user is inside the selected course. Shared by the sidebar (lecture and document lists)
/// and the main area (transcripts, notes, document preview).
@MainActor
final class CourseNavigation: ObservableObject {
    enum SidebarTab: String, CaseIterable, Identifiable {
        case lectures
        case documents
        /// Projects only: the user's own folders.
        case files

        var id: String { rawValue }

        static func tabs(for kind: CourseKind) -> [SidebarTab] {
            kind == .project ? [.lectures, .documents, .files] : [.lectures, .documents]
        }

        func title(for kind: CourseKind) -> String {
            switch self {
            case .lectures: return kind.unitPlural
            case .documents: return kind == .project ? "Materials" : "Documents"
            case .files: return "Files"
            }
        }
    }

    /// An entry in the transcript bar: a recording (by base name), a note or a meeting's file (by file path).
    enum BarItem: Hashable {
        case recording(String)
        case note(String)
        case file(String)
    }

    @Published var sidebarTab: SidebarTab = .lectures
    @Published var lectureSelection: LectureSelection?
    @Published var barItem: BarItem?
    @Published var documentID: String?
    /// The file open under Files, by path.
    @Published var projectFileID: String?
    @Published var isAddingLecture = false
    /// Lecture to select when the next course opens. Selecting a course resets navigation, so opening a course
    /// at a particular lecture (e.g. from the home screen) sets this first and `reset()` applies it.
    var pendingLectureSelection: LectureSelection?
    /// Series for the New Meeting sheet when the project opens from a series' slot on the home screen.
    var pendingNewLectureSeries: String?
    /// The series the open New Meeting sheet starts with.
    var newLectureSeries: String?

    func reset() {
        sidebarTab = .lectures
        lectureSelection = pendingLectureSelection
        pendingLectureSelection = nil
        newLectureSeries = pendingNewLectureSeries
        isAddingLecture = pendingNewLectureSeries != nil
        pendingNewLectureSeries = nil
        barItem = nil
        documentID = nil
        projectFileID = nil
    }

    var selectedLectureNumber: Int? {
        if case .lecture(let number) = lectureSelection { return number }
        return nil
    }

    /// Follows a `[[wikilink]]` clicked in a note.
    func open(_ target: WikilinkTarget, in course: Course) {
        switch target {
        case .note(let name):
            if let note = course.notes.first(where: { $0.name == name }) {
                sidebarTab = .lectures
                barItem = .note(note.id)
            }
        case .lecture(let number):
            sidebarTab = .lectures
            lectureSelection = .lecture(number)
        case .file(let name):
            if let material = course.materials.first(where: { $0.name == name }) {
                documentID = material.id
                sidebarTab = .documents
            } else if let (number, file) = course.meetingFiles.lazy.compactMap({ entry in entry.value.first { $0.name == name }.map { (entry.key, $0) } }).first {
                sidebarTab = .lectures
                lectureSelection = .lecture(number)
                barItem = .file(file.id)
            } else if let transcript = course.transcripts.first(where: { $0.name == name }) {
                CourseStorageService.shared.openFile(url: transcript.url)
            }
        case .missing(let name):
            // Like Obsidian, following a link to a note that doesn't exist yet creates it.
            if let note = try? CourseStorageService.shared.createNote(courseID: course.id, title: name) {
                sidebarTab = .lectures
                barItem = .note(note.id)
            }
        }
    }
}
