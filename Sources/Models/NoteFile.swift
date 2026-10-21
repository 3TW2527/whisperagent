import Foundation

/// A Markdown note the student wrote for a course, stored as `notes/<name>.md`.
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
}
