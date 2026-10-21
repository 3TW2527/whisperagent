import Foundation
import AppKit

/// A recording number held for an in-progress transcription, so parallel jobs never pick the same name.
public struct RecordingSlot: Hashable, Sendable {
    public let courseID: String
    public let lectureNumber: Int
    public let recordingNumber: Int
    public let baseName: String
}

public enum StorageError: LocalizedError {
    case courseNotFound
    case lectureNotFound
    case segmentsMissing
    case courseBusy
    case invalidDestination
    case destinationNotEmpty
    case noteNotFound

    public var errorDescription: String? {
        switch self {
        case .courseNotFound: return "The course folder could not be found. It may have been moved or renamed."
        case .lectureNotFound: return "The lecture no longer exists in this course."
        case .courseBusy: return "A transcription for this course is still running. Wait for it to finish, then try again."
        case .invalidDestination: return "A course can't be moved into itself."
        case .destinationNotEmpty: return "That folder already has files in it. Choose an empty folder, or create a new one."
        case .noteNotFound: return "The note could not be found. It may have been moved or deleted."
        case .segmentsMissing: return "No timing data is saved for this recording, so it can't be exported to another format. Transcripts created before this version only exist in their original format."
        }
    }
}

/// Reads and writes the course library on disk.
///
/// Layout under the root folder (courses can also live in other folders; see `moveCourse`):
/// ```
/// <Course>/course.json        metadata (source of truth for lectures and recordings)
/// <Course>/COURSE.md          generated overview
/// <Course>/materials/         slides, PDFs, notes for the whole course
/// <Course>/transcripts/       <Prefix>_L03_R1.md / .txt / .srt / .vtt
/// <Course>/notes/             the student's own Markdown notes
/// <Course>/.whisperlectures/  timing data used to re-export transcripts
/// ```
@MainActor
public class CourseStorageService: ObservableObject {
    public static let shared = CourseStorageService()

    @Published public private(set) var courses: [Course] = []
    @Published public var selectedCourseID: String?
    /// Folders left over from the old one-folder-per-lecture layout.
    @Published public private(set) var legacyFolders: [URL] = []

    private let fileManager = FileManager.default
    private var reservedSlots: Set<RecordingSlot> = []

    public init() {
        reload()
    }

    public var selectedCourse: Course? {
        guard let id = selectedCourseID else { return nil }
        return courses.first { $0.id == id }
    }

    public func course(id: String) -> Course? {
        courses.first { $0.id == id }
    }

    public var allTags: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for tag in courses.flatMap(\.tags) where seen.insert(tag.lowercased()).inserted {
            result.append(tag)
        }
        return result.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    // MARK: - Loading

