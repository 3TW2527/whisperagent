import SwiftUI

/// Where the user is inside the selected course. Shared by the sidebar (lecture and document lists)
/// and the main area (transcripts, notes, document preview).
@MainActor
final class CourseNavigation: ObservableObject {
    enum SidebarTab: String, CaseIterable, Identifiable {
        case lectures = "Lectures"
        case documents = "Documents"

        var id: String { rawValue }
    }

    /// An entry in the transcript bar: a recording (by base name) or a note (by file path).
    enum BarItem: Hashable {
        case recording(String)
        case note(String)
    }

    @Published var sidebarTab: SidebarTab = .lectures
    @Published var lectureSelection: LectureSelection?
    @Published var barItem: BarItem?
    @Published var documentID: String?
    @Published var isAddingLecture = false

    func reset() {
        sidebarTab = .lectures
        lectureSelection = nil
        barItem = nil
        documentID = nil
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
