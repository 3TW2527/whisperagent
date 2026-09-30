import Foundation
import SwiftUI
import UniformTypeIdentifiers

public struct LectureFile: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let name: String
    public let url: URL
    public let fileSize: Int64
    public let modifiedAt: Date

    public init(url: URL) {
        self.id = UUID()
        self.url = url
        self.name = url.lastPathComponent
        
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        self.fileSize = Int64(values?.fileSize ?? 0)
        self.modifiedAt = values?.contentModificationDate ?? Date()
    }

    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    public var fileExtension: String {
        url.pathExtension.lowercased()
    }

    public var systemIconName: String {
        switch fileExtension {
        case "pdf":
            return "doc.richtext"
        case "ppt", "pptx", "key":
            return "rectangle.on.rectangle.angled"
        case "doc", "docx", "pages", "txt", "rtf":
            return "doc.text"
        case "png", "jpg", "jpeg", "heic", "webp":
            return "photo"
        case "zip", "tar", "gz":
            return "archivebox"
        default:
            return "doc"
        }
    }

    public var iconColor: Color {
        switch fileExtension {
        case "pdf":
            return .red
        case "ppt", "pptx", "key":
            return .orange
        case "doc", "docx", "pages":
            return .blue
        case "png", "jpg", "jpeg", "heic":
            return .purple
        case "zip", "tar", "gz":
            return .yellow
        default:
            return .secondary
        }
    }
}
