import Foundation
import SwiftUI

@MainActor
public class AppSettings: ObservableObject {
    public static let shared = AppSettings()

    private let rootPathBookmarkKey = "WhisperLectures_RootBookmark"
    private let rootPathStringKey = "WhisperLectures_RootPath"
    private let selectedModelKey = "WhisperLectures_SelectedModel"
    private let silenceThresholdKey = "WhisperLectures_SilenceThreshold"

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

    private init() {
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
