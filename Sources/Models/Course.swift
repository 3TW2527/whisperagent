import Foundation

/// Persisted metadata for a course, stored as `course.json` in the course folder.
public struct CourseMetadata: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var name: String
    public var code: String
    public var tags: [String]
    public var createdAt: Date
    public var lectures: [Lecture]

    public init(name: String, code: String = "", tags: [String] = [], createdAt: Date = Date(), lectures: [Lecture] = []) {
        self.schemaVersion = Self.currentSchemaVersion
        self.name = name
        self.code = code
        self.tags = tags
        self.createdAt = createdAt
        self.lectures = lectures
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? Self.currentSchemaVersion
        self.name = try c.decode(String.self, forKey: .name)
        self.code = try c.decodeIfPresent(String.self, forKey: .code) ?? ""
        self.tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        self.createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        self.lectures = try c.decodeIfPresent([Lecture].self, forKey: .lectures) ?? []
    }

    public var nextLectureNumber: Int {
        (lectures.map(\.number).max() ?? 0) + 1
    }
}

public struct Lecture: Codable, Hashable, Identifiable, Sendable {
    public var number: Int
    public var title: String
    public var date: Date
    public var recordings: [RecordingInfo]

    public var id: Int { number }

    public init(number: Int, title: String = "", date: Date = Date(), recordings: [RecordingInfo] = []) {
        self.number = number
        self.title = title
        self.date = date
        self.recordings = recordings
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.number = try c.decode(Int.self, forKey: .number)
        self.title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        self.date = try c.decodeIfPresent(Date.self, forKey: .date) ?? Date()
        self.recordings = try c.decodeIfPresent([RecordingInfo].self, forKey: .recordings) ?? []
    }

    public var label: String {
        String(format: "L%02d", number)
    }

    public var displayTitle: String {
        title.isEmpty ? "Lecture \(number)" : "Lecture \(number): \(title)"
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

/// A course loaded from disk: its metadata plus the files found in its folder.
public struct Course: Identifiable, Hashable, Sendable {
    public static let metadataFileName = "course.json"
    public static let overviewFileName = "COURSE.md"
    public static let materialsFolderName = "materials"
    public static let transcriptsFolderName = "transcripts"
    public static let notesFolderName = "notes"
    public static let internalFolderName = ".whisperlectures"

    public let folderURL: URL
    public var metadata: CourseMetadata
    public var materials: [LectureFile]
    public var transcripts: [TranscriptFile]
    public var notes: [NoteFile] = []
    /// True when the course lives outside the library folder.
    public var isExternal = false

    public var id: String { folderURL.path }
    public var name: String { metadata.name }
    public var tags: [String] { metadata.tags }
    public var lectures: [Lecture] { metadata.lectures.sorted { $0.number < $1.number } }

    public var metadataURL: URL { folderURL.appendingPathComponent(Self.metadataFileName) }
    public var materialsURL: URL { folderURL.appendingPathComponent(Self.materialsFolderName) }
    public var transcriptsURL: URL { folderURL.appendingPathComponent(Self.transcriptsFolderName) }
    public var notesURL: URL { folderURL.appendingPathComponent(Self.notesFolderName) }
    public var segmentsURL: URL { folderURL.appendingPathComponent(Self.internalFolderName).appendingPathComponent("segments") }

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
