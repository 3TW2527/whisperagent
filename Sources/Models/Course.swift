import Foundation

/// What a folder in the library holds. A course has lectures; a project has meetings, which can belong to
/// recurring series, plus key dates and folders of the user's own work.
public enum CourseKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case course
    case project

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .course: return "Course"
        case .project: return "Project"
        }
    }

    /// What one dated session is called.
    public var unitName: String {
        switch self {
        case .course: return "Lecture"
        case .project: return "Meeting"
        }
    }

    public var unitPlural: String { unitName + "s" }

    /// Prefix of session labels, transcript names and note names: `L03` for a lecture, `M03` for a meeting.
    public var unitLetter: String {
        switch self {
        case .course: return "L"
        case .project: return "M"
        }
    }

    /// The generated overview in the folder's root.
    public var overviewFileName: String {
        switch self {
        case .course: return "COURSE.md"
        case .project: return "PROJECT.md"
        }
    }

    public var systemImage: String {
        switch self {
        case .course: return "book.closed"
        case .project: return "folder.badge.person.crop"
        }
    }
}

/// A recurring kind of meeting in a project, e.g. the weekly Team Meeting on Mondays at 10:00.
public struct MeetingSeries: Codable, Hashable, Identifiable, Sendable {
    public var name: String
    /// `Calendar` weekday (1 = Sunday ... 7 = Saturday), or nil when the series has no fixed day.
    public var weekday: Int?
    /// Minutes after midnight the meeting usually starts, or nil when it has no fixed time.
    public var minuteOfDay: Int?

    public var id: String { name }

    public init(name: String, weekday: Int? = nil, minuteOfDay: Int? = nil) {
        self.name = name
        self.weekday = weekday
        self.minuteOfDay = minuteOfDay
    }

    public var hasSchedule: Bool { weekday != nil }

    /// The first usual slot on or after the start of `date`'s day, so on the meeting day itself it is that day's
    /// slot even once the meeting has started. Nil without a fixed weekday.
    public func nextOccurrence(from date: Date = Date(), calendar: Calendar = .current) -> Date? {
        guard let weekday else { return nil }
        let minutes = minuteOfDay ?? 9 * 60
        var components = DateComponents()
        components.weekday = weekday
        components.hour = minutes / 60
        components.minute = minutes % 60
        let startOfDay = calendar.startOfDay(for: date)
        return calendar.nextDate(after: startOfDay.addingTimeInterval(-1), matching: components, matchingPolicy: .nextTime)
    }

    /// `Mon 10:00`, `Mon`, or nil without a schedule. Day names follow the user's language.
    public var scheduleDescription: String? { scheduleDescription(locale: .current) }

    /// The schedule with English day names, for generated files.
    public var englishScheduleDescription: String? { scheduleDescription(locale: Locale(identifier: "en_US_POSIX")) }

    public func scheduleDescription(locale: Locale) -> String? {
        guard let weekday else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        let day = calendar.shortWeekdaySymbols[(weekday - 1) % 7]
        guard let minuteOfDay else { return day }
        return String(format: "%@ %02d:%02d", day, minuteOfDay / 60, minuteOfDay % 60)
    }

    /// `Team Meeting 2`, or `Team Meeting 2` too when the series is already called "Team Meeting".
    public static func meetingTitle(series: String, index: Int) -> String {
        series.lowercased().hasSuffix("meeting") ? "\(series) \(index)" : "\(series) Meeting \(index)"
    }
}

/// A deadline or milestone of a project, e.g. a final presentation.
public struct KeyDate: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var date: Date

    public init(id: UUID = UUID(), title: String, date: Date) {
        self.id = id
        self.title = title
        self.date = date
    }
}

