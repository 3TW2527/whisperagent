import Foundation

// MARK: - Canvas API responses

/// A course the user is enrolled in, from `GET /api/v1/courses`.
public struct CanvasCourse: Codable, Identifiable, Hashable, Sendable {
    public let id: Int
    public let name: String
    public let courseCode: String?

    public var displayName: String {
        guard let code = courseCode, !code.isEmpty, code != name else { return name }
        return "\(code) · \(name)"
    }
}

/// A file as the Files API returns it. Only the fields the app uses are decoded.
struct CanvasAPIFile: Decodable, Sendable {
    let id: Int
    let displayName: String
    let size: Int?
    let contentType: String?
    let url: String?
    let createdAt: Date?
    let modifiedAt: Date?
    let unlockAt: Date?
    let lockedForUser: Bool?
    let lockExplanation: String?

    enum CodingKeys: String, CodingKey {
        case id, displayName, size, url, createdAt, modifiedAt, unlockAt, lockedForUser, lockExplanation
        case contentType = "content-type"
    }
}

struct CanvasModule: Decodable, Sendable {
    let id: Int
    let name: String
    let unlockAt: Date?
    let items: [CanvasModuleItem]?
}

struct CanvasModuleItem: Decodable, Sendable {
    let title: String
    let type: String
    let contentId: Int?
    let contentDetails: ContentDetails?

    struct ContentDetails: Decodable, Sendable {
        let lockedForUser: Bool?
        let lockExplanation: String?
        let unlockAt: Date?
    }
}

struct CanvasPage: Decodable, Sendable {
    let url: String
    let updatedAt: Date?
    let body: String?
}

/// Any item with HTML that may link to course files: assignments (`description`),
/// discussions and announcements (`message`), and the course itself (`syllabus_body`).
struct CanvasHTMLItem: Decodable, Sendable {
    let description: String?
    let message: String?
    let syllabusBody: String?

    var html: String { [description, message, syllabusBody].compactMap { $0 }.joined(separator: "\n") }
}

// MARK: - Stored state

/// Where a file was found. The Files list has everything visible; the others find files when that list is hidden.
public enum CanvasFileSource: String, Codable, Sendable {
    case files
    case module
    case link
}

/// Why a file sits on its date: whichever of its dates is the newest.
public enum CanvasFileReason: String, Sendable {
    case new = "New"
    case updated = "Updated"
    case released = "Released"
    case found = "Found"
    case upcoming = "Upcoming"
}

/// A Canvas file the app knows about, merged from every source and remembered between launches.
public struct CanvasFileRecord: Codable, Identifiable, Hashable, Sendable {
    /// The Canvas file id.
    public let id: Int
    public var courseID: Int
    public var name: String
    public var size: Int?
    public var contentType: String?
    public var downloadURL: String?
    public var createdAt: Date?
    public var modifiedAt: Date?
    public var unlockAt: Date?
    public var isLocked: Bool
    public var lockExplanation: String?
    public var source: CanvasFileSource
    public var moduleName: String?
    /// When the app first saw the file. Nil for files that were already there on the course's first sync,
    /// so connecting Canvas doesn't make every old file look new.
    public var firstSeenAt: Date?

    /// Edits within this long of the upload count as part of the upload, not as an update.
    static let updateGrace: TimeInterval = 120

    /// The newest of the file's dates, ignoring an unlock date that hasn't come yet.
    public func effectiveDate(now: Date = Date()) -> Date {
        if let unlockAt, unlockAt > now { return unlockAt }
        return dated(now: now).max { $0.date < $1.date }?.date ?? .distantPast
    }

    public func reason(now: Date = Date()) -> CanvasFileReason {
        if let unlockAt, unlockAt > now { return .upcoming }
        return dated(now: now).max { $0.date < $1.date }?.reason ?? .new
    }

    public func isUpcoming(now: Date = Date()) -> Bool {
        if let unlockAt { return unlockAt > now }
        return false
    }

    private func dated(now: Date) -> [(date: Date, reason: CanvasFileReason)] {
        var dates: [(date: Date, reason: CanvasFileReason)] = []
        if let createdAt { dates.append((createdAt, .new)) }
        if let modifiedAt, modifiedAt > (createdAt ?? .distantPast).addingTimeInterval(Self.updateGrace) {
            dates.append((modifiedAt, .updated))
        }
        if let unlockAt, unlockAt <= now { dates.append((unlockAt, .released)) }
        if let firstSeenAt { dates.append((firstSeenAt, .found)) }
        return dates
    }

    public var fileExtension: String {
        (name as NSString).pathExtension.lowercased()
    }

    public var formattedSize: String? {
        size.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) }
    }
}

/// A file the app downloaded: where it went and which version it was.
public struct CanvasDownload: Codable, Hashable, Sendable {
    public var path: String
    public var downloadedAt: Date
    /// The file's `modified_at` when it was downloaded. A newer one on Canvas means an update is available.
    public var modifiedAt: Date?
    /// True for a file of the same name found in the materials folder with a different size, so it's
    /// probably an older version. Downloading replaces it.
    public var isOutdated: Bool?
}

public enum CanvasDownloadState: Equatable, Sendable {
    case notDownloaded
    case downloaded(URL)
    case updateAvailable(URL)
    case locked
}

/// The last sync, saved so the tool opens instantly and remembers when each file was first seen.
struct CanvasSnapshot: Codable, Sendable {
    /// The Canvas site this was synced from. Connecting to another site starts afresh.
    var address: String?
    var courses: [CanvasCourse] = []
    var files: [CanvasFileRecord] = []
    /// Canvas courses synced at least once. Files found in a course after its first sync are marked as found.
    var syncedCourseIDs: Set<Int> = []
    /// Files linked from each page, keyed `courseID/page-url`, so unchanged pages aren't downloaded again.
    var pageLinks: [String: PageLinks] = [:]
    var notices: [Int: String] = [:]
    var lastSyncedAt: Date?

    struct PageLinks: Codable, Sendable {
        var updatedAt: Date?
        var fileIDs: [Int]
    }
}
