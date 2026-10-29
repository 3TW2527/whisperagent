import Foundation
import SwiftUI

public enum FileIngestionAction: String, CaseIterable, Identifiable, Sendable {
    case copy = "Copy"
    case move = "Move"

    public var id: String { rawValue }

    public var description: String {
        switch self {
        case .copy: return "Copy (keep original in place)"
        case .move: return "Move (relocate into the course folder)"
        }
    }
}

public enum TranscriptFormat: String, CaseIterable, Identifiable, Codable, Sendable {
    case markdown = "md"
    case plainText = "txt"
    case srt = "srt"
    case vtt = "vtt"

    public var id: String { rawValue }

    public var fileExtension: String { rawValue }

    public var displayName: String {
        switch self {
        case .markdown: return "Markdown (.md)"
        case .plainText: return "Plain Text (.txt)"
        case .srt: return "SubRip Subtitles (.srt)"
        case .vtt: return "WebVTT Subtitles (.vtt)"
        }
    }

    public var description: String {
        switch self {
        case .markdown:
            return "Metadata header plus timestamped paragraphs. Best for LLMs and reading."
        case .plainText:
            return "Spoken text only, in paragraphs, with no timestamps."
        case .srt:
            return "Subtitle cues with millisecond timestamps, for video players and editors."
        case .vtt:
            return "Web subtitle format, for browsers and web video players."
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
    private let transcriptFormatsKey = "WhisperLectures_TranscriptFormats"
    private let maxConcurrentJobsKey = "WhisperLectures_MaxConcurrentJobs"
    private let externalCoursePathsKey = "WhisperLectures_ExternalCoursePaths"
    private let recentLectureCountKey = "WhisperLectures_RecentLectureCount"
    private let markdownFolderPathsKey = "WhisperLectures_MarkdownFolderPaths"
    private let canvasAddressKey = "WhisperLectures_CanvasAddress"
    private let canvasSyncMinutesKey = "WhisperLectures_CanvasSyncMinutes"
    private let canvasHiddenCourseIDsKey = "WhisperLectures_CanvasHiddenCourseIDs"

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

    /// Formats written for every new transcription. Never empty.
    @Published public var transcriptFormats: Set<TranscriptFormat> {
        didSet {
            if transcriptFormats.isEmpty {
                transcriptFormats = [.markdown]
                return
            }
            UserDefaults.standard.set(transcriptFormats.map(\.rawValue).sorted(), forKey: transcriptFormatsKey)
        }
    }

    /// How many transcription jobs may run at the same time.
    @Published public var maxConcurrentJobs: Int {
        didSet {
            UserDefaults.standard.set(maxConcurrentJobs, forKey: maxConcurrentJobsKey)
        }
    }

    /// Course folders that live outside the library folder. They are listed alongside the library's courses.
    @Published public var externalCoursePaths: [String] {
        didSet {
            UserDefaults.standard.set(externalCoursePaths, forKey: externalCoursePathsKey)
        }
    }

    /// How many lectures the home screen lists under Recent Lectures.
    @Published public var recentLectureCount: Int {
        didSet {
            UserDefaults.standard.set(recentLectureCount, forKey: recentLectureCountKey)
        }
    }

    /// Folders the Markdown Library tool reads, in the order they were added.
    @Published public var markdownFolderPaths: [String] {
        didSet {
            UserDefaults.standard.set(markdownFolderPaths, forKey: markdownFolderPathsKey)
        }
    }

    /// The Canvas site, e.g. `https://school.instructure.com`. The access token is kept in the keychain.
    @Published public var canvasAddress: String {
        didSet {
            UserDefaults.standard.set(canvasAddress, forKey: canvasAddressKey)
        }
    }

    /// How often Canvas is synced while the app is open, in minutes. 0 syncs only when the Canvas tool opens,
    /// and `canvasManualSync` only when the refresh button is pressed.
    @Published public var canvasSyncMinutes: Int {
        didSet {
            UserDefaults.standard.set(canvasSyncMinutes, forKey: canvasSyncMinutesKey)
        }
    }

    /// Canvas courses left out of the Canvas tool and its syncs.
    @Published public var canvasHiddenCourseIDs: [Int] {
        didSet {
            UserDefaults.standard.set(canvasHiddenCourseIDs, forKey: canvasHiddenCourseIDsKey)
        }
    }

    public static let concurrentJobsRange = 1...4
    public static let canvasManualSync = -1
    public static let canvasSyncChoices = [canvasManualSync, 0, 15, 30, 60]
    public static let recentLectureCountRange = 3...50

    /// Formats in a stable display order.
    public var orderedTranscriptFormats: [TranscriptFormat] {
        TranscriptFormat.allCases.filter { transcriptFormats.contains($0) }
    }

    private init() {
        // Load Ingestion Action
        let savedActionStr = UserDefaults.standard.string(forKey: fileIngestionActionKey) ?? "Copy"
        self.fileIngestionAction = FileIngestionAction(rawValue: savedActionStr) ?? .copy

        // Load Transcript Formats (falls back to the older single-format setting)
        if let saved = UserDefaults.standard.stringArray(forKey: transcriptFormatsKey) {
            let formats = Set(saved.compactMap(TranscriptFormat.init(rawValue:)))
            self.transcriptFormats = formats.isEmpty ? [.markdown] : formats
        } else if UserDefaults.standard.string(forKey: transcriptFormatKey) == "Plain Text (.txt)" {
            self.transcriptFormats = [.plainText]
        } else {
            self.transcriptFormats = [.markdown]
        }

        // Load Concurrency Limit
        let savedJobs = UserDefaults.standard.integer(forKey: maxConcurrentJobsKey)
        self.maxConcurrentJobs = Self.concurrentJobsRange.contains(savedJobs) ? savedJobs : 2

        self.externalCoursePaths = UserDefaults.standard.stringArray(forKey: externalCoursePathsKey) ?? []

        let savedRecent = UserDefaults.standard.integer(forKey: recentLectureCountKey)
        self.recentLectureCount = Self.recentLectureCountRange.contains(savedRecent) ? savedRecent : 8

        self.markdownFolderPaths = UserDefaults.standard.stringArray(forKey: markdownFolderPathsKey) ?? []

        self.canvasAddress = UserDefaults.standard.string(forKey: canvasAddressKey) ?? ""
        let savedSync = UserDefaults.standard.integer(forKey: canvasSyncMinutesKey)
        self.canvasSyncMinutes = Self.canvasSyncChoices.contains(savedSync) ? savedSync : 0
        self.canvasHiddenCourseIDs = UserDefaults.standard.array(forKey: canvasHiddenCourseIDsKey) as? [Int] ?? []

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
