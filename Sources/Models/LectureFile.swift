import Foundation
import SwiftUI
import UniformTypeIdentifiers

public struct LectureFile: Identifiable, Hashable, Sendable {
    public var id: String { url.path }
    public let name: String
    public let url: URL
    public let fileSize: Int64
    public let modifiedAt: Date

    public init(url: URL) {
        self.url = url
        self.name = url.lastPathComponent
        
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        self.fileSize = Int64(values?.fileSize ?? 0)
        self.modifiedAt = values?.contentModificationDate ?? Date()
    }

    public var formattedModifiedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: modifiedAt)
    }

    public var kindDescription: String {
        switch fileExtension {
        case "pdf":
            return "PDF Document"
        case "ppt", "pptx":
            return "PowerPoint Presentation"
        case "key":
            return "Keynote Presentation"
        case "doc", "docx":
            return "Word Document"
        case "pages":
            return "Pages Document"
        case "txt":
            return "Plain Text Document"
        case "rtf":
            return "Rich Text Document"
        case "png", "jpg", "jpeg", "heic", "webp":
            return "Image"
        case "zip", "tar", "gz":
            return "Compressed Archive"
        case "mp3", "m4a", "wav", "aac":
            return "Audio Recording"
        case "mp4", "mov":
            return "Video"
        default:
            return fileExtension.isEmpty ? "File" : "\(fileExtension.uppercased()) Document"
        }
    }

    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    public var fileExtension: String {
        url.pathExtension.lowercased()
    }

    public var systemIconName: String {
        Self.systemIconName(forExtension: fileExtension)
    }

    public var iconColor: Color {
        Self.iconColor(forExtension: fileExtension)
    }

    public static func systemIconName(forExtension fileExtension: String) -> String {
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

    public static func iconColor(forExtension fileExtension: String) -> Color {
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
