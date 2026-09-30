import Foundation

public struct LectureProject: Identifiable, Hashable, Sendable {
    public let id: String
    public var title: String
    public let folderURL: URL
    public let createdAt: Date
    public var modifiedAt: Date
    public var transcripts: [TranscriptFile]
    public var files: [LectureFile]

    public init(folderURL: URL, transcripts: [TranscriptFile] = [], files: [LectureFile] = []) {
        self.id = folderURL.path
        self.folderURL = folderURL
        self.title = folderURL.lastPathComponent
        self.transcripts = transcripts
        self.files = files
        
        let values = try? folderURL.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        self.createdAt = values?.creationDate ?? Date()
        self.modifiedAt = values?.contentModificationDate ?? Date()
    }

    public var hasTranscripts: Bool {
        !transcripts.isEmpty
    }

    public var totalFileCount: Int {
        transcripts.count + files.count
    }

    public var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: createdAt)
    }
}
