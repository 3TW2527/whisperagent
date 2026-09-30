import Foundation

public struct TranscriptFile: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let name: String
    public let url: URL
    public let modifiedAt: Date
    public let fileSize: Int64

    public init(url: URL) {
        self.id = UUID()
        self.url = url
        self.name = url.deletingPathExtension().lastPathComponent
        
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        self.fileSize = Int64(values?.fileSize ?? 0)
        self.modifiedAt = values?.contentModificationDate ?? Date()
    }

    public var content: String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    public var formattedModifiedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: modifiedAt)
    }

    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
}