/// Persisted metadata for a course or project, stored as `course.json` in its folder.
public struct CourseMetadata: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var kind: CourseKind
    public var name: String
    public var code: String
    public var tags: [String]
    public var createdAt: Date
    public var lectures: [Lecture]
    /// Canvas courses whose downloads go into this course's materials folder.
    public var canvasCourseIDs: [Int]
    /// Projects only: the recurring meeting series.
    public var series: [MeetingSeries]
    /// Projects only: deadlines and milestones.
    public var keyDates: [KeyDate]

    enum CodingKeys: String, CodingKey {
        case schemaVersion, kind, name, code, tags, createdAt, lectures, canvasCourseIDs, series, keyDates
    }

    public init(kind: CourseKind = .course, name: String, code: String = "", tags: [String] = [], createdAt: Date = Date(), lectures: [Lecture] = [], canvasCourseIDs: [Int] = [], series: [MeetingSeries] = [], keyDates: [KeyDate] = []) {
        self.schemaVersion = Self.currentSchemaVersion
        self.kind = kind
        self.name = name
        self.code = code
        self.tags = tags
        self.createdAt = createdAt
        self.lectures = lectures
        self.canvasCourseIDs = canvasCourseIDs
        self.series = series
        self.keyDates = keyDates
        normalize()
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? Self.currentSchemaVersion
        self.kind = try c.decodeIfPresent(CourseKind.self, forKey: .kind) ?? .course
        self.name = try c.decode(String.self, forKey: .name)
        self.code = try c.decodeIfPresent(String.self, forKey: .code) ?? ""
        self.tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        self.createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        self.lectures = try c.decodeIfPresent([Lecture].self, forKey: .lectures) ?? []
        self.canvasCourseIDs = try c.decodeIfPresent([Int].self, forKey: .canvasCourseIDs) ?? []
        self.series = try c.decodeIfPresent([MeetingSeries].self, forKey: .series) ?? []
        self.keyDates = try c.decodeIfPresent([KeyDate].self, forKey: .keyDates) ?? []
        normalize()
    }

    /// Courses keep the same `course.json` as before projects existed: project-only fields are left out.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        if kind != .course { try c.encode(kind, forKey: .kind) }
        try c.encode(name, forKey: .name)
        try c.encode(code, forKey: .code)
        try c.encode(tags, forKey: .tags)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(lectures, forKey: .lectures)
        try c.encode(canvasCourseIDs, forKey: .canvasCourseIDs)
        if kind == .project || !series.isEmpty { try c.encode(series, forKey: .series) }
        if kind == .project || !keyDates.isEmpty { try c.encode(keyDates, forKey: .keyDates) }
    }

    public var nextLectureNumber: Int {
        (lectures.map(\.number).max() ?? 0) + 1
    }

    /// Fills in each lecture's derived values: its kind (for labels) and its place within its series.
    public mutating func normalize() {
        var counters: [String: Int] = [:]
        let order = lectures.indices.sorted { a, b in
            (lectures[a].date, lectures[a].number) < (lectures[b].date, lectures[b].number)
        }
        for index in order {
            lectures[index].kind = kind
            if let series = lectures[index].series {
                let key = series.lowercased()
                counters[key, default: 0] += 1
                lectures[index].seriesIndex = counters[key]
            } else {
                lectures[index].seriesIndex = nil
            }
        }
    }
}

/// A lecture of a course, or a meeting of a project.
public struct Lecture: Codable, Hashable, Identifiable, Sendable {
    public var number: Int
    public var title: String
    public var date: Date
    public var recordings: [RecordingInfo]
    /// Projects only: the meeting series this meeting belongs to.
    public var series: String?

    /// Derived on load, not saved: whether this is a lecture or a meeting.
    public var kind: CourseKind = .course
    /// Derived on load, not saved: 2 for the second meeting of its series by date.
    public var seriesIndex: Int?

    public var id: Int { number }

    enum CodingKeys: String, CodingKey {
        case number, title, date, recordings, series
    }

    public init(number: Int, title: String = "", date: Date = Date(), recordings: [RecordingInfo] = [], series: String? = nil, kind: CourseKind = .course) {
        self.number = number
        self.title = title
        self.date = date
        self.recordings = recordings
        self.series = series
        self.kind = kind
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.number = try c.decode(Int.self, forKey: .number)
        self.title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        self.date = try c.decodeIfPresent(Date.self, forKey: .date) ?? Date()
        self.recordings = try c.decodeIfPresent([RecordingInfo].self, forKey: .recordings) ?? []
        let series = try c.decodeIfPresent(String.self, forKey: .series)?.trimmingCharacters(in: .whitespaces)
        self.series = series?.isEmpty == false ? series : nil
    }

