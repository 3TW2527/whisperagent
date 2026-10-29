import Foundation
import Network
import AppKit

/// One HTTP request read from the phone.
struct HTTPRequest: Sendable {
    var method: String
    var path: String
    var query: [String: String]
    /// Header names in lower case.
    var headers: [String: String]
    var body: Data
}

struct HTTPResponse: Sendable {
    var status: Int
    var contentType: String
    var body: Data

    static func text(_ text: String, status: Int = 200) -> HTTPResponse {
        HTTPResponse(status: status, contentType: "text/plain; charset=utf-8", body: Data(text.utf8))
    }

    static func html(_ html: String, status: Int = 200) -> HTTPResponse {
        HTTPResponse(status: status, contentType: "text/html; charset=utf-8", body: Data(html.utf8))
    }

    static func json(_ object: Any, status: Int = 200) -> HTTPResponse {
        let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8)
        return HTTPResponse(status: status, contentType: "application/json", body: data)
    }

    static func error(_ message: String, status: Int) -> HTTPResponse {
        json(["error": message], status: status)
    }

    var statusText: String {
        switch status {
        case 200: return "OK"
        case 400: return "Bad Request"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 409: return "Conflict"
        case 413: return "Payload Too Large"
        default: return "Error"
        }
    }
}

/// Reads one request from a connection, hands it to the server, writes the reply and closes the connection.
/// All of its state is used only on `queue`.
final class HTTPConnection: @unchecked Sendable {
    static let maxBodyBytes = 50 * 1024 * 1024
    static let maxHeaderBytes = 64 * 1024

    private let connection: NWConnection
    private let queue: DispatchQueue
    private let handler: @Sendable (HTTPRequest) async -> HTTPResponse
    private var buffer = Data()

    init(connection: NWConnection, queue: DispatchQueue, handler: @escaping @Sendable (HTTPRequest) async -> HTTPResponse) {
        self.connection = connection
        self.queue = queue
        self.handler = handler
    }

    func start() {
        connection.start(queue: queue)
        receive()
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [self] data, _, isComplete, error in
            if let data { buffer.append(data) }
            switch parse() {
            case .request(let request):
                Task {
                    let response = await handler(request)
                    queue.async { self.send(response) }
                }
            case .tooLarge:
                send(.error("That's too large to send.", status: 413))
            case .incomplete:
                if isComplete || error != nil {
                    connection.cancel()
                } else {
                    receive()
                }
            }
        }
    }

    private enum ParseResult {
        case request(HTTPRequest)
        case incomplete
        case tooLarge
    }

    private func parse() -> ParseResult {
        guard let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) else {
            return buffer.count > Self.maxHeaderBytes ? .tooLarge : .incomplete
        }
        let head = String(decoding: buffer[buffer.startIndex..<headerEnd.lowerBound], as: UTF8.self)
        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count >= 2 else { return .tooLarge }

        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = Int(headers["content-length"] ?? "0") ?? 0
        guard length <= Self.maxBodyBytes else { return .tooLarge }
        let bodyStart = headerEnd.upperBound
        guard buffer.count - bodyStart >= length else { return .incomplete }

        let target = URLComponents(string: String(requestLine[1]))
        var query: [String: String] = [:]
        for item in target?.queryItems ?? [] {
            query[item.name] = item.value ?? ""
        }
        return .request(HTTPRequest(
            method: String(requestLine[0]).uppercased(),
            path: target?.path ?? "/",
            query: query,
            headers: headers,
            body: Data(buffer[bodyStart..<(bodyStart + length)])
        ))
    }

    private func send(_ response: HTTPResponse) {
        var head = "HTTP/1.1 \(response.status) \(response.statusText)\r\n"
        head += "Content-Type: \(response.contentType)\r\n"
        head += "Content-Length: \(response.body.count)\r\n"
        head += "Cache-Control: no-store\r\n"
        head += "Connection: close\r\n\r\n"
        var data = Data(head.utf8)
        data.append(response.body)
        connection.send(content: data, completion: .contentProcessed { [connection] _ in
            connection.cancel()
        })
    }
}

/// An IPv4 address of this Mac that a phone on the same network can reach.
struct NetworkAddress: Hashable, Identifiable {
    let interface: String
    let ip: String

