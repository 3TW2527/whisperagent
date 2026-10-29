import Foundation
import AppKit

/// Finds the files in the user's Canvas courses and downloads them, either into the materials folder of the
/// linked course or into Downloads.
///
/// Files come from three places, merged by Canvas file id: the course's Files list, its modules, and links in
/// its pages, assignments, discussions, announcements and syllabus. The last two find files when a lecturer
/// hides the Files tab. What was found is saved between launches, along with when each file was first seen
/// and which files were downloaded where.
@MainActor
public final class CanvasSyncService: ObservableObject {
    public static let shared = CanvasSyncService()

    private static let tokenAccount = "canvas-access-token"

    @Published public private(set) var courses: [CanvasCourse] = []
    @Published public private(set) var files: [CanvasFileRecord] = []
    /// Per-course notes, such as the Files tab being hidden.
    @Published public private(set) var notices: [Int: String] = [:]
    @Published public private(set) var downloads: [Int: CanvasDownload] = [:]
    @Published public private(set) var downloading: Set<Int> = []
    @Published public private(set) var isSyncing = false
    @Published public private(set) var lastSyncedAt: Date?
    @Published public private(set) var hasToken = false
    @Published public var errorMessage: String?

    private var snapshot = CanvasSnapshot()
    private var token: String?
    private var autoSyncTask: Task<Void, Never>?
    private let fileManager = FileManager.default

    private init() {
        token = KeychainStore.read(Self.tokenAccount)
        hasToken = !(token ?? "").isEmpty
        load()
    }

    public var isConfigured: Bool { client != nil }

    private var client: CanvasClient? {
        guard let base = CanvasClient.normalizedBaseURL(AppSettings.shared.canvasAddress), let token, !token.isEmpty else { return nil }
        return CanvasClient(baseURL: base, token: token)
    }

    public var visibleCourses: [CanvasCourse] {
        let hidden = Set(AppSettings.shared.canvasHiddenCourseIDs)
        return courses.filter { !hidden.contains($0.id) }
    }

    public var visibleFiles: [CanvasFileRecord] {
        let ids = Set(visibleCourses.map(\.id))
        return files.filter { ids.contains($0.courseID) }
    }

    public func course(id: Int) -> CanvasCourse? {
        courses.first { $0.id == id }
    }

    /// Files dated today that haven't been downloaded yet, or have an update waiting.
    public var newTodayCount: Int {
        visibleFiles.filter { file in
            guard !file.isUpcoming(), Calendar.current.isDateInToday(file.effectiveDate()) else { return false }
            switch downloadState(of: file) {
            case .notDownloaded, .updateAvailable: return true
            case .downloaded, .locked: return false
            }
        }.count
    }

    // MARK: - Connection

    /// Saves the site and token, checks them, and loads the course list. Returns the name of the signed-in user.
    /// An empty token keeps the one already saved.
    @discardableResult
    public func connect(address: String, token newToken: String) async throws -> String {
        guard let base = CanvasClient.normalizedBaseURL(address) else { throw CanvasError.invalidAddress }
        let trimmedToken = newToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = trimmedToken.isEmpty ? (token ?? "") : trimmedToken
        guard !candidate.isEmpty else { throw CanvasError.notConfigured }

        let client = CanvasClient(baseURL: base, token: candidate)
        let name = try await client.currentUserName()

        if !trimmedToken.isEmpty {
            KeychainStore.write(trimmedToken, for: Self.tokenAccount)
            token = trimmedToken
            hasToken = true
        }
        AppSettings.shared.canvasAddress = base.absoluteString
        if snapshot.address != base.absoluteString {
            snapshot = CanvasSnapshot(address: base.absoluteString)
            downloads = [:]
            saveDownloads()
            publish()
        }
        snapshot.courses = try await client.courses().sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        errorMessage = nil
        publish()
        save()
        return name
    }

    /// Forgets the token. Downloaded files stay where they are.
    public func disconnect() {
        KeychainStore.write("", for: Self.tokenAccount)
        token = nil
        hasToken = false
        autoSyncTask?.cancel()
    }

    // MARK: - Syncing