    /// `L03` or `M03`.
    public var label: String {
        Self.label(number: number, kind: kind)
    }

    public static func label(number: Int, kind: CourseKind) -> String {
        String(format: "%@%02d", kind.unitLetter, number)
    }

    /// The title, else the series and its count (`Team Meeting 2`), else `Lecture 3` / `Meeting 3`.
    public var shortTitle: String {
        if !title.isEmpty { return title }
        if let seriesTitle { return seriesTitle }
        return "\(kind.unitName) \(number)"
    }

    /// `Team Meeting 2` for the second meeting of the Team series.
    public var seriesTitle: String? {
        guard let series, let seriesIndex else { return nil }
        return MeetingSeries.meetingTitle(series: series, index: seriesIndex)
    }

    public var displayTitle: String {
        let name = title.isEmpty ? seriesTitle : title
        return name.map { "\(kind.unitName) \(number): \($0)" } ?? "\(kind.unitName) \(number)"
    }
}

/// A transcribed recording that belongs to a lecture. Its files live in `transcripts/<baseName>.<ext>`.
public struct RecordingInfo: Codable, Hashable, Identifiable, Sendable {
    public var number: Int
    public var baseName: String
    public var sourceAudio: String
    public var model: String
    public var transcribedAt: Date
    public var durationSeconds: Double

    public var id: Int { number }

    public init(number: Int, baseName: String, sourceAudio: String, model: String, transcribedAt: Date = Date(), durationSeconds: Double) {
        self.number = number
        self.baseName = baseName
        self.sourceAudio = sourceAudio
        self.model = model
        self.transcribedAt = transcribedAt
        self.durationSeconds = durationSeconds
    }
}

/// A course or project loaded from disk: its metadata plus the files found in its folder.
///
/// A project's folder is its root: the app manages `materials/`, `meetings/`, `notes/` and `transcripts/`,
/// and every other folder in it is the user's own work, shown under Files.
public struct Course: Identifiable, Hashable, Sendable {
    public static let metadataFileName = "course.json"
    public static let materialsFolderName = "materials"
    public static let meetingsFolderName = "meetings"
    public static let transcriptsFolderName = "transcripts"
    public static let notesFolderName = "notes"
    public static let internalFolderName = ".whisperlectures"
    public static let actionsFileName = "ACTIONS.md"

    /// Names in a project's root that the app owns, so they aren't listed as the user's own files.
    public static let reservedRootNames: Set<String> = [
        metadataFileName, "COURSE.md", "PROJECT.md", actionsFileName, "INDEX.md", "AGENTS.md", "CLAUDE.md", "GEMINI.md",
        materialsFolderName, meetingsFolderName, transcriptsFolderName, notesFolderName, internalFolderName,
    ]

    public let folderURL: URL
    public var metadata: CourseMetadata
    public var materials: [LectureFile]
    public var transcripts: [TranscriptFile]
    public var notes: [NoteFile] = []
    /// Projects only: each meeting's own files from `meetings/M03/`, by meeting number.
    public var meetingFiles: [Int: [LectureFile]] = [:]
    /// Projects only: checkboxes in the notes, as read when the project was loaded.
    public var actions: [ActionItem] = []
    /// True when the course lives outside the library folder.
    public var isExternal = false

    public var id: String { folderURL.path }
    public var name: String { metadata.name }
    public var tags: [String] { metadata.tags }
    public var kind: CourseKind { metadata.kind }
    public var isProject: Bool { metadata.kind == .project }
    public var lectures: [Lecture] { metadata.lectures.sorted { $0.number < $1.number } }
    public var overviewFileName: String { kind.overviewFileName }