    var id: String { "\(interface)-\(ip)" }

    /// Every Wi-Fi, Ethernet, VPN and shared-network address, in the order they're most likely
    /// to be the one the phone can reach.
    static func current() -> [NetworkAddress] {
        var result: [NetworkAddress] = []
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return [] }
        defer { freeifaddrs(pointer) }
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(entry.pointee.ifa_flags)
            guard let address = entry.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                  flags & IFF_UP != 0, flags & IFF_RUNNING != 0, flags & IFF_LOOPBACK == 0 else { continue }
            let name = String(cString: entry.pointee.ifa_name)
            guard name.hasPrefix("en") || name.hasPrefix("bridge") || name.hasPrefix("utun") else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let ip = String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            guard !ip.hasPrefix("169.254.") else { continue }  // no DHCP lease, unreachable
            result.append(NetworkAddress(interface: name, ip: ip))
        }
        return result.sorted { ($0.rank, $0.interface) < ($1.rank, $1.interface) }
    }

    /// Wi-Fi, then VPNs (a phone on the same VPN can reach the Mac from any network), other Ethernet, then
    /// shared networks.
    private var rank: Int {
        if interface == "en0" { return 0 }
        if interface.hasPrefix("utun") { return 1 }
        if interface.hasPrefix("en") { return 2 }
        return 3
    }

    var interfaceDescription: String {
        if interface == "en0" { return "Wi-Fi" }
        if interface.hasPrefix("en") { return "Ethernet (\(interface))" }
        if interface.hasPrefix("utun") { return "VPN (\(interface))" }
        if interface.hasPrefix("bridge") { return "Shared network (\(interface))" }
        return interface
    }
}

/// A small web server, switched on from the Phone Notepad tool, that serves a notepad page to a phone on the
/// same network. The phone scans a QR code holding the Mac's address and a token that changes every time the
/// server starts. What the phone sends goes into a "phone" note of the chosen meeting or lecture, photos into
/// the meeting's folder, and actions can be ticked off.
@MainActor
final class PhoneNotepadServer: ObservableObject {
    static let shared = PhoneNotepadServer()
    static let preferredPorts: [UInt16] = Array(8765...8775)