    /// Syncs now, then every `canvasSyncMinutes` while the app is open. Call again when that setting changes.
    public func startAutoSync() {
        autoSyncTask?.cancel()
        let minutes = AppSettings.shared.canvasSyncMinutes
        guard minutes > 0, isConfigured else { return }
        autoSyncTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.sync()
                try? await Task.sleep(for: .seconds(minutes * 60))
            }
        }
    }

    public func sync() async {
        guard !isSyncing else { return }
        guard let client else {
            errorMessage = CanvasError.notConfigured.errorDescription
            return
        }
        isSyncing = true
        defer { isSyncing = false }

        do {
            snapshot.courses = try await client.courses().sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        errorMessage = nil
        publish()

        let hidden = Set(AppSettings.shared.canvasHiddenCourseIDs)
        for course in snapshot.courses where !hidden.contains(course.id) {
            do {
                try await syncCourse(course.id, client: client)
            } catch {
                snapshot.notices[course.id] = "Couldn't sync this course: \(error.localizedDescription)"
            }
            publish()
        }

        // Courses the user is no longer enrolled in drop out.
        let enrolled = Set(snapshot.courses.map(\.id))
        snapshot.files.removeAll { !enrolled.contains($0.courseID) }
        removeDuplicates()
        snapshot.lastSyncedAt = Date()
        publish()
        save()
    }

    private func syncCourse(_ courseID: Int, client: CanvasClient) async throws {
        var found: [Int: CanvasFileRecord] = [:]
        var notice: String?

        // 1. The Files list. Students get an error here when the lecturer hides the Files tab.
        do {
            for file in try await client.files(courseID: courseID) {
                found[file.id] = Self.record(from: file, courseID: courseID, source: .files)
            }
        } catch let error as CanvasError where error.isAccessDenied {
            notice = "The Files tab is hidden in this course, so only files in modules or linked from course pages are listed."
        }

        // 2. Files in modules. A course without modules, or with them hidden, has none.
        var moduleItems: [Int: (moduleName: String, item: CanvasModuleItem, moduleUnlockAt: Date?)] = [:]
        for module in (try? await client.modules(courseID: courseID)) ?? [] {
            for item in module.items ?? [] where item.type == "File" {
                guard let id = item.contentId, moduleItems[id] == nil else { continue }
                moduleItems[id] = (module.name, item, module.unlockAt)
            }
        }

        // 3. Files linked from pages and other course content. Pages are only read again when they change.
        var linked = Set<Int>()
        var pageLinks = snapshot.pageLinks.filter { !$0.key.hasPrefix("\(courseID)/") }
        for page in (try? await client.pages(courseID: courseID)) ?? [] {
            let key = "\(courseID)/\(page.url)"
            if let cached = snapshot.pageLinks[key], cached.updatedAt == page.updatedAt {
                pageLinks[key] = cached
                linked.formUnion(cached.fileIDs)
                continue
            }
            guard let full = try? await client.page(courseID: courseID, url: page.url) else { continue }
            let ids = CanvasClient.linkedFileIDs(in: full.body ?? "")
            pageLinks[key] = CanvasSnapshot.PageLinks(updatedAt: page.updatedAt, fileIDs: ids.sorted())
            linked.formUnion(ids)
        }
        snapshot.pageLinks = pageLinks
        for item in await client.htmlItems(courseID: courseID) {
            linked.formUnion(CanvasClient.linkedFileIDs(in: item.html))
        }

        // Files linked here that belong to another synced course stay with that course.
        let elsewhere = Set(snapshot.files.filter { $0.courseID != courseID && $0.source != .link }.map(\.id))
        linked.subtract(elsewhere)

        // Look up the files the Files list didn't include.
        let missing = Set(moduleItems.keys).union(linked).subtracting(found.keys)
        for (id, file) in await lookUp(missing, client: client) {
            found[id] = Self.record(from: file, courseID: courseID, source: moduleItems[id] == nil ? .link : .module)
        }

        // Module details: the module's name, and its lock, which can apply even when the file itself isn't locked.
        for (id, info) in moduleItems {
            let details = info.item.contentDetails
            let unlockAt = details?.unlockAt ?? info.moduleUnlockAt
            if found[id] == nil {
                // Canvas wouldn't give the file's details, which usually means it's still locked.
                found[id] = CanvasFileRecord(
                    id: id, courseID: courseID, name: info.item.title,
                    unlockAt: unlockAt, isLocked: true,
                    lockExplanation: details?.lockExplanation, source: .module
                )
            }
            guard var record = found[id] else { continue }
            record.moduleName = info.moduleName
            if details?.lockedForUser == true {
                record.isLocked = true
                record.lockExplanation = details?.lockExplanation ?? record.lockExplanation
                if record.unlockAt == nil { record.unlockAt = unlockAt }
            }
            found[id] = record
        }

        // Keep first-seen dates. On a course's first sync, nothing counts as found.
        let isFirstSync = !snapshot.syncedCourseIDs.contains(courseID)
        let previous = Dictionary(snapshot.files.filter { $0.courseID == courseID }.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let now = Date()
        for id in found.keys {
            if let old = previous[id] {
                found[id]?.firstSeenAt = old.firstSeenAt
            } else {
                found[id]?.firstSeenAt = isFirstSync ? nil : now
            }
        }

        snapshot.files.removeAll { $0.courseID == courseID }
        snapshot.files += found.values
        snapshot.syncedCourseIDs.insert(courseID)
        snapshot.notices[courseID] = notice
    }

    /// A file linked from another course's pages is listed once, under the course it belongs to. A course synced
    /// earlier can't know that yet, so this runs after every course is done.
    private func removeDuplicates() {
        let preferred = snapshot.files.sorted { ($0.source == .link ? 1 : 0) < ($1.source == .link ? 1 : 0) }
        var seen = Set<Int>()
        let kept = Set(preferred.filter { seen.insert($0.id).inserted }.map { "\($0.courseID)/\($0.id)" })
        snapshot.files.removeAll { !kept.contains("\($0.courseID)/\($0.id)") }
    }

    /// Fetches each file's details, a few at a time. Files the user can't open are left out.
    private func lookUp(_ ids: Set<Int>, client: CanvasClient) async -> [Int: CanvasAPIFile] {
        await withTaskGroup(of: (Int, CanvasAPIFile?).self) { group in
            var pending = Array(ids).makeIterator()
            for _ in 0..<CanvasClient.maxConcurrentRequests {
                guard let id = pending.next() else { break }
                group.addTask { (id, try? await client.file(id: id)) }
            }
            var results: [Int: CanvasAPIFile] = [:]
            while let (id, file) = await group.next() {
                if let file { results[id] = file }
                if let next = pending.next() {
                    group.addTask { (next, try? await client.file(id: next)) }
                }
            }
            return results
        }
    }

    private static func record(from file: CanvasAPIFile, courseID: Int, source: CanvasFileSource) -> CanvasFileRecord {
        CanvasFileRecord(
            id: file.id,
            courseID: courseID,
            name: file.displayName,
            size: file.size,
            contentType: file.contentType,
            downloadURL: (file.url ?? "").isEmpty ? nil : file.url,
            createdAt: file.createdAt,
            modifiedAt: file.modifiedAt,
            unlockAt: file.unlockAt,
            isLocked: file.lockedForUser ?? false,
            lockExplanation: file.lockExplanation,
            source: source
        )
    }

    // MARK: - Downloads

    public func downloadState(of file: CanvasFileRecord) -> CanvasDownloadState {
        if let entry = downloads[file.id], fileManager.fileExists(atPath: entry.path) {
            let url = URL(fileURLWithPath: entry.path)
            if let modified = file.modifiedAt, let downloaded = entry.modifiedAt, modified > downloaded {
                return .updateAvailable(url)
            }
            return .downloaded(url)
        }
        return canDownload(file) ? .notDownloaded : .locked
    }

    public func canDownload(_ file: CanvasFileRecord) -> Bool {
        !file.isLocked && !file.isUpcoming() && file.downloadURL != nil
    }

    /// Where a course's files are saved: the linked course's materials folder, or Downloads.
    public func destinationName(forCourse canvasCourseID: Int) -> String {
        if let course = CourseStorageService.shared.course(linkedToCanvas: canvasCourseID) {
            return "\(course.name) materials"
        }
        return "Downloads"
    }

    /// Downloads the files one after another. A file downloaded before is replaced; the old copy goes to the Trash.
    public func download(_ ids: [Int]) async {
        guard let client else {
            errorMessage = CanvasError.notConfigured.errorDescription
            return
        }
        let queue = ids.filter { !downloading.contains($0) }
        downloading.formUnion(queue)
        var failures: [String] = []
        for id in queue {
            defer { downloading.remove(id) }
            guard let file = files.first(where: { $0.id == id }), canDownload(file),
                  let link = file.downloadURL, let url = URL(string: link) else { continue }
            do {
                let temporary = try await client.download(url)
                try place(temporary, for: file)
            } catch {
                failures.append("\(file.name): \(error.localizedDescription)")
            }
        }
        saveDownloads()
        errorMessage = failures.isEmpty ? nil : "Couldn't download " + failures.joined(separator: "; ")
    }

    private func place(_ temporary: URL, for file: CanvasFileRecord) throws {
        let name = Self.safeFileName(file.name)
        let staging = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }
        let named = staging.appendingPathComponent(name)
        try fileManager.moveItem(at: temporary, to: named)

        // The new copy takes the old one's name.
        if let old = downloads[file.id], fileManager.fileExists(atPath: old.path) {
            try? fileManager.trashItem(at: URL(fileURLWithPath: old.path), resultingItemURL: nil)
        }

        let destination: URL
        if let course = CourseStorageService.shared.course(linkedToCanvas: file.courseID) {
            destination = try CourseStorageService.shared.ingestMaterial(from: named, courseID: course.id, action: .move).url
        } else {
            let folder = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
            destination = uniqueURL(in: folder, fileName: name)
            try fileManager.moveItem(at: named, to: destination)
        }
        downloads[file.id] = CanvasDownload(path: destination.path, downloadedAt: Date(), modifiedAt: file.modifiedAt)
    }

    private func uniqueURL(in folder: URL, fileName: String) -> URL {
        let base = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        let suffix = ext.isEmpty ? "" : ".\(ext)"
        var candidate = folder.appendingPathComponent(fileName)
        var counter = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(base) (\(counter))\(suffix)")
            counter += 1
        }
        return candidate
    }

    private static func safeFileName(_ name: String) -> String {
        let cleaned = name.components(separatedBy: CharacterSet(charactersIn: "/:\\")).joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Canvas file" : cleaned
    }

    /// The file's page on Canvas.
    public func webURL(for file: CanvasFileRecord) -> URL? {
        CanvasClient.normalizedBaseURL(AppSettings.shared.canvasAddress)?
            .appendingPathComponent("courses/\(file.courseID)/files/\(file.id)")
    }

    // MARK: - Saving

    private var storageFolder: URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("WhisperLectures")
    }

    private var snapshotURL: URL { storageFolder.appendingPathComponent("canvas-snapshot.json") }
    private var downloadsURL: URL { storageFolder.appendingPathComponent("canvas-downloads.json") }

    private func publish() {
        courses = snapshot.courses
        files = snapshot.files
        notices = snapshot.notices
        lastSyncedAt = snapshot.lastSyncedAt
    }

    private func load() {
        let decoder = SegmentsDocument.decoder()
        if let data = try? Data(contentsOf: snapshotURL), let saved = try? decoder.decode(CanvasSnapshot.self, from: data) {
            snapshot = saved
        }
        if let data = try? Data(contentsOf: downloadsURL), let saved = try? decoder.decode([Int: CanvasDownload].self, from: data) {
            downloads = saved
        }
        publish()
    }

    private func save() {
        write(snapshot, to: snapshotURL)
    }

    private func saveDownloads() {
        write(downloads, to: downloadsURL)
    }

    private func write<T: Encodable>(_ value: T, to url: URL) {
        do {
            try fileManager.createDirectory(at: storageFolder, withIntermediateDirectories: true)
            try SegmentsDocument.encoder().encode(value).write(to: url, options: .atomic)
        } catch {
            print("Failed to save \(url.lastPathComponent): \(error)")
        }
    }
}

extension CanvasError {
    /// The student isn't allowed to see this part of the course.
    var isAccessDenied: Bool {
        switch self {
        case .unauthorized, .forbidden, .notFound: return true
        default: return false
        }
    }
}
