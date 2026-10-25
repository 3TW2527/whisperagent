import Foundation
import AppKit

/// A Markdown file found in one of the Markdown Library's folders.
public struct MarkdownDocument: Identifiable, Hashable, Sendable {
    public var id: String { url.path }
    public let url: URL
    /// Path inside its library folder, e.g. `week-1/summary.md`.
    public let relativePath: String
    public let modifiedAt: Date

    /// File name without the extension. This is what `[[wikilinks]]` refer to.
    public var name: String {
        url.deletingPathExtension().lastPathComponent
    }

    /// Subfolder inside the library folder, empty for files at its top level.
    public var subfolder: String {
        (relativePath as NSString).deletingLastPathComponent
    }
}

/// A folder the user added to the Markdown Library, with every Markdown file below it.
public struct MarkdownFolder: Identifiable, Hashable, Sendable {
    public var id: String { url.path }
    public let url: URL
    public var documents: [MarkdownDocument]
    /// True when the folder no longer exists (moved, deleted, or on a disconnected drive).
    public var isMissing: Bool
    /// True when the scan stopped at `MarkdownLibraryService.maxFilesPerFolder`.
    public var isTruncated: Bool

    public var name: String { url.lastPathComponent }
}

/// Reads the folders listed in `AppSettings.markdownFolderPaths` and edits the Markdown files inside them.
@MainActor
public final class MarkdownLibraryService: ObservableObject {
    public static let shared = MarkdownLibraryService()

    nonisolated public static let fileExtensions: Set<String> = ["md", "markdown", "mdown", "mkd"]
    nonisolated public static let maxFilesPerFolder = 5000
    /// Folders that are never worth scanning for notes.
    nonisolated private static let skippedFolderNames: Set<String> = ["node_modules", ".git", "build", "DerivedData"]

    @Published public private(set) var folders: [MarkdownFolder] = []
    @Published public private(set) var isScanning = false

    private let fileManager = FileManager.default
    private var scanTask: Task<Void, Never>?

    private init() {}

    public func folder(id: String) -> MarkdownFolder? {
        folders.first { $0.id == id }
    }

    public func document(id: String) -> MarkdownDocument? {
        folders.lazy.flatMap(\.documents).first { $0.id == id }
    }

    /// The library folder a document belongs to.
    public func folder(containing document: MarkdownDocument) -> MarkdownFolder? {
        folders.first { $0.documents.contains(document) }
    }

    // MARK: - Folders

    /// Rescans every folder in the background. Large folders never block the UI.
    public func reload() {
        let urls = AppSettings.shared.markdownFolderPaths.map { URL(fileURLWithPath: $0) }
        scanTask?.cancel()
        isScanning = true
        scanTask = Task {
            let scanned = await Task.detached(priority: .userInitiated) {
                urls.map(Self.scan)
            }.value
            guard !Task.isCancelled else { return }
            folders = scanned
            isScanning = false
        }
    }

    public func addFolder(_ url: URL) {
        let path = url.standardizedFileURL.path
        guard !AppSettings.shared.markdownFolderPaths.contains(path) else { return }
        AppSettings.shared.markdownFolderPaths.append(path)
        reload()
    }

    /// Forgets a folder. Its files stay where they are.
    public func removeFolder(id: String) {
        AppSettings.shared.markdownFolderPaths.removeAll { $0 == id }
        folders.removeAll { $0.id == id }
    }

    nonisolated private static func scan(_ folderURL: URL) -> MarkdownFolder {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: folderURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return MarkdownFolder(url: folderURL, documents: [], isMissing: true, isTruncated: false)
        }

        let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey]
        guard let enumerator = fileManager.enumerator(
            at: folderURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return MarkdownFolder(url: folderURL, documents: [], isMissing: false, isTruncated: false)
        }

        let rootPath = folderURL.standardizedFileURL.path
        var documents: [MarkdownDocument] = []
        var isTruncated = false
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isDirectory == true {
                if skippedFolderNames.contains(url.lastPathComponent) { enumerator.skipDescendants() }
                continue
            }
            guard fileExtensions.contains(url.pathExtension.lowercased()) else { continue }
            if documents.count >= maxFilesPerFolder {
                isTruncated = true
                break
            }
            let path = url.standardizedFileURL.path
            let relative = path.hasPrefix(rootPath + "/") ? String(path.dropFirst(rootPath.count + 1)) : url.lastPathComponent
            documents.append(MarkdownDocument(url: url, relativePath: relative, modifiedAt: values?.contentModificationDate ?? .distantPast))
        }

        documents.sort { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
        return MarkdownFolder(url: folderURL, documents: documents, isMissing: false, isTruncated: isTruncated)
    }

    // MARK: - Documents

    /// Creates `<title>.md` in `directory` (a library folder or one of its subfolders), with a heading.
    @discardableResult
    public func createDocument(in directory: URL, title: String) throws -> URL {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = uniqueURL(in: directory, name: fileName(title))
        try "# \(url.deletingPathExtension().lastPathComponent)\n\n".write(to: url, atomically: true, encoding: .utf8)
        reload()
        return url
    }

    /// Renames a document in place, keeping its extension. Returns the new location.
    @discardableResult
    public func rename(_ document: MarkdownDocument, to title: String) throws -> URL {
        let name = fileName(title)
        guard name != document.name else { return document.url }
        let directory = document.url.deletingLastPathComponent()
        let url = uniqueURL(in: directory, name: name, ext: document.url.pathExtension)
        try fileManager.moveItem(at: document.url, to: url)
        reload()
        return url
    }

    public func delete(_ document: MarkdownDocument) throws {
        try fileManager.trashItem(at: document.url, resultingItemURL: nil)
        reload()
    }

    private func fileName(_ title: String) -> String {
        let blocked = CharacterSet(charactersIn: "/:\\[]#|^")
        let cleaned = title.components(separatedBy: blocked).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Untitled" : cleaned
    }

    private func uniqueURL(in folder: URL, name: String, ext: String = "md") -> URL {
        var url = folder.appendingPathComponent(name).appendingPathExtension(ext)
        var index = 2
        while fileManager.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(name) \(index)").appendingPathExtension(ext)
            index += 1
        }
        return url
    }
}