    public var metadataURL: URL { folderURL.appendingPathComponent(Self.metadataFileName) }
    public var materialsURL: URL { folderURL.appendingPathComponent(Self.materialsFolderName) }
    public var transcriptsURL: URL { folderURL.appendingPathComponent(Self.transcriptsFolderName) }
    public var notesURL: URL { folderURL.appendingPathComponent(Self.notesFolderName) }
    public var segmentsURL: URL { folderURL.appendingPathComponent(Self.internalFolderName).appendingPathComponent("segments") }
    public var meetingsURL: URL { folderURL.appendingPathComponent(Self.meetingsFolderName) }

    /// `meetings/M03/`: files that belong to one meeting rather than the whole project.
    public func meetingFolderURL(number: Int) -> URL {
        meetingsURL.appendingPathComponent(Lecture.label(number: number, kind: .project))
    }

    public func files(forMeeting number: Int) -> [LectureFile] {
        meetingFiles[number] ?? []
    }

    /// Notes that belong to a lecture or meeting (nil: notes for the whole course).
    public func notes(for lecture: Lecture?) -> [NoteFile] {
        notes.filter { $0.lectureNumber == lecture?.number }
    }

    /// Short identifier used as the prefix of transcript file names: the course code if set, otherwise the name.
    public var filePrefix: String {
        let source = metadata.code.trimmingCharacters(in: .whitespaces).isEmpty ? metadata.name : metadata.code
        return Self.slug(source)
    }

    public var displayName: String {
        metadata.code.isEmpty ? metadata.name : "\(metadata.code) · \(metadata.name)"
    }

    public func lecture(number: Int) -> Lecture? {
        metadata.lectures.first { $0.number == number }
    }

    /// Recordings for a lecture, grouping every transcript file that shares a base name.
    public func recordingGroups(for lecture: Lecture) -> [RecordingGroup] {
        var groups: [RecordingGroup] = []
        var claimed = Set<String>()
        for info in lecture.recordings.sorted(by: { $0.number < $1.number }) {
            let files = transcripts.filter { $0.baseName == info.baseName }
            groups.append(RecordingGroup(baseName: info.baseName, info: info, files: files))
            claimed.insert(info.baseName)
        }
        // Files that follow the naming scheme but aren't listed in course.json (e.g. added by hand).
        let pattern = "_\(lecture.label)_R"
        let orphans = Dictionary(grouping: transcripts.filter { !claimed.contains($0.baseName) && $0.baseName.contains(pattern) }, by: \.baseName)
        for (base, files) in orphans.sorted(by: { $0.key.localizedStandardCompare($1.key) == .orderedAscending }) {
            groups.append(RecordingGroup(baseName: base, info: nil, files: files))
        }
        return groups
    }

    /// Transcript files that can't be matched to any lecture.
    public var unassignedRecordingGroups: [RecordingGroup] {
        let assigned = Set(lectures.flatMap { recordingGroups(for: $0) }.map(\.baseName))
        let rest = Dictionary(grouping: transcripts.filter { !assigned.contains($0.baseName) }, by: \.baseName)
        return rest.sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
            .map { RecordingGroup(baseName: $0.key, info: nil, files: $0.value) }
    }

    public static func slug(_ text: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        let words = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        let joined = words.joined(separator: "-")
        let cleaned = String(joined.unicodeScalars.filter { allowed.contains($0) })
        return cleaned.isEmpty ? "Course" : cleaned
    }
}

/// All transcript files (md/txt/srt/vtt) that belong to one recording.
public struct RecordingGroup: Identifiable, Hashable, Sendable {
    public let baseName: String
    public let info: RecordingInfo?
    public let files: [TranscriptFile]

    public var id: String { baseName }

    /// The file best suited for reading: Markdown, then text, then subtitles.
    public var primaryFile: TranscriptFile? {
        let order = ["md", "txt", "vtt", "srt"]
        return files.min { (order.firstIndex(of: $0.fileExtension) ?? 99) < (order.firstIndex(of: $1.fileExtension) ?? 99) }
    }

    public func file(for format: TranscriptFormat) -> TranscriptFile? {
        files.first { $0.fileExtension == format.fileExtension }
    }
}