    public func reload() {
        let rootURL = AppSettings.shared.rootFolderURL
        if !fileManager.fileExists(atPath: rootURL.path) {
            try? fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        }

        let entries = (try? fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var loaded: [Course] = []
        var legacy: [URL] = []
        for url in entries where isDirectory(url) {
            if let course = loadCourse(at: url) {
                loaded.append(course)
            } else {
                legacy.append(url)
            }
        }

        for path in AppSettings.shared.externalCoursePaths {
            let url = URL(fileURLWithPath: path)
            guard isDirectory(url), let course = loadCourse(at: url), !loaded.contains(where: { $0.id == course.id }) else { continue }
            loaded.append(course)
        }

        courses = loaded.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        legacyFolders = legacy.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        // Nothing is selected by default: selecting a course opens it.
        if selectedCourse == nil {
            selectedCourseID = nil
        }

        LibraryIndexGenerator.regenerate(rootURL: rootURL, courses: courses)
    }

    public func loadCourse(at folderURL: URL) -> Course? {
        let metadataURL = folderURL.appendingPathComponent(Course.metadataFileName)
        guard let metadata = readMetadata(at: metadataURL) else { return nil }

        let materialsURL = folderURL.appendingPathComponent(Course.materialsFolderName)
        let transcriptsURL = folderURL.appendingPathComponent(Course.transcriptsFolderName)

        let materials = listFiles(in: materialsURL)
            .map(LectureFile.init(url:))
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let transcripts = listFiles(in: transcriptsURL)
            .filter { TranscriptFile.supportedExtensions.contains($0.pathExtension.lowercased()) }
            .map(TranscriptFile.init(url:))
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        let notes = listFiles(in: folderURL.appendingPathComponent(Course.notesFolderName))
            .filter { $0.pathExtension.lowercased() == "md" }
            .map(NoteFile.init(url:))
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        var course = Course(folderURL: folderURL, metadata: metadata, materials: materials, transcripts: transcripts, notes: notes)
        course.isExternal = !isSameFolder(folderURL.deletingLastPathComponent(), AppSettings.shared.rootFolderURL)
        return course
    }

    // MARK: - Courses

    @discardableResult
    public func createCourse(name rawName: String, code: String = "", tags: [String] = [], location: URL? = nil) -> Course? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "New Course" : rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let code = code.trimmingCharacters(in: .whitespacesAndNewlines)
        // With a custom location, that folder itself is the course folder.
        let folderURL: URL
        if let location {
            guard Self.isUsableCourseFolder(location) else { return nil }
            folderURL = location.standardizedFileURL
        } else {
            folderURL = uniqueURL(in: AppSettings.shared.rootFolderURL, name: folderName(name: name, code: code), ext: "")
        }

        do {
            try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: folderURL.appendingPathComponent(Course.materialsFolderName), withIntermediateDirectories: true)
            try fileManager.createDirectory(at: folderURL.appendingPathComponent(Course.transcriptsFolderName), withIntermediateDirectories: true)
            let metadata = CourseMetadata(name: name, code: code, tags: Self.normalizedTags(tags))
            try writeMetadata(metadata, to: folderURL.appendingPathComponent(Course.metadataFileName))
            if !isSameFolder(folderURL.deletingLastPathComponent(), AppSettings.shared.rootFolderURL) {
                registerExternalCourse(folderURL)
            }
            reload()
            selectedCourseID = folderURL.path
            return course(id: folderURL.path)
        } catch {
            print("Failed to create course: \(error)")
            return nil
        }
    }

    /// Updates name, code and tags. Renames a library course's folder to match; transcript file names are kept.
    /// Returns the course's id, which changes when the folder is renamed.
    @discardableResult
    public func updateCourse(id: String, name: String, code: String, tags: [String]) throws -> String {
        guard let course = course(id: id) else { throw StorageError.courseNotFound }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)

        var folderURL = course.folderURL
        let desiredFolder = folderName(name: trimmedName.isEmpty ? course.name : trimmedName, code: trimmedCode)
        // A folder the user chose for the course keeps its name.
        if !course.isExternal, desiredFolder != folderURL.lastPathComponent, !hasActiveReservations(courseID: id) {
            let newURL = uniqueURL(in: folderURL.deletingLastPathComponent(), name: desiredFolder, ext: "")
            try fileManager.moveItem(at: folderURL, to: newURL)
            folderURL = newURL
        }

        try mutateMetadata(folderURL: folderURL) { meta in
            if !trimmedName.isEmpty { meta.name = trimmedName }
            meta.code = trimmedCode
            meta.tags = Self.normalizedTags(tags)
        }
        selectedCourseID = folderURL.path
        reload()
        return folderURL.path
    }

    /// Makes `destination` the course's folder, moving all of its files there. The folder must be new or empty.
    /// Pass nil to move the course back into the library folder. Returns the course's new id.
    @discardableResult
    public func moveCourse(id: String, to destination: URL?) throws -> String {
        guard let course = course(id: id) else { throw StorageError.courseNotFound }
        let library = AppSettings.shared.rootFolderURL
        let source = course.folderURL.standardizedFileURL
        let newURL: URL

        if let destination {
            newURL = destination.standardizedFileURL
            if newURL.path == source.path { return id }
            guard !hasActiveReservations(courseID: id) else { throw StorageError.courseBusy }
            guard !newURL.path.hasPrefix(source.path + "/") else { throw StorageError.invalidDestination }
            guard Self.isUsableCourseFolder(newURL) else { throw StorageError.destinationNotEmpty }
            if fileManager.fileExists(atPath: newURL.path) {
                try fileManager.removeItem(at: newURL)  // empty: moveItem needs the destination to be free
            } else {
                try fileManager.createDirectory(at: newURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            }
        } else {
            guard course.isExternal else { return id }
            guard !hasActiveReservations(courseID: id) else { throw StorageError.courseBusy }
            newURL = uniqueURL(in: library, name: source.lastPathComponent, ext: "")
        }

        try fileManager.moveItem(at: source, to: newURL)

        unregisterExternalCourse(course.folderURL)
        if !isSameFolder(newURL.deletingLastPathComponent(), library) {
            registerExternalCourse(newURL)
        }
        selectedCourseID = newURL.path
        reload()
        return newURL.path
    }

    /// True for a folder that doesn't exist yet or has nothing in it (Finder's .DS_Store aside).
    public static func isUsableCourseFolder(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return true }
        guard isDir.boolValue else { return false }
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
        return contents.allSatisfy { $0 == ".DS_Store" }
    }

    private func registerExternalCourse(_ url: URL) {
        let path = url.path
        if !AppSettings.shared.externalCoursePaths.contains(path) {
            AppSettings.shared.externalCoursePaths.append(path)
        }
    }

    private func unregisterExternalCourse(_ url: URL) {
        AppSettings.shared.externalCoursePaths.removeAll { $0 == url.path }
    }

    private func isSameFolder(_ a: URL, _ b: URL) -> Bool {
        a.standardizedFileURL.path == b.standardizedFileURL.path
    }

    public func deleteCourse(id: String) {
        guard let course = course(id: id) else { return }
        do {
            try fileManager.trashItem(at: course.folderURL, resultingItemURL: nil)
        } catch {
            print("Failed to move course to Trash: \(error)")
        }
        unregisterExternalCourse(course.folderURL)
        if selectedCourseID == id { selectedCourseID = nil }
        reload()
    }

    public func hasActiveReservations(courseID: String) -> Bool {
        reservedSlots.contains { $0.courseID == courseID }
    }

    // MARK: - Lectures

    @discardableResult
    public func addLecture(courseID: String, title: String, date: Date) throws -> Lecture {
        guard let course = course(id: courseID) else { throw StorageError.courseNotFound }
        var created: Lecture?
        try mutateMetadata(folderURL: course.folderURL) { meta in
            let lecture = Lecture(number: meta.nextLectureNumber, title: title.trimmingCharacters(in: .whitespacesAndNewlines), date: date)
            meta.lectures.append(lecture)
            created = lecture
        }
        reload()
        return created!
    }

    public func updateLecture(courseID: String, number: Int, title: String, date: Date) throws {
        guard let course = course(id: courseID) else { throw StorageError.courseNotFound }
        try mutateMetadata(folderURL: course.folderURL) { meta in
            guard let index = meta.lectures.firstIndex(where: { $0.number == number }) else { return }
            meta.lectures[index].title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            meta.lectures[index].date = date
        }
        reload()
    }

    /// Removes a lecture and moves its transcript files to the Trash.
    public func deleteLecture(courseID: String, number: Int) throws {
        guard let course = course(id: courseID), let lecture = course.lecture(number: number) else { throw StorageError.lectureNotFound }
        for group in course.recordingGroups(for: lecture) {
            trashRecordingFiles(course: course, baseName: group.baseName)
        }
        try mutateMetadata(folderURL: course.folderURL) { meta in
            meta.lectures.removeAll { $0.number == number }
        }
        reload()
    }

    public func deleteRecording(courseID: String, baseName: String) throws {
        guard let course = course(id: courseID) else { throw StorageError.courseNotFound }
        trashRecordingFiles(course: course, baseName: baseName)
        try mutateMetadata(folderURL: course.folderURL) { meta in
            for index in meta.lectures.indices {
                meta.lectures[index].recordings.removeAll { $0.baseName == baseName }
            }
        }
        reload()
    }

    private func trashRecordingFiles(course: Course, baseName: String) {
        for file in course.transcripts where file.baseName == baseName {
            try? fileManager.trashItem(at: file.url, resultingItemURL: nil)
        }
        let segments = course.segmentsURL.appendingPathComponent("\(baseName).json")
        try? fileManager.removeItem(at: segments)
    }

    // MARK: - Notes

    /// Creates an empty note. The name is made unique and safe for `[[wikilinks]]`.
    @discardableResult
    public func createNote(courseID: String, title: String) throws -> NoteFile {
        guard let course = course(id: courseID) else { throw StorageError.courseNotFound }
        try fileManager.createDirectory(at: course.notesURL, withIntermediateDirectories: true)
        let name = noteFileName(title)
        let url = uniqueURL(in: course.notesURL, name: name, ext: "md")
        try "# \(url.deletingPathExtension().lastPathComponent)\n\n".write(to: url, atomically: true, encoding: .utf8)
        reload()
        return NoteFile(url: url)
    }

    @discardableResult
    public func renameNote(courseID: String, note: NoteFile, to title: String) throws -> NoteFile {
        guard let course = course(id: courseID) else { throw StorageError.courseNotFound }
        guard fileManager.fileExists(atPath: note.url.path) else { throw StorageError.noteNotFound }
        let name = noteFileName(title)
        if name == note.name { return note }
        let url = uniqueURL(in: course.notesURL, name: name, ext: "md")
        try fileManager.moveItem(at: note.url, to: url)
        reload()
        return NoteFile(url: url)
    }

    public func deleteNote(courseID: String, note: NoteFile) throws {
        try fileManager.trashItem(at: note.url, resultingItemURL: nil)
        reload()
    }

    /// Saves note text without reloading the library, so typing never rebuilds the UI.
    public func writeNote(_ note: NoteFile, text: String) throws {
        try text.write(to: note.url, atomically: true, encoding: .utf8)
    }

    private func noteFileName(_ title: String) -> String {
        let blocked = CharacterSet(charactersIn: "[]#|^")
        let cleaned = sanitizeFileName(title).components(separatedBy: blocked).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Untitled" : cleaned
    }

    // MARK: - Materials

    @discardableResult
    public func ingestMaterial(from sourceURL: URL, courseID: String, action: FileIngestionAction? = nil) throws -> LectureFile {
        guard let course = course(id: courseID) else { throw StorageError.courseNotFound }
        let resolvedAction = action ?? AppSettings.shared.fileIngestionAction
        try fileManager.createDirectory(at: course.materialsURL, withIntermediateDirectories: true)
        let destination = uniqueURL(
            in: course.materialsURL,
            name: sourceURL.deletingPathExtension().lastPathComponent,
            ext: sourceURL.pathExtension
        )

        switch resolvedAction {
        case .copy: try fileManager.copyItem(at: sourceURL, to: destination)
        case .move: try fileManager.moveItem(at: sourceURL, to: destination)
        }

        reload()
        return LectureFile(url: destination)
    }

    public func deleteMaterial(_ file: LectureFile) {
        try? fileManager.trashItem(at: file.url, resultingItemURL: nil)
        reload()
    }

    // MARK: - Recordings

    /// The base name a new recording would get, without reserving it.
    public func proposedRecordingName(courseID: String, lectureNumber: Int) -> String? {
        guard let course = course(id: courseID) else { return nil }
        let number = nextRecordingNumber(course: course, lectureNumber: lectureNumber)
        return defaultBaseName(course: course, lectureNumber: lectureNumber, recordingNumber: number)
    }

    /// Reserves the next recording number for a lecture. Pass `customName` to override the default
    /// `<Prefix>_L03_R2` name; it is made unique if needed.
    public func reserveRecording(courseID: String, lectureNumber: Int, customName: String? = nil) throws -> RecordingSlot {
        guard let course = course(id: courseID) else { throw StorageError.courseNotFound }
        guard course.lecture(number: lectureNumber) != nil else { throw StorageError.lectureNotFound }

        let number = nextRecordingNumber(course: course, lectureNumber: lectureNumber)
        let trimmedCustom = sanitizeFileName(customName ?? "")
        let preferred = trimmedCustom.isEmpty ? defaultBaseName(course: course, lectureNumber: lectureNumber, recordingNumber: number) : trimmedCustom

        let taken = Set(course.transcripts.map(\.baseName))
            .union(reservedSlots.filter { $0.courseID == courseID }.map(\.baseName))
            .union(course.metadata.lectures.flatMap(\.recordings).map(\.baseName))
        var baseName = preferred
        var counter = 2
        while taken.contains(baseName) {
            baseName = "\(preferred)-\(counter)"
            counter += 1
        }

        let slot = RecordingSlot(courseID: courseID, lectureNumber: lectureNumber, recordingNumber: number, baseName: baseName)
        reservedSlots.insert(slot)
        return slot
    }

    public func releaseRecording(_ slot: RecordingSlot) {
        reservedSlots.remove(slot)
    }

    /// Writes every requested format plus the timing data, records the recording in `course.json`,
    /// and releases the reservation.
    @discardableResult
    public func saveRecording(
        slot: RecordingSlot,
        document: SegmentsDocument,
        formats: [TranscriptFormat],
        durationSeconds: Double
    ) throws -> [URL] {
        defer { releaseRecording(slot) }
        guard let course = course(id: slot.courseID) else { throw StorageError.courseNotFound }

        try fileManager.createDirectory(at: course.transcriptsURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: course.segmentsURL, withIntermediateDirectories: true)

        let segmentsData = try SegmentsDocument.encoder().encode(document)
        try segmentsData.write(to: course.segmentsURL.appendingPathComponent("\(slot.baseName).json"), options: .atomic)

        var written: [URL] = []
        for format in formats {
            let url = course.transcriptsURL.appendingPathComponent("\(slot.baseName).\(format.fileExtension)")
            let content = TranscriptFormatter.render(format, segments: document.segments, context: document.context)
            try content.write(to: url, atomically: true, encoding: .utf8)
            written.append(url)
        }

        try mutateMetadata(folderURL: course.folderURL) { meta in
            guard let index = meta.lectures.firstIndex(where: { $0.number == slot.lectureNumber }) else { return }
            meta.lectures[index].recordings.removeAll { $0.baseName == slot.baseName }
            meta.lectures[index].recordings.append(RecordingInfo(
                number: slot.recordingNumber,
                baseName: slot.baseName,
                sourceAudio: document.context.sourceAudio,
                model: document.context.model,
                transcribedAt: document.context.transcribedAt,
                durationSeconds: durationSeconds
            ))
        }
        reload()
        return written
    }

    public func hasTimingData(courseID: String, baseName: String) -> Bool {
        guard let course = course(id: courseID) else { return false }
        return fileManager.fileExists(atPath: course.segmentsURL.appendingPathComponent("\(baseName).json").path)
    }

    /// Creates (or overwrites) one format of an existing recording from its saved timing data.
    @discardableResult
    public func exportRecording(courseID: String, baseName: String, format: TranscriptFormat) throws -> URL {
        guard let course = course(id: courseID) else { throw StorageError.courseNotFound }
        let segmentsURL = course.segmentsURL.appendingPathComponent("\(baseName).json")
        guard let data = try? Data(contentsOf: segmentsURL) else { throw StorageError.segmentsMissing }
        var document = try SegmentsDocument.decoder().decode(SegmentsDocument.self, from: data)

        // Use the current course and lecture details in case they were edited since transcription.
        document.context.courseName = course.name
        document.context.courseCode = course.metadata.code
        if let lecture = course.metadata.lectures.first(where: { $0.recordings.contains { $0.baseName == baseName } }) {
            document.context.lectureNumber = lecture.number
            document.context.lectureTitle = lecture.title
            document.context.lectureDate = lecture.date
        }

        let url = course.transcriptsURL.appendingPathComponent("\(baseName).\(format.fileExtension)")
        try TranscriptFormatter.render(format, segments: document.segments, context: document.context)
            .write(to: url, atomically: true, encoding: .utf8)
        reload()
        return url
    }

    private func nextRecordingNumber(course: Course, lectureNumber: Int) -> Int {
        let fromMetadata = course.lecture(number: lectureNumber)?.recordings.map(\.number) ?? []
        let fromReservations = reservedSlots.filter { $0.courseID == course.id && $0.lectureNumber == lectureNumber }.map(\.recordingNumber)
        let label = String(format: "_L%02d_R", lectureNumber)
        let fromFiles = course.transcripts.compactMap { file -> Int? in
            guard let range = file.baseName.range(of: label) else { return nil }
            return Int(file.baseName[range.upperBound...].prefix { $0.isNumber })
        }
        return ((fromMetadata + fromReservations + fromFiles).max() ?? 0) + 1
    }

    private func defaultBaseName(course: Course, lectureNumber: Int, recordingNumber: Int) -> String {
        String(format: "%@_L%02d_R%d", course.filePrefix, lectureNumber, recordingNumber)
    }

    // MARK: - Legacy Migration

    /// Turns an old lecture-project folder into a lecture of a course. Transcripts are renamed to the
    /// course naming scheme and other files move to the course materials folder. The old folder is
    /// removed once empty.
    public func migrateLegacyFolder(_ folderURL: URL, intoCourseID courseID: String) throws {
        guard let course = course(id: courseID) else { throw StorageError.courseNotFound }
        let created = (try? folderURL.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
        let lecture = try addLecture(courseID: courseID, title: folderURL.lastPathComponent, date: created)

        try fileManager.createDirectory(at: course.transcriptsURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: course.materialsURL, withIntermediateDirectories: true)

        let files = listFiles(in: folderURL)
        let transcriptFiles = files.filter { Self.isLegacyTranscript($0) }
        let otherFiles = files.filter { !Self.isLegacyTranscript($0) }

        // Files with the same base name (e.g. talk.md + talk.txt) count as one recording.
        let grouped = Dictionary(grouping: transcriptFiles) { $0.deletingPathExtension().lastPathComponent }
        var recordings: [RecordingInfo] = []
        for (index, entry) in grouped.sorted(by: { $0.key.localizedStandardCompare($1.key) == .orderedAscending }).enumerated() {
            let number = index + 1
            guard let current = self.course(id: courseID) else { break }
            let baseName = defaultBaseName(course: current, lectureNumber: lecture.number, recordingNumber: number)
            for file in entry.value {
                let destination = uniqueURL(in: course.transcriptsURL, name: baseName, ext: file.pathExtension.lowercased())
                try fileManager.moveItem(at: file, to: destination)
            }
            recordings.append(RecordingInfo(number: number, baseName: baseName, sourceAudio: entry.key, model: "unknown", transcribedAt: created, durationSeconds: 0))
        }

        for file in otherFiles {
            let destination = uniqueURL(in: course.materialsURL, name: file.deletingPathExtension().lastPathComponent, ext: file.pathExtension)
            try fileManager.moveItem(at: file, to: destination)
        }

        try mutateMetadata(folderURL: course.folderURL) { meta in
            guard let index = meta.lectures.firstIndex(where: { $0.number == lecture.number }) else { return }
            meta.lectures[index].recordings = recordings
        }

        let remaining = (try? fileManager.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        if remaining.isEmpty {
            try? fileManager.removeItem(at: folderURL)
        }
        reload()
    }

    static func isLegacyTranscript(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "md" || (ext == "txt" && url.deletingPathExtension().lastPathComponent.localizedCaseInsensitiveContains("transcript"))
    }

    // MARK: - Finder

    public func revealInFinder(url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    public func openFile(url: URL) {
        NSWorkspace.shared.open(url)
    }

    // MARK: - Helpers

    private func mutateMetadata(folderURL: URL, _ change: (inout CourseMetadata) -> Void) throws {
        let url = folderURL.appendingPathComponent(Course.metadataFileName)
        guard var metadata = readMetadata(at: url) else { throw StorageError.courseNotFound }
        change(&metadata)
        try writeMetadata(metadata, to: url)
    }

    private func readMetadata(at url: URL) -> CourseMetadata? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? SegmentsDocument.decoder().decode(CourseMetadata.self, from: data)
    }

    private func writeMetadata(_ metadata: CourseMetadata, to url: URL) throws {
        var sorted = metadata
        sorted.lectures.sort { $0.number < $1.number }
        for index in sorted.lectures.indices {
            sorted.lectures[index].recordings.sort { $0.number < $1.number }
        }
        try SegmentsDocument.encoder().encode(sorted).write(to: url, options: .atomic)
    }

    private func listFiles(in folderURL: URL) -> [URL] {
        let contents = (try? fileManager.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return contents.filter { !isDirectory($0) }
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    private func uniqueURL(in folder: URL, name: String, ext: String) -> URL {
        let suffix = ext.isEmpty ? "" : ".\(ext)"
        var candidate = folder.appendingPathComponent(name + suffix)
        var counter = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(name) (\(counter))\(suffix)")
            counter += 1
        }
        return candidate
    }

    private func folderName(name: String, code: String) -> String {
        sanitizeFileName(code.isEmpty ? name : "\(code) \(name)")
    }

    private func sanitizeFileName(_ name: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "\\/:*?\"<>|")
        return name.components(separatedBy: invalidCharacters).joined(separator: "_").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func normalizedTags(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        return tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    public static func parseTags(_ text: String) -> [String] {
        normalizedTags(text.components(separatedBy: ","))
    }
}