    @Published private(set) var isRunning = false
    @Published private(set) var isStarting = false
    @Published private(set) var port: UInt16?
    @Published private(set) var token = ""
    @Published private(set) var addresses: [NetworkAddress] = []
    @Published var selectedAddressID: String?
    @Published private(set) var lastRequestAt: Date?
    /// Recent things the phone did, newest first, e.g. "14:23 Note added to M03".
    @Published private(set) var events: [String] = []
    @Published private(set) var errorMessage: String?

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "PhoneNotepadServer")
    private var sleepActivity: NSObjectProtocol?
    private var idleTimer: Timer?
    /// Entries already saved, so a phone retrying after a dropped connection doesn't add them twice.
    private var savedEntryIDs: [String] = []

    private var storage: CourseStorageService { .shared }

    var selectedAddress: NetworkAddress? {
        addresses.first { $0.id == selectedAddressID } ?? addresses.first
    }

    /// The address the QR code holds.
    var pageURL: URL? {
        guard let port, let address = selectedAddress else { return nil }
        return URL(string: "http://\(address.ip):\(port)/?t=\(token)")
    }

    // MARK: - Starting and Stopping

    func start() {
        guard !isRunning, !isStarting else { return }
        errorMessage = nil
        token = Self.makeToken()
        savedEntryIDs = []
        refreshAddresses()
        isStarting = true
        listen(onPortAt: 0)
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
        isStarting = false
        port = nil
        idleTimer?.invalidate()
        idleTimer = nil
        if let sleepActivity {
            ProcessInfo.processInfo.endActivity(sleepActivity)
            self.sleepActivity = nil
        }
    }

    func refreshAddresses() {
        addresses = NetworkAddress.current()
        if selectedAddress?.id != selectedAddressID {
            selectedAddressID = addresses.first?.id
        }
    }

    /// Tries the preferred ports in turn, so the page keeps its address (and its saved drafts) between sessions.
    private func listen(onPortAt index: Int) {
        guard index < Self.preferredPorts.count, let port = NWEndpoint.Port(rawValue: Self.preferredPorts[index]) else {
            isStarting = false
            errorMessage = "Couldn't start the server: ports \(Self.preferredPorts.first!)–\(Self.preferredPorts.last!) are all in use."
            return
        }
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        let listener: NWListener
        do {
            listener = try NWListener(using: parameters, on: port)
        } catch {
            listen(onPortAt: index + 1)
            return
        }
        let queue = self.queue
        listener.newConnectionHandler = { connection in
            HTTPConnection(connection: connection, queue: queue) { request in
                await PhoneNotepadServer.shared.handle(request)
            }.start()
        }
        listener.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                self?.listenerChanged(state, listener: listener, portIndex: index)
            }
        }
        self.listener = listener
        listener.start(queue: queue)
    }

    private func listenerChanged(_ state: NWListener.State, listener: NWListener, portIndex: Int) {
        guard listener === self.listener else { return }
        switch state {
        case .ready:
            isStarting = false
            isRunning = true
            port = listener.port?.rawValue
            lastRequestAt = Date()
            startIdleTimer()
            if AppSettings.shared.phoneNotepadKeepsMacAwake {
                sleepActivity = ProcessInfo.processInfo.beginActivity(options: [.idleSystemSleepDisabled], reason: "Phone notepad is on")
            }
        case .failed:
            listener.cancel()
            self.listener = nil
            if isRunning {
                stop()
                errorMessage = "The server stopped unexpectedly. Turn it on again."
            } else {
                listen(onPortAt: portIndex + 1)
            }
        default:
            break
        }
    }

    private func startIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            Task { @MainActor in PhoneNotepadServer.shared.stopIfIdle() }
        }
    }

    private func stopIfIdle() {
        let minutes = AppSettings.shared.phoneNotepadAutoOffMinutes
        guard isRunning, minutes > 0, let last = lastRequestAt, Date().timeIntervalSince(last) > Double(minutes) * 60 else { return }
        stop()
        log("Turned off after \(minutes) minutes without the phone")
    }

    private static func makeToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private func log(_ event: String) {
        let time = Date().formatted(date: .omitted, time: .shortened)
        events.insert("\(time)  \(event)", at: 0)
        if events.count > 30 { events.removeLast(events.count - 30) }
    }

    // MARK: - Requests

    func handle(_ request: HTTPRequest) -> HTTPResponse {
        let authorized = !token.isEmpty && (request.query["t"] == token || request.headers["x-token"] == token)
        if request.method == "GET" && (request.path == "/" || request.path == "/index.html") {
            return authorized ? .html(PhoneNotepadPage.html) : .html(PhoneNotepadPage.expiredHTML, status: 403)
        }
        guard authorized else { return .error("This link has expired. Scan the QR code in WhisperLectures again.", status: 403) }
        lastRequestAt = Date()

        switch (request.method, request.path) {
        case ("GET", "/api/state"): return stateResponse()
        case ("GET", "/api/note"): return noteResponse(request)
        case ("GET", "/api/actions"): return actionsResponse(request)
        case ("POST", "/api/entry"): return addEntry(request)
        case ("POST", "/api/meeting"): return addMeeting(request)
        case ("POST", "/api/photo"): return addPhoto(request)
        case ("POST", "/api/action"): return setAction(request)
        default: return .error("Not found", status: 404)
        }
    }

    /// Projects first, then courses; each with its newest meetings or lectures and the one happening now.
    private func stateResponse() -> HTTPResponse {
        let courses = storage.courses.filter(\.isProject) + storage.courses.filter { !$0.isProject }
        let now = Date()
        let iso = ISO8601DateFormatter()
        let list: [[String: Any]] = courses.map { course in
            let meetings = course.lectures.reversed().prefix(40).map { lecture -> [String: Any] in
                ["number": lecture.number, "label": lecture.label, "title": lecture.shortTitle, "date": iso.string(from: lecture.date), "series": lecture.series ?? ""]
            }
            var item: [String: Any] = [
                "id": course.id,
                "name": course.displayName,
                "isProject": course.isProject,
                "unit": course.kind.unitName,
                "series": course.metadata.series.map(\.name),
                "meetings": Array(meetings),
                "openActions": course.actions.filter { !$0.isDone }.count,
            ]
            if let current = Self.currentLecture(in: course, now: now) {
                item["current"] = current.number
            }
            return item
        }
        return .json(["courses": list, "mac": Host.current().localizedName ?? "Mac"])
    }

    /// The meeting happening about now: started up to 3 hours ago or starting within the hour, else today's latest.
    static func currentLecture(in course: Course, now: Date) -> Lecture? {
        let window = course.lectures.filter { $0.date > now.addingTimeInterval(-3 * 3600) && $0.date < now.addingTimeInterval(3600) }
        if let closest = window.min(by: { abs($0.date.timeIntervalSince(now)) < abs($1.date.timeIntervalSince(now)) }) {
            return closest
        }
        return course.lectures.filter { Calendar.current.isDate($0.date, inSameDayAs: now) }.max { $0.date < $1.date }
    }

    private func noteResponse(_ request: HTTPRequest) -> HTTPResponse {
        guard let found = lookup(request.query) else { return .error("That meeting no longer exists.", status: 404) }
        let (course, lecture) = found
        guard let note = try? phoneNote(course: course, lecture: lecture, create: false) else {
            return .json(["name": storage.noteTitle(for: lecture, date: lecture.date, suffix: "phone"), "content": ""])
        }
        let content = (try? String(contentsOf: note.url, encoding: .utf8)) ?? ""
        return .json(["name": note.name, "content": content])
    }

    private func actionsResponse(_ request: HTTPRequest) -> HTTPResponse {
        guard let id = request.query["course"], let course = storage.course(id: id) else { return .error("Not found", status: 404) }
        let items: [[String: Any]] = course.actions.filter { !$0.isDone }.reversed().map { item in
            var entry: [String: Any] = ["id": item.id, "text": item.text, "overdue": item.isOverdue()]
            if let number = item.meetingNumber { entry["meeting"] = Lecture.label(number: number, kind: course.kind) }
            if let due = item.due { entry["due"] = DateFormats.isoDay.string(from: due) }
            return entry
        }
        return .json(["actions": items])
    }

    /// Adds a timestamped line (or an action) to the meeting's phone note.
    private func addEntry(_ request: HTTPRequest) -> HTTPResponse {
        guard let body = Self.jsonBody(request), let text = (body["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return .error("Nothing to save.", status: 400)
        }
        let entryID = body["id"] as? String ?? UUID().uuidString
        if savedEntryIDs.contains(entryID) { return .json(["ok": true, "duplicate": true]) }
        guard let found = lookup(body) else { return .error("That meeting no longer exists.", status: 404) }
        let (course, lecture) = found

        let time = (body["time"] as? String).flatMap { ISO8601DateFormatter.withFractionalSeconds.date(from: $0) ?? ISO8601DateFormatter().date(from: $0) } ?? Date()
        let isAction = body["kind"] as? String == "action"
        let line: String
        if isAction {
            line = "- [ ] " + text.components(separatedBy: .newlines).filter { !$0.isEmpty }.joined(separator: " ")
        } else {
            let parts = text.components(separatedBy: "\n")
            line = (["- \(Self.clock(time)) \(parts[0])"] + parts.dropFirst().map { "  " + $0 }).joined(separator: "\n")
        }
        do {
            let note = try phoneNote(course: course, lecture: lecture, create: true)!
            try Self.append(line, to: note)
            savedEntryIDs.append(entryID)
            if savedEntryIDs.count > 1000 { savedEntryIDs.removeFirst(500) }
            storage.refresh(courseID: course.id)
            log("\(isAction ? "Action" : "Note") added to \(lecture.label)")
            return .json(["ok": true])
        } catch {
            return .error("Couldn't save: \(error.localizedDescription)", status: 500)
        }
    }

    private func addMeeting(_ request: HTTPRequest) -> HTTPResponse {
        guard let body = Self.jsonBody(request), let id = body["course"] as? String, let course = storage.course(id: id) else {
            return .error("Not found", status: 404)
        }
        let series = (body["series"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let title = body["title"] as? String ?? ""
        do {
            let lecture = try storage.addLecture(courseID: course.id, title: title, date: Date(), series: course.isProject ? series : nil)
            log("\(lecture.label) \(lecture.shortTitle) created")
            return .json(["ok": true, "number": lecture.number])
        } catch {
            return .error(error.localizedDescription, status: 500)
        }
    }

    /// Saves a photo into the meeting's folder (a course's materials) and links it from the phone note.
    private func addPhoto(_ request: HTTPRequest) -> HTTPResponse {
        guard !request.body.isEmpty else { return .error("No photo received.", status: 400) }
        guard let found = lookup(request.query) else { return .error("That meeting no longer exists.", status: 404) }
        let (course, lecture) = found
        let ext = Self.fileExtension(name: request.query["name"], contentType: request.headers["content-type"])
        let stamp = Self.photoStampFormatter.string(from: Date())
        do {
            let file = try storage.saveFile(request.body, named: "Photo \(stamp).\(ext)", courseID: course.id, meetingNumber: course.isProject ? lecture.number : nil)
            if let note = try phoneNote(course: course, lecture: lecture, create: true) {
                try Self.append("- \(Self.clock(Date())) Photo: [[\(file.name)]]", to: note)
            }
            storage.refresh(courseID: course.id)
            log("Photo added to \(lecture.label)")
            return .json(["ok": true, "name": file.name])
        } catch {
            return .error("Couldn't save the photo: \(error.localizedDescription)", status: 500)
        }
    }

    private func setAction(_ request: HTTPRequest) -> HTTPResponse {
        guard let body = Self.jsonBody(request), let courseID = body["course"] as? String, let actionID = body["id"] as? String else {
            return .error("Not found", status: 404)
        }
        storage.refresh(courseID: courseID)
        guard let course = storage.course(id: courseID), let item = course.actions.first(where: { $0.id == actionID }) else {
            return .error("That action changed on the Mac. Pull to refresh.", status: 409)
        }
        do {
            try storage.setAction(item, done: body["done"] as? Bool ?? true, courseID: courseID)
            log("Action ticked: \(item.text)")
            return .json(["ok": true])
        } catch {
            return .error("That action changed on the Mac. Refresh and try again.", status: 409)
        }
    }

    // MARK: - Helpers

    private func lookup(_ values: [String: Any]) -> (Course, Lecture)? {
        guard let id = values["course"] as? String, let course = storage.course(id: id) else { return nil }
        let number = (values["meeting"] as? Int) ?? (values["meeting"] as? String).flatMap(Int.init)
        guard let number, let lecture = course.lecture(number: number) else { return nil }
        return (course, lecture)
    }

    /// The meeting's note for what comes from the phone, e.g. `M03 Team Meeting 2 · 2026-03-12 · phone`.
    private func phoneNote(course: Course, lecture: Lecture, create: Bool) throws -> NoteFile? {
        if let existing = course.notes(for: lecture).first(where: { $0.name.hasSuffix(" · phone") }) {
            return existing
        }
        guard create else { return nil }
        let title = storage.noteTitle(for: lecture, date: lecture.date, suffix: "phone")
        return try storage.createNote(courseID: course.id, title: title)
    }

    private static func append(_ line: String, to note: NoteFile) throws {
        var text = (try? String(contentsOf: note.url, encoding: .utf8)) ?? ""
        if !text.isEmpty && !text.hasSuffix("\n") { text += "\n" }
        text += line + "\n"
        try text.write(to: note.url, atomically: true, encoding: .utf8)
    }

    private static func jsonBody(_ request: HTTPRequest) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any]
    }

    /// `2026-10-29 14.23.05`, for photo file names.
    private static let photoStampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return formatter
    }()

    /// `14:23` in the Mac's time zone.
    private static func clock(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    private static func fileExtension(name: String?, contentType: String?) -> String {
        let fromName = (name as NSString?)?.pathExtension.lowercased() ?? ""
        if !fromName.isEmpty, fromName.count <= 5 { return fromName }
        switch contentType?.lowercased() {
        case "image/png": return "png"
        case "image/heic": return "heic"
        case "image/heif": return "heif"
        case "image/gif": return "gif"
        case "image/webp": return "webp"
        default: return "jpg"
        }
    }
}

private extension ISO8601DateFormatter {
    /// Parses `2026-10-29T14:23:05.123Z`, as JavaScript's `toISOString()` writes it.
    static var withFractionalSeconds: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }
}
