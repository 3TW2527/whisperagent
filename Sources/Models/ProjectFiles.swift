import Foundation

/// A file or folder of the user's own work in a project, listed under Files.
public struct ProjectFileNode: Identifiable, Hashable, Sendable {
    public let url: URL
    public let isDirectory: Bool
    /// Nil for a file, so `OutlineGroup` shows no disclosure triangle.
    public var children: [ProjectFileNode]?

    public var id: String { url.path }
    public var name: String { url.lastPathComponent }
    public var fileExtension: String { url.pathExtension.lowercased() }

    /// Number of files in this folder and its subfolders.
    public var fileCount: Int {
        guard let children else { return 1 }
        return children.reduce(0) { $0 + $1.fileCount }
    }
}

/// Finds the user's own files in a project: everything in its root except the folders and files the app manages.
public enum ProjectFiles {
    static let maxDepth = 8

    public static func tree(of course: Course) -> [ProjectFileNode] {
        nodes(in: course.folderURL, depth: 0) { url in
            !Course.reservedRootNames.contains(url.lastPathComponent)
        }
    }

    /// The top-level items only, for PROJECT.md.
    public static func topLevelItems(of course: Course) -> [ProjectFileNode] {
        entries(in: course.folderURL)
            .filter { !Course.reservedRootNames.contains($0.lastPathComponent) }
            .map { ProjectFileNode(url: $0, isDirectory: isDirectory($0), children: nil) }
    }

    private static func nodes(in folder: URL, depth: Int, include: (URL) -> Bool = { _ in true }) -> [ProjectFileNode] {
        entries(in: folder).filter(include).map { url in
            if isDirectory(url) {
                let children = depth < maxDepth ? nodes(in: url, depth: depth + 1) : []
                return ProjectFileNode(url: url, isDirectory: true, children: children)
            }
            return ProjectFileNode(url: url, isDirectory: false, children: nil)
        }
    }

    /// Folders first, then files, each A–Z. Hidden files and Office/Windows clutter are left out.
    private static func entries(in folder: URL) -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return contents
            .filter { url in
                let name = url.lastPathComponent
                return !name.hasPrefix("~$") && name != "Thumbs.db" && name != "desktop.ini"
            }
            .sorted { a, b in
                let (aDir, bDir) = (isDirectory(a), isDirectory(b))
                if aDir != bDir { return aDir }
                return a.lastPathComponent.localizedStandardCompare(b.lastPathComponent) == .orderedAscending
            }
    }

    private static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
    }
}
