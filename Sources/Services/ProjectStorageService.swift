import Foundation
import AppKit

@MainActor
public class ProjectStorageService: ObservableObject {
    public static let shared = ProjectStorageService()

    @Published public var projects: [LectureProject] = []
    @Published public var selectedProject: LectureProject?

    private let fileManager = FileManager.default

    public init() {
        reloadProjects()
    }

    public func reloadProjects() {
        let rootURL = AppSettings.shared.rootFolderURL

        // Ensure root directory exists
        if !fileManager.fileExists(atPath: rootURL.path) {
            try? fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        }

        guard let enumerator = try? fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey, .creationDateKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            self.projects = []
            return
        }

        var loadedProjects: [LectureProject] = []

        for itemURL in enumerator {
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: itemURL.path, isDirectory: &isDirectory), isDirectory.boolValue {
                let project = loadProject(at: itemURL)
                loadedProjects.append(project)
            }
        }

        // Sort projects by newest first
        self.projects = loadedProjects.sorted(by: { $0.createdAt > $1.createdAt })

        // Preserve or update selection
        if let current = selectedProject, let match = projects.first(where: { $0.id == current.id }) {
            self.selectedProject = match
        } else {
            self.selectedProject = projects.first
        }
    }

    public func loadProject(at folderURL: URL) -> LectureProject {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return LectureProject(folderURL: folderURL)
        }

        var transcripts: [TranscriptFile] = []
        var files: [LectureFile] = []

        for fileURL in contents {
            let ext = fileURL.pathExtension.lowercased()
            let isTranscript = ext == "md" || (ext == "txt" && fileURL.deletingPathExtension().lastPathComponent.localizedCaseInsensitiveContains("transcript"))
            if isTranscript {
                transcripts.append(TranscriptFile(url: fileURL))
            } else {
                files.append(LectureFile(url: fileURL))
            }
        }

        // Sort transcripts by date
        transcripts.sort(by: { $0.modifiedAt > $1.modifiedAt })
        files.sort(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending })

        return LectureProject(folderURL: folderURL, transcripts: transcripts, files: files)
    }

    public func createProject(named rawName: String) -> LectureProject? {
        let cleanName = sanitizeFileName(rawName.isEmpty ? "New Lecture" : rawName)
        let rootURL = AppSettings.shared.rootFolderURL
        var projectURL = rootURL.appendingPathComponent(cleanName)

        // Avoid collision
        var counter = 1
        while fileManager.fileExists(atPath: projectURL.path) {
            projectURL = rootURL.appendingPathComponent("\(cleanName) (\(counter))")
            counter += 1
        }

        do {
            try fileManager.createDirectory(at: projectURL, withIntermediateDirectories: true)
            reloadProjects()
            let created = projects.first(where: { $0.folderURL.path == projectURL.path })
            if let created = created {
                self.selectedProject = created
            }
            return created
        } catch {
            print("Failed to create project directory: \(error)")
            return nil
        }
    }

    public func renameProject(_ project: LectureProject, to newName: String) {
        let sanitized = sanitizeFileName(newName)
        guard !sanitized.isEmpty, sanitized != project.title else { return }

        let parentURL = project.folderURL.deletingLastPathComponent()
        let newURL = parentURL.appendingPathComponent(sanitized)

        do {
            try fileManager.moveItem(at: project.folderURL, to: newURL)
            reloadProjects()
            self.selectedProject = projects.first(where: { $0.folderURL.path == newURL.path })
        } catch {
            print("Failed to rename project: \(error)")
        }
    }

    public func deleteProject(_ project: LectureProject) {
        do {
            try fileManager.removeItem(at: project.folderURL)
            reloadProjects()
        } catch {
            print("Failed to delete project: \(error)")
        }
    }

    public func ingestFile(
        from sourceURL: URL,
        into project: LectureProject,
        action: FileIngestionAction? = nil
    ) throws -> LectureFile {
        let resolvedAction = action ?? AppSettings.shared.fileIngestionAction
        let destinationURL = project.folderURL.appendingPathComponent(sourceURL.lastPathComponent)

        var finalDestination = destinationURL
        var counter = 1
        let nameWithoutExt = sourceURL.deletingPathExtension().lastPathComponent
        let ext = sourceURL.pathExtension

        while fileManager.fileExists(atPath: finalDestination.path) {
            let uniqueName = "\(nameWithoutExt) (\(counter))" + (ext.isEmpty ? "" : ".\(ext)")
            finalDestination = project.folderURL.appendingPathComponent(uniqueName)
            counter += 1
        }

        switch resolvedAction {
        case .copy:
            try fileManager.copyItem(at: sourceURL, to: finalDestination)
        case .move:
            try fileManager.moveItem(at: sourceURL, to: finalDestination)
        }

        reloadProjects()
        return LectureFile(url: finalDestination)
    }

    public func copyFile(from sourceURL: URL, into project: LectureProject) throws -> LectureFile {
        try ingestFile(from: sourceURL, into: project, action: .copy)
    }

    public func saveTranscript(
        content: String,
        baseFileName: String,
        project: LectureProject,
        format: TranscriptFormat? = nil
    ) throws -> URL {
        let resolvedFormat = format ?? AppSettings.shared.transcriptFormat
        let cleanName = sanitizeFileName(baseFileName)
        let ext = resolvedFormat.fileExtension
        let fileName = cleanName.hasSuffix(".\(ext)") ? cleanName : "\(cleanName).\(ext)"
        let destURL = project.folderURL.appendingPathComponent(fileName)

        var finalDestination = destURL
        var counter = 1
        let nameNoExt = (fileName as NSString).deletingPathExtension

        while fileManager.fileExists(atPath: finalDestination.path) {
            finalDestination = project.folderURL.appendingPathComponent("\(nameNoExt) (\(counter)).\(ext)")
            counter += 1
        }

        try content.write(to: finalDestination, atomically: true, encoding: .utf8)
        reloadProjects()
        return finalDestination
    }

    public func saveTranscript(markdown: String, baseFileName: String, project: LectureProject) throws -> URL {
        try saveTranscript(content: markdown, baseFileName: baseFileName, project: project, format: .markdown)
    }

    public func revealInFinder(url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    public func openFile(url: URL) {
        NSWorkspace.shared.open(url)
    }

    private func sanitizeFileName(_ name: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "\\/:*?\"<>|")
        return name.components(separatedBy: invalidCharacters).joined(separator: "_").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
