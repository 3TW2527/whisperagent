import Foundation
import SwiftUI

public enum FileIngestionAction: String, CaseIterable, Identifiable, Sendable {
    case copy = "Copy"
    case move = "Move"

    public var id: String { rawValue }

    public var description: String {
        switch self {
        case .copy: return "Copy (keep original in place)"
        case .move: return "Move (relocate into lecture folder)"
        }
    }
}

public enum TranscriptFormat: String, CaseIterable, Identifiable, Sendable {
    case markdown = "Markdown (.md)"
    case plainText = "Plain Text (.txt)"

    public var id: String { rawValue }

    public var fileExtension: String {
        switch self {
        case .markdown: return "md"
        case .plainText: return "txt"
        }
    }

    public var description: String {
        switch self {
        case .markdown:
            return "Rich Markdown formatted with timestamps and metadata headers"
        case .plainText:
            return "Plain text transcript only (no timestamps or formatting)"
        }
    }
}

@MainActor
public class AppSettings: ObservableObject {
    public static let shared = AppSettings()

    private let rootPathBookmarkKey = "WhisperLectures_RootBookmark"
    private let rootPathStringKey = "WhisperLectures_RootPath"
    private let selectedModelKey = "WhisperLectures_SelectedModel"
    private let silenceThresholdKey = "WhisperLectures_SilenceThreshold"
    private let fileIngestionActionKey = "WhisperLectures_FileIngestionAction"
    private let transcriptFormatKey = "WhisperLectures_TranscriptFormat"

    @Published public var rootFolderURL: URL {
        didSet {
            saveRootBookmark(for: rootFolderURL)
        }
    }

    @Published public var selectedModelVariant: String {
        didSet {
            UserDefaults.standard.set(selectedModelVariant, forKey: selectedModelKey)
        }
    }

    @Published public var silenceThresholdDB: Float {
        didSet {
            UserDefaults.standard.set(silenceThresholdDB, forKey: silenceThresholdKey)
        }
    }

    @Published public var fileIngestionAction: FileIngestionAction {
        didSet {
            UserDefaults.standard.set(fileIngestionAction.rawValue, forKey: fileIngestionActionKey)
        }
    }

    @Published public var transcriptFormat: TranscriptFormat {
        didSet {
            UserDefaults.standard.set(transcriptFormat.rawValue, forKey: transcriptFormatKey)
        }
    }

    private init() {
        // Load Ingestion Action
        let savedActionStr = UserDefaults.standard.string(forKey: fileIngestionActionKey) ?? "Copy"
        self.fileIngestionAction = FileIngestionAction(rawValue: savedActionStr) ?? .copy

        // Load Transcript Format
        let savedFormatStr = UserDefaults.standard.string(forKey: transcriptFormatKey) ?? TranscriptFormat.markdown.rawValue
        self.transcriptFormat = TranscriptFormat(rawValue: savedFormatStr) ?? .markdown

        // Load Model
        let savedModel = UserDefaults.standard.string(forKey: selectedModelKey) ?? "openai_whisper-base"
        self.selectedModelVariant = savedModel

        // Load Silence Threshold
        let savedThreshold = UserDefaults.standard.float(forKey: silenceThresholdKey)
        self.silenceThresholdDB = savedThreshold != 0 ? savedThreshold : -35.0

        // Resolve root storage URL
        if let bookmarkData = UserDefaults.standard.data(forKey: rootPathBookmarkKey) {
            var isStale = false
            do {
                let resolvedURL = try URL(
                    resolvingBookmarkData: bookmarkData,
                    options: .withSecurityScope,
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
                if !isStale {
                    _ = resolvedURL.startAccessingSecurityScopedResource()
                    self.rootFolderURL = resolvedURL
                    return
                }
            } catch {
                print("Failed to resolve security bookmark: \(error.localizedDescription)")
            }
        }

        if let savedPath = UserDefaults.standard.string(forKey: rootPathStringKey) {
            let url = URL(fileURLWithPath: savedPath)
            if FileManager.default.fileExists(atPath: url.path) {
                self.rootFolderURL = url
                return
            }
        }

        // Default path: check iCloud Drive first, else Documents
        let defaultURL = Self.defaultRootDirectory()
        try? FileManager.default.createDirectory(at: defaultURL, withIntermediateDirectories: true)
        self.rootFolderURL = defaultURL
        saveRootBookmark(for: defaultURL)
    }

    public static func defaultRootDirectory() -> URL {
        // iCloud Drive folder path on macOS:
        let fileManager = FileManager.default
        let homeDir = fileManager.homeDirectoryForCurrentUser
        let cloudDocs = homeDir.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/WhisperLectures")

        if fileManager.fileExists(atPath: homeDir.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs").path) {
            return cloudDocs
        } else {
            return homeDir.appendingPathComponent("Documents/WhisperLectures")
        }
    }

    public func setCustomRootDirectory(_ url: URL) {
        _ = url.startAccessingSecurityScopedResource()
        self.rootFolderURL = url
        saveRootBookmark(for: url)
    }

    private func saveRootBookmark(for url: URL) {
        UserDefaults.standard.set(url.path, forKey: rootPathStringKey)
        do {
            let bookmarkData = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmarkData, forKey: rootPathBookmarkKey)
        } catch {
            print("Failed to create bookmark data for \(url.path): \(error.localizedDescription)")
        }
    }

    public var isUsingiCloud: Bool {
        rootFolderURL.path.contains("Mobile Documents/com~apple~CloudDocs")
    }
}
