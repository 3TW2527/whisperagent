import Foundation

public enum CanvasError: LocalizedError, Sendable {
    case notConfigured
    case invalidAddress
    case unauthorized
    case forbidden
    case notFound
    case http(Int)

    public var errorDescription: String? {
        switch self {
        case .notConfigured: return "Add your Canvas address and access token in this tool's settings."
        case .invalidAddress: return "The Canvas address isn't a valid web address."
        case .unauthorized: return "Canvas didn't accept the access token. Check it in this tool's settings."
        case .forbidden: return "Canvas says you don't have access to this."
        case .notFound: return "Canvas couldn't find this."
        case .http(let status): return "Canvas returned an error (HTTP \(status))."
        }
    }
}

/// Talks to the Canvas REST API as the student who owns the access token.
struct CanvasClient: Sendable {
    let baseURL: URL
    let token: String

    /// How many requests run at once when looking up files one by one.
    static let maxConcurrentRequests = 4

    init(baseURL: URL, token: String) {
        self.baseURL = baseURL
        self.token = token
    }

    /// Turns what the user typed (`school.instructure.com`, a pasted course link, ...) into `https://host`.
    static func normalizedBaseURL(_ text: String) -> URL? {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if !trimmed.contains("://") { trimmed = "https://" + trimmed }
        guard let components = URLComponents(string: trimmed), let host = components.host, host.contains(".") else { return nil }
        var base = URLComponents()
        base.scheme = components.scheme == "http" ? "http" : "https"
        base.host = host
        base.port = components.port
        return base.url
    }

    // MARK: - Endpoints

    func currentUserName() async throws -> String {
        struct User: Decodable { let name: String }
        return try await get(User.self, "users/self").name
    }

    func courses() async throws -> [CanvasCourse] {
        try await getAll(CanvasCourse.self, "courses", query: [URLQueryItem(name: "enrollment_state", value: "active")])
    }

    /// Every file in the course's Files area. Throws `forbidden` or `unauthorized` when the Files tab is hidden from students.
    func files(courseID: Int) async throws -> [CanvasAPIFile] {
        try await getAll(CanvasAPIFile.self, "courses/\(courseID)/files")
    }

    func file(id: Int) async throws -> CanvasAPIFile {
        try await get(CanvasAPIFile.self, "files/\(id)")
    }

    func modules(courseID: Int) async throws -> [CanvasModule] {
        try await getAll(CanvasModule.self, "courses/\(courseID)/modules", query: [
            URLQueryItem(name: "include[]", value: "items"),
            URLQueryItem(name: "include[]", value: "content_details"),
        ])
    }

    func pages(courseID: Int) async throws -> [CanvasPage] {
        try await getAll(CanvasPage.self, "courses/\(courseID)/pages")
    }

    func page(courseID: Int, url: String) async throws -> CanvasPage {
        let slug = url.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? url
        return try await get(CanvasPage.self, "courses/\(courseID)/pages/\(slug)")
    }

    /// HTML from assignments, discussions, announcements and the syllabus. Sections the student can't open are skipped.
    func htmlItems(courseID: Int) async -> [CanvasHTMLItem] {
        var items: [CanvasHTMLItem] = []
        let lists: [(String, [URLQueryItem])] = [
            ("courses/\(courseID)/assignments", []),
            ("courses/\(courseID)/discussion_topics", []),
            ("courses/\(courseID)/discussion_topics", [URLQueryItem(name: "only_announcements", value: "true")]),
        ]
        for (path, query) in lists {
            items += (try? await getAll(CanvasHTMLItem.self, path, query: query)) ?? []
        }
        if let course = try? await get(CanvasHTMLItem.self, "courses/\(courseID)", query: [URLQueryItem(name: "include[]", value: "syllabus_body")]) {
            items.append(course)
        }
        return items
    }

    /// Ids of course files linked from HTML, e.g. `/courses/12/files/345/download` or `/api/v1/files/345`.
    static func linkedFileIDs(in html: String) -> Set<Int> {
        guard let regex = try? NSRegularExpression(pattern: #"/files/(\d+)"#) else { return [] }
        let range = NSRange(html.startIndex..., in: html)
        var ids = Set<Int>()
        for match in regex.matches(in: html, range: range) {
            if let idRange = Range(match.range(at: 1), in: html), let id = Int(html[idRange]) {
                ids.insert(id)
            }
        }
        return ids
    }

    // MARK: - Downloads

    /// Downloads a file to a temporary location. The caller moves it into place.
    func download(_ url: URL) async throws -> URL {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (location, response) = try await URLSession.shared.download(for: request, delegate: RedirectAuthStripper())
        try Self.check(response)
        let kept = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.moveItem(at: location, to: kept)
        return kept
    }

    // MARK: - Requests

    private func get<T: Decodable>(_ type: T.Type, _ path: String, query: [URLQueryItem] = []) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request(endpoint(path, query: query)))
        try Self.check(response)
        return try Self.decoder.decode(T.self, from: data)
    }

    /// Follows Canvas's `Link: <...>; rel="next"` headers until every page is read.
    private func getAll<T: Decodable>(_ type: T.Type, _ path: String, query: [URLQueryItem] = []) async throws -> [T] {
        var results: [T] = []
        var next: URL? = endpoint(path, query: query + [URLQueryItem(name: "per_page", value: "100")])
        while let url = next {
            let (data, response) = try await URLSession.shared.data(for: request(url))
            try Self.check(response)
            results += try Self.decoder.decode([T].self, from: data)
            next = (response as? HTTPURLResponse).flatMap(Self.nextPageURL)
        }
        return results
    }

    private func endpoint(_ path: String, query: [URLQueryItem]) -> URL {
        var components = URLComponents(url: baseURL.appendingPathComponent("api/v1/" + path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        return components.url!
    }

    private func request(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private static func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        switch http.statusCode {
        case 200..<300: return
        case 401: throw CanvasError.unauthorized
        case 403: throw CanvasError.forbidden
        case 404: throw CanvasError.notFound
        default: throw CanvasError.http(http.statusCode)
        }
    }

    private static func nextPageURL(_ response: HTTPURLResponse) -> URL? {
        guard let header = response.value(forHTTPHeaderField: "Link") else { return nil }
        for part in header.components(separatedBy: ",") where part.contains("rel=\"next\"") {
            guard let start = part.firstIndex(of: "<"), let end = part.firstIndex(of: ">"), start < end else { continue }
            return URL(string: String(part[part.index(after: start)..<end]))
        }
        return nil
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            if let date = formatter.date(from: text) { return date }
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: text) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown date \(text)"))
        }
        return decoder
    }()
}

/// File downloads redirect to a signed storage URL on another host. The token must not be sent there.
private final class RedirectAuthStripper: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        var request = request
        if request.url?.host != task.originalRequest?.url?.host {
            request.setValue(nil, forHTTPHeaderField: "Authorization")
        }
        return request
    }
}
