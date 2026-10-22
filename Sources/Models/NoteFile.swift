import Foundation

/// A Markdown note the student wrote, stored as `notes/<name>.md`.
/// Notes for a lecture are named `L03 <title> · <date> · <index>`; the `L03` prefix ties them to that lecture.
public struct NoteFile: Identifiable, Hashable, Sendable {
    public var id: String { url.path }
    public let url: URL
    public let modifiedAt: Date

    public init(url: URL) {
        self.url = url
        self.modifiedAt = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
    }

    /// File name without the extension. This is what `[[wikilinks]]` refer to.
    public var name: String {
        url.deletingPathExtension().lastPathComponent
    }

    /// The lecture this note belongs to, read from its `L03 ` name prefix. Nil for course-wide notes.
    public var lectureNumber: Int? {
        let name = self.name
        guard name.hasPrefix("L"), let space = name.firstIndex(of: " ") else { return nil }
        return Int(name[name.index(after: name.startIndex)..<space])
    }
}
