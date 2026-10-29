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
    case projectFolderTaken
    case alreadyProject

    public var errorDescription: String? {
        switch self {
        case .courseNotFound: return "The course folder could not be found. It may have been moved or renamed."
        case .lectureNotFound: return "The lecture no longer exists in this course."
        case .courseBusy: return "A transcription for this course is still running. Wait for it to finish, then try again."
        case .invalidDestination: return "A course can't be moved into itself."
        case .destinationNotEmpty: return "That folder already has files in it. Choose an empty folder, or create a new one."
        case .noteNotFound: return "The note could not be found. It may have been moved or deleted."
        case .projectFolderTaken: return "That folder already belongs to a course or project (it has a course.json). Choose another folder."
        case .alreadyProject: return "This is already a project."
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
/// A project has the same layout plus `PROJECT.md` (instead of `COURSE.md`), `ACTIONS.md`, `meetings/M03/` for
/// each meeting's own files, and any folders of the user's own work, which the app leaves alone.
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
        if metadata.kind == .project {
            course.meetingFiles = loadMeetingFiles(in: course.meetingsURL)
            course.actions = ActionScanner.scan(notes)
        }
        course.isExternal = !isSameFolder(folderURL.deletingLastPathComponent(), AppSettings.shared.rootFolderURL)
        return course
    }

    /// Files in `meetings/M03/` folders, by meeting number.
    private func loadMeetingFiles(in meetingsURL: URL) -> [Int: [LectureFile]] {
        let folders = (try? fileManager.contentsOfDirectory(at: meetingsURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        var result: [Int: [LectureFile]] = [:]
        for folder in folders where isDirectory(folder) {
            let name = folder.lastPathComponent
            guard name.hasPrefix(CourseKind.project.unitLetter), let number = Int(name.dropFirst()) else { continue }
            let files = listFiles(in: folder)
                .map(LectureFile.init(url:))
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            if !files.isEmpty { result[number] = files }
        }
        return result
    }

    /// Re-reads one course after its notes changed, e.g. a note was saved or the phone added to it, and rewrites
    /// its generated files. Cheaper than `reload()`, which reads the whole library.
    public func refresh(courseID: String) {
        guard let index = courses.firstIndex(where: { $0.id == courseID }),
              let course = loadCourse(at: courses[index].folderURL) else { return }
        guard course != courses[index] else { return }
        courses[index] = course
        LibraryIndexGenerator.regenerate(course: course)
    }

    // MARK: - Actions

    /// Ticks or unticks an action in its note.
    public func setAction(_ item: ActionItem, done: Bool, courseID: String) throws {
        try ActionScanner.setDone(item, done)
        refresh(courseID: courseID)
    }

    // MARK: - Courses

    /// Creates a course or project. With a custom location, that folder itself is its folder: a course needs an
    /// empty one, while a project can adopt a folder that already holds the user's files.
    @discardableResult
    public func createCourse(kind: CourseKind = .course, name rawName: String, code: String = "", tags: [String] = [], location: URL? = nil) -> Course? {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? "New \(kind.displayName)" : trimmed
        let code = code.trimmingCharacters(in: .whitespacesAndNewlines)
        let folderURL: URL
        if let location {
            guard Self.isUsableFolder(location, for: kind) else { return nil }
            folderURL = location.standardizedFileURL
        } else {
            folderURL = uniqueURL(in: AppSettings.shared.rootFolderURL, name: folderName(name: name, code: code), ext: "")
        }

        do {
            try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: folderURL.appendingPathComponent(Course.materialsFolderName), withIntermediateDirectories: true)
            try fileManager.createDirectory(at: folderURL.appendingPathComponent(Course.transcriptsFolderName), withIntermediateDirectories: true)
            if kind == .project {
                try fileManager.createDirectory(at: folderURL.appendingPathComponent(Course.meetingsFolderName), withIntermediateDirectories: true)
                try fileManager.createDirectory(at: folderURL.appendingPathComponent(Course.notesFolderName), withIntermediateDirectories: true)
            }
            let metadata = CourseMetadata(kind: kind, name: name, code: code, tags: Self.normalizedTags(tags))
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

    /// A course needs an empty folder. A project can also adopt a folder of existing files, as long as it isn't
    /// already a course or project.
    public static func isUsableFolder(_ url: URL, for kind: CourseKind) -> Bool {
        switch kind {
        case .course:
            return isUsableCourseFolder(url)
        case .project:
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return true }
            return isDir.boolValue && !FileManager.default.fileExists(atPath: url.appendingPathComponent(Course.metadataFileName).path)
        }
    }

    /// Saves a project's meeting series and key dates.
    public func updateProjectPlan(id: String, series: [MeetingSeries], keyDates: [KeyDate]) throws {
        guard let course = course(id: id) else { throw StorageError.courseNotFound }
        var seen = Set<String>()
        let cleaned = series.compactMap { item -> MeetingSeries? in
            var item = item
            item.name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !item.name.isEmpty, seen.insert(item.name.lowercased()).inserted else { return nil }
            return item
        }
        try mutateMetadata(folderURL: course.folderURL) { meta in
            meta.series = cleaned
            meta.keyDates = keyDates
                .filter { !$0.title.trimmingCharacters(in: .whitespaces).isEmpty }
                .sorted { $0.date < $1.date }
        }
        reload()
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

    /// Sends a Canvas course's downloads to this course's materials folder, or to Downloads when `courseID` is nil.
    public func linkCanvasCourse(_ canvasCourseID: Int, toCourseID courseID: String?) throws {
        for course in courses where course.metadata.canvasCourseIDs.contains(canvasCourseID) && course.id != courseID {
            try mutateMetadata(folderURL: course.folderURL) { $0.canvasCourseIDs.removeAll { $0 == canvasCourseID } }
        }
        if let courseID, let course = course(id: courseID), !course.metadata.canvasCourseIDs.contains(canvasCourseID) {
            try mutateMetadata(folderURL: course.folderURL) { $0.canvasCourseIDs.append(canvasCourseID) }
        }
        reload()
    }

    /// The local course a Canvas course downloads into, if it's linked to one.
    public func course(linkedToCanvas canvasCourseID: Int) -> Course? {
        courses.first { $0.metadata.canvasCourseIDs.contains(canvasCourseID) }
    }

    public func hasActiveReservations(courseID: String) -> Bool {
        reservedSlots.contains { $0.courseID == courseID }
    }

    // MARK: - Lectures

    /// Adds a lecture or meeting with the next number. `series` is for a project's meetings.
    @discardableResult
    public func addLecture(courseID: String, title: String, date: Date, series: String? = nil) throws -> Lecture {
        guard let course = course(id: courseID) else { throw StorageError.courseNotFound }
        var created: Lecture?
        try mutateMetadata(folderURL: course.folderURL) { meta in
            let lecture = Lecture(number: meta.nextLectureNumber, title: title.trimmingCharacters(in: .whitespacesAndNewlines), date: date, series: Self.cleanedSeries(series), kind: meta.kind)
            meta.lectures.append(lecture)
            created = lecture
        }
        reload()
        // Reloaded so the meeting comes back with its place in its series.
        return self.course(id: courseID)?.lecture(number: created!.number) ?? created!
    }

    public func updateLecture(courseID: String, number: Int, title: String, date: Date, series: String? = nil) throws {
        guard let course = course(id: courseID) else { throw StorageError.courseNotFound }
        try mutateMetadata(folderURL: course.folderURL) { meta in
            guard let index = meta.lectures.firstIndex(where: { $0.number == number }) else { return }
            meta.lectures[index].title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            meta.lectures[index].date = date
            meta.lectures[index].series = Self.cleanedSeries(series)
        }
        reload()
    }

    private static func cleanedSeries(_ series: String?) -> String? {
        let trimmed = series?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Removes a lecture and moves its transcript files (and a meeting's own files) to the Trash.
    public func deleteLecture(courseID: String, number: Int) throws {
        guard let course = course(id: courseID), let lecture = course.lecture(number: number) else { throw StorageError.lectureNotFound }
        for group in course.recordingGroups(for: lecture) {
            trashRecordingFiles(course: course, baseName: group.baseName)
        }
        let meetingFolder = course.meetingFolderURL(number: number)
        if course.isProject, fileManager.fileExists(atPath: meetingFolder.path) {
            try? fileManager.trashItem(at: meetingFolder, resultingItemURL: nil)
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

    /// Creates an empty note named `L03 <lecture title> · <date> · <index>` (or `Note · <date> · <index>` without a
    /// lecture), so several notes can exist for one lecture. The name is unique and safe for `[[wikilinks]]`.
    /// A meeting's note starts with Agenda, Notes and Actions headings.
    @discardableResult
    public func createNote(courseID: String, lecture: Lecture?) throws -> NoteFile {
        guard let course = course(id: courseID) else { throw StorageError.courseNotFound }
        let date = lecture?.date ?? Date()
        let existing = course.notes(for: lecture).count
        let title = noteTitle(for: lecture, date: date, suffix: String(existing + 1))
        let template = course.isProject && lecture != nil ? "## Agenda\n\n\n## Notes\n\n\n## Actions\n\n- [ ] \n" : ""
        return try createNote(courseID: courseID, title: title, body: template)
    }

    /// `M03 Team Meeting 2 · 2026-03-12 · <suffix>`, or `Note · <date> · <suffix>` without a lecture.
    func noteTitle(for lecture: Lecture?, date: Date, suffix: String) -> String {
        var parts = [lecture.map { [$0.label, $0.shortTitle.trimmingCharacters(in: .whitespaces)].filter { !$0.isEmpty }.joined(separator: " ") } ?? "Note"]
        parts.append(date.formatted(.iso8601.year().month().day()))
        parts.append(suffix)
        return parts.joined(separator: " · ")
    }

    /// Creates a note with this title, e.g. from a `[[wikilink]]` to a note that doesn't exist yet.
    @discardableResult
    public func createNote(courseID: String, title: String, body: String = "") throws -> NoteFile {
        guard let course = course(id: courseID) else { throw StorageError.courseNotFound }
        try fileManager.createDirectory(at: course.notesURL, withIntermediateDirectories: true)
        let name = noteFileName(title)
        let url = uniqueURL(in: course.notesURL, name: name, ext: "md")
        try "# \(url.deletingPathExtension().lastPathComponent)\n\n\(body)".write(to: url, atomically: true, encoding: .utf8)
        reload()
        return NoteFile(url: url)
    }

    @discardableResult
    public func renameNote(courseID: String, note: NoteFile, to title: String) throws -> NoteFile {
        guard let course = course(id: courseID) else { throw StorageError.courseNotFound }
        guard fileManager.fileExists(atPath: note.url.path) else { throw StorageError.noteNotFound }
        var name = noteFileName(title)
        // A lecture's notes keep their `L03 ` prefix so they stay attached to that lecture.
        if let number = note.lectureNumber {
            let prefix = Lecture.label(number: number, kind: course.kind)
            if !name.hasPrefix(prefix + " ") { name = "\(prefix) \(name)" }
        }
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

    private func noteFileName(_ title: String) -> String {
        let blocked = CharacterSet(charactersIn: "[]#|^")
        let cleaned = sanitizeFileName(title).components(separatedBy: blocked).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Untitled" : cleaned
    }

    // MARK: - Materials

    /// Adds a file to the course's materials, or to one meeting's folder when `meetingNumber` is set.
    @discardableResult
    public func ingestMaterial(from sourceURL: URL, courseID: String, meetingNumber: Int? = nil, action: FileIngestionAction? = nil) throws -> LectureFile {
        guard let course = course(id: courseID) else { throw StorageError.courseNotFound }
        let resolvedAction = action ?? AppSettings.shared.fileIngestionAction
        let folder = meetingNumber.map { course.meetingFolderURL(number: $0) } ?? course.materialsURL
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = uniqueURL(
            in: folder,
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

    /// Saves data as a new file in one meeting's folder, or in the materials when `meetingNumber` is nil, e.g. a
    /// photo sent from the phone notepad.
    @discardableResult
    public func saveFile(_ data: Data, named name: String, courseID: String, meetingNumber: Int?) throws -> LectureFile {
        guard let course = course(id: courseID) else { throw StorageError.courseNotFound }
        let folder = meetingNumber.map { course.meetingFolderURL(number: $0) } ?? course.materialsURL
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let cleaned = sanitizeFileName(name)
        let base = (cleaned as NSString).deletingPathExtension
        let destination = uniqueURL(in: folder, name: base.isEmpty ? "File" : base, ext: (cleaned as NSString).pathExtension)
        try data.write(to: destination, options: .atomic)
        reload()
        return LectureFile(url: destination)
    }

    /// Moves a project file between the project's materials (`meetingNumber` nil) and a meeting's folder.
    public func moveFile(_ file: LectureFile, courseID: String, toMeeting meetingNumber: Int?) throws {
        guard let course = course(id: courseID) else { throw StorageError.courseNotFound }
        let folder = meetingNumber.map { course.meetingFolderURL(number: $0) } ?? course.materialsURL
        guard file.url.deletingLastPathComponent().standardizedFileURL.path != folder.standardizedFileURL.path else { return }
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = uniqueURL(in: folder, name: file.url.deletingPathExtension().lastPathComponent, ext: file.url.pathExtension)
        try fileManager.moveItem(at: file.url, to: destination)
        removeIfEmpty(file.url.deletingLastPathComponent(), unlessSameAs: course.materialsURL)
        reload()
    }

    /// Removes a meeting folder left empty (Finder's .DS_Store aside).
    private func removeIfEmpty(_ folder: URL, unlessSameAs keep: URL) {
        guard folder.standardizedFileURL.path != keep.standardizedFileURL.path else { return }
        let contents = (try? fileManager.contentsOfDirectory(atPath: folder.path)) ?? []
        if contents.allSatisfy({ $0 == ".DS_Store" }) {
            try? fileManager.removeItem(at: folder)
        }
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
        document.context.kind = course.kind
        if let lecture = course.metadata.lectures.first(where: { $0.recordings.contains { $0.baseName == baseName } }) {
            document.context.update(course: course, lecture: lecture)
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
        let label = "_\(Lecture.label(number: lectureNumber, kind: course.kind))_R"
        let fromFiles = course.transcripts.compactMap { file -> Int? in
            guard let range = file.baseName.range(of: label) else { return nil }
            return Int(file.baseName[range.upperBound...].prefix { $0.isNumber })
        }
        return ((fromMetadata + fromReservations + fromFiles).max() ?? 0) + 1
    }

    private func defaultBaseName(course: Course, lectureNumber: Int, recordingNumber: Int) -> String {
        "\(course.filePrefix)_\(Lecture.label(number: lectureNumber, kind: course.kind))_R\(recordingNumber)"
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

    // MARK: - Converting to a Project

    /// What converting a course to a project would do, shown before the user confirms.
    public struct ProjectConversionPlan: Sendable {
        public var root: URL
        public var code: String
        /// Old and new base names of recordings, and old and new names of notes.
        public var recordingRenames: [(String, String)]
        public var noteRenames: [(String, String)]
        public var series: [MeetingSeries]
        /// Meeting numbers whose title becomes their series' default title, e.g. "Team Meeting 2".
        public var titlesCleared: Set<Int>
    }

    /// Plans turning a course into a project whose root is `root`: the course's own folder, or a folder that
    /// contains it (the course's files then move up into it).
    public func planProjectConversion(courseID: String, root rawRoot: URL, code rawCode: String) throws -> ProjectConversionPlan {
        guard let course = course(id: courseID) else { throw StorageError.courseNotFound }
        guard !course.isProject else { throw StorageError.alreadyProject }
        let root = rawRoot.standardizedFileURL
        let source = course.folderURL.standardizedFileURL
        guard root.path == source.path || source.path.hasPrefix(root.path + "/") else { throw StorageError.invalidDestination }
        if root.path != source.path, fileManager.fileExists(atPath: root.appendingPathComponent(Course.metadataFileName).path) {
            throw StorageError.projectFolderTaken
        }

        let code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = Course.slug(code.isEmpty ? course.name : code)

        // Recordings with the default `_L03_R1` name get the project's `_M03_R1` name.
        var renames: [(String, String)] = []
        var taken = Set<String>()
        for lecture in course.lectures {
            for recording in lecture.recordings.sorted(by: { $0.number < $1.number }) {
                let old = recording.baseName
                guard old.contains("_\(Lecture.label(number: lecture.number, kind: .course))_R") else { continue }
                var new = "\(prefix)_\(Lecture.label(number: lecture.number, kind: .project))_R\(recording.number)"
                var counter = 2
                while taken.contains(new) { new = "\(new)-\(counter)"; counter += 1 }
                taken.insert(new)
                if new != old { renames.append((old, new)) }
            }
        }

        let noteRenames = course.notes.compactMap { note -> (String, String)? in
            guard note.lectureNumber != nil, note.name.hasPrefix(CourseKind.course.unitLetter) else { return nil }
            return (note.name, CourseKind.project.unitLetter + note.name.dropFirst())
        }

        // Titles like "Team Meeting 2" become meetings of the "Team" series.
        var seriesNames: [String] = []
        var seriesOf: [Int: String] = [:]
        for lecture in course.lectures {
            guard let match = lecture.title.firstMatch(of: /^(.+?)\s+[Mm]eeting\s+\d+$/) else { continue }
            let name = String(match.1).trimmingCharacters(in: .whitespaces)
            if let existing = seriesNames.first(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
                seriesOf[lecture.number] = existing
            } else {
                seriesNames.append(name)
                seriesOf[lecture.number] = name
            }
        }
        var trial = course.metadata
        trial.kind = .project
        for index in trial.lectures.indices {
            trial.lectures[index].series = seriesOf[trial.lectures[index].number]
        }
        trial.normalize()
        let cleared = Set(trial.lectures.filter { $0.series != nil && $0.title == $0.seriesTitle }.map(\.number))

        // A series whose meetings all fall on one weekday gets that day, and the time of its latest meeting.
        let calendar = Calendar.current
        let series = seriesNames.map { name -> MeetingSeries in
            let meetings = trial.lectures.filter { $0.series == name }.sorted { $0.date < $1.date }
            let weekdays = Set(meetings.map { calendar.component(.weekday, from: $0.date) })
            guard meetings.count >= 2, weekdays.count == 1, let latest = meetings.last else { return MeetingSeries(name: name) }
            let time = calendar.dateComponents([.hour, .minute], from: latest.date)
            return MeetingSeries(name: name, weekday: weekdays.first, minuteOfDay: (time.hour ?? 0) * 60 + (time.minute ?? 0))
        }

        // The root as chosen, not standardized: it becomes the project's id and its saved path.
        return ProjectConversionPlan(root: rawRoot, code: code, recordingRenames: renames, noteRenames: noteRenames, series: series, titlesCleared: cleared)
    }

    /// Turns a course into a project as planned. Transcripts and notes are renamed from `L03` to `M03`, links to
    /// renamed notes are updated, and the course's files move into the project root. Returns the project's id.
    @discardableResult
    public func convertToProject(courseID: String, plan: ProjectConversionPlan) throws -> String {
        guard let course = course(id: courseID) else { throw StorageError.courseNotFound }
        guard !hasActiveReservations(courseID: courseID) else { throw StorageError.courseBusy }
        let source = course.folderURL
        let root = plan.root
        let inPlace = root.standardizedFileURL.path == source.standardizedFileURL.path

        // 1. Rename transcripts and their timing data inside the course folder.
        for (old, new) in plan.recordingRenames {
            for file in course.transcripts where file.baseName == old {
                try fileManager.moveItem(at: file.url, to: course.transcriptsURL.appendingPathComponent("\(new).\(file.url.pathExtension)"))
            }
            let segments = course.segmentsURL.appendingPathComponent("\(old).json")
            if fileManager.fileExists(atPath: segments.path) {
                try fileManager.moveItem(at: segments, to: course.segmentsURL.appendingPathComponent("\(new).json"))
            }
        }

        // 2. Rename notes, then point their headings and every [[link]] at the new names.
        let noteMap = Dictionary(uniqueKeysWithValues: plan.noteRenames)
        for note in course.notes {
            let newName = noteMap[note.name] ?? note.name
            var text = (try? String(contentsOf: note.url, encoding: .utf8)) ?? ""
            let original = text
            for (old, new) in plan.noteRenames {
                text = text.replacingOccurrences(of: "# \(old)\n", with: "# \(new)\n")
                text = text.replacingOccurrences(of: "[[\(old)", with: "[[\(new)")
            }
            text = text.replacing(/\[\[Lecture (\d+)/) { "[[Meeting \($0.1)" }
            let destination = course.notesURL.appendingPathComponent("\(newName).md")
            if text != original { try text.write(to: note.url, atomically: true, encoding: .utf8) }
            if newName != note.name { try fileManager.moveItem(at: note.url, to: destination) }
        }

        // 3. The metadata, written to the project root.
        var metadata = course.metadata
        metadata.kind = .project
        metadata.code = plan.code
        metadata.series = plan.series
        let renameMap = Dictionary(uniqueKeysWithValues: plan.recordingRenames)
        for index in metadata.lectures.indices {
            let number = metadata.lectures[index].number
            if let match = metadata.lectures[index].title.firstMatch(of: /^(.+?)\s+[Mm]eeting\s+\d+$/) {
                let name = String(match.1).trimmingCharacters(in: .whitespaces)
                metadata.lectures[index].series = plan.series.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.name
            }
            if plan.titlesCleared.contains(number) { metadata.lectures[index].title = "" }
            for r in metadata.lectures[index].recordings.indices {
                if let new = renameMap[metadata.lectures[index].recordings[r].baseName] {
                    metadata.lectures[index].recordings[r].baseName = new
                }
            }
        }
        metadata.normalize()

        // 4. Move the course's folders up into the root, merging with folders already there.
        if !inPlace {
            let children = (try? fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
            for child in children {
                let name = child.lastPathComponent
                if name == ".DS_Store" || name == Course.metadataFileName || name == CourseKind.course.overviewFileName { continue }
                let target = root.appendingPathComponent(name)
                if isDirectory(child), isDirectory(target) {
                    try mergeFolder(child, into: target)
                } else {
                    let ext = child.pathExtension
                    let base = ext.isEmpty ? name : (name as NSString).deletingPathExtension
                    try fileManager.moveItem(at: child, to: uniqueURL(in: root, name: base, ext: ext))
                }
            }
        }
        try fileManager.createDirectory(at: root.appendingPathComponent(Course.meetingsFolderName), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: root.appendingPathComponent(Course.notesFolderName), withIntermediateDirectories: true)
        try writeMetadata(metadata, to: root.appendingPathComponent(Course.metadataFileName))
        try? fileManager.removeItem(at: root.appendingPathComponent(CourseKind.course.overviewFileName))
        if !inPlace {
            try? fileManager.removeItem(at: source.appendingPathComponent(Course.metadataFileName))
            try? fileManager.removeItem(at: source.appendingPathComponent(CourseKind.course.overviewFileName))
            removeIfEmpty(source, unlessSameAs: root)
        }

        unregisterExternalCourse(source)
        if !isSameFolder(root.deletingLastPathComponent(), AppSettings.shared.rootFolderURL) {
            registerExternalCourse(root)
        }
        selectedCourseID = root.path
        reload()

        // 5. Rewrite transcripts that have timing data, so their headers say "meeting".
        if let project = self.course(id: root.path) {
            for lecture in project.lectures {
                for group in project.recordingGroups(for: lecture) where hasTimingData(courseID: project.id, baseName: group.baseName) {
                    for file in group.files {
                        if let format = TranscriptFormat(rawValue: file.fileExtension) {
                            _ = try? exportRecording(courseID: project.id, baseName: group.baseName, format: format)
                        }
                    }
                }
            }
        }
        return root.path
    }

    /// Moves everything in `source` into `target`, keeping both copies when names clash, then removes `source`.
    private func mergeFolder(_ source: URL, into target: URL) throws {
        let children = (try? fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        for child in children where child.lastPathComponent != ".DS_Store" {
            let destination = target.appendingPathComponent(child.lastPathComponent)
            if isDirectory(child), isDirectory(destination) {
                try mergeFolder(child, into: destination)
            } else if fileManager.fileExists(atPath: destination.path) {
                let ext = child.pathExtension
                try fileManager.moveItem(at: child, to: uniqueURL(in: target, name: child.deletingPathExtension().lastPathComponent, ext: ext))
            } else {
                try fileManager.moveItem(at: child, to: destination)
            }
        }
        removeIfEmpty(source, unlessSameAs: target)
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
