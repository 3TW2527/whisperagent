import SwiftUI
import WebKit

/// What `[[wikilinks]]` in a note can point to.
struct WikilinkContext: Equatable {
    var notes: [String] = []
    var lectures: [LectureRef] = []
    var files: [String] = []

    struct LectureRef: Equatable {
        let number: Int
        let title: String
    }

    init(course: Course) {
        notes = course.notes.map(\.name)
        lectures = course.lectures.map { LectureRef(number: $0.number, title: $0.title) }
        files = course.materials.map(\.name) + course.transcripts.map(\.name)
    }

    /// Links between plain Markdown files, e.g. the files of one Markdown Library folder.
    init(notes: [String]) {
        self.notes = notes
    }

    var json: String {
        let object: [String: Any] = [
            "notes": notes,
            "lectures": lectures.map { ["number": $0.number, "title": $0.title] },
            "files": files,
        ]
        return Self.jsonString(object)
    }

    static func jsonString(_ object: Any) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8) else { return "null" }
        return text
    }
}

enum WikilinkTarget {
    case note(String)
    case lecture(Int)
    case file(String)
    case missing(String)

    init?(kind: String, value: String) {
        switch kind {
        case "note": self = .note(value)
        case "lecture": guard let number = Int(value) else { return nil }; self = .lecture(number)
        case "file": self = .file(value)
        case "missing": self = .missing(value)
        default: return nil
        }
    }
}

/// Owns a `WKWebView` that renders Markdown (with LaTeX and wikilinks) using the bundled `note.html`.
@MainActor
final class MarkdownRenderer: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    let webView: WKWebView
    var onWikilink: ((WikilinkTarget) -> Void)?

    private var isLoaded = false
    private var pending: [() -> Void] = []
    private var lastMarkdown: String?
    private var lastContext: String?

    static var previewFolderURL: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("Preview")
            ?? Bundle.main.url(forResource: "note", withExtension: "html")?.deletingLastPathComponent()
    }

    init(frame: CGRect = .zero) {
        let configuration = WKWebViewConfiguration()
        let controller = WKUserContentController()
        configuration.userContentController = controller
        webView = WKWebView(frame: frame, configuration: configuration)
        super.init()
        controller.add(WeakScriptHandler(self), name: "wikilink")
        webView.navigationDelegate = self
        load()
    }

    private func load() {
        guard let folder = Self.previewFolderURL else { return }
        let page = folder.appendingPathComponent("note.html")
        webView.loadFileURL(page, allowingReadAccessTo: folder)
    }

    func render(markdown: String, context: WikilinkContext) {
        let contextJSON = context.json
        guard markdown != lastMarkdown || contextJSON != lastContext else { return }
        lastMarkdown = markdown
        lastContext = contextJSON
        let markdownLiteral = WikilinkContext.jsonString([markdown]).dropFirst().dropLast()
        run { [webView] in
            webView.evaluateJavaScript("setContext(\(contextJSON)); renderNote(\(markdownLiteral));", completionHandler: nil)
        }
    }

    /// Renders and waits until math fonts are ready. Used before exporting.
    func renderAndWait(markdown: String, context: WikilinkContext, printMode: Bool) async {
        lastMarkdown = markdown
        lastContext = context.json
        let markdownLiteral = WikilinkContext.jsonString([markdown]).dropFirst().dropLast()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            run { [webView] in
                let script = "setPrintMode(\(printMode)); setContext(\(context.json)); renderNote(\(markdownLiteral));"
                webView.callAsyncJavaScript(script, arguments: [:], in: nil, in: .page) { _ in
                    continuation.resume()
                }
            }
        }
    }

    private func run(_ work: @escaping () -> Void) {
        if isLoaded { work() } else { pending.append(work) }
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoaded = true
        let queued = pending
        pending = []
        queued.forEach { $0() }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url else { return .allow }
        if url.scheme == "http" || url.scheme == "https" || url.scheme == "mailto" {
            NSWorkspace.shared.open(url)
        }
        return .cancel
    }

    // MARK: WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let kind = body["kind"] as? String,
              let value = body["value"] as? String,
              let target = WikilinkTarget(kind: kind, value: value) else { return }
        onWikilink?(target)
    }
}

/// `WKUserContentController` retains its handlers; this avoids a retain cycle with the renderer.
private final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?

    init(_ target: WKScriptMessageHandler) {
        self.target = target
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}

/// Live-rendered Markdown. Re-renders whenever `markdown` or the link context changes.
struct MarkdownPreviewView: NSViewRepresentable {
    let markdown: String
    let context: WikilinkContext
    let onWikilink: (WikilinkTarget) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var renderer: MarkdownRenderer?
    }

    func makeNSView(context ctx: Context) -> WKWebView {
        let renderer = MarkdownRenderer()
        ctx.coordinator.renderer = renderer
        renderer.onWikilink = onWikilink
        renderer.render(markdown: markdown, context: context)
        return renderer.webView
    }

    func updateNSView(_ nsView: WKWebView, context ctx: Context) {
        guard let renderer = ctx.coordinator.renderer else { return }
        renderer.onWikilink = onWikilink
        renderer.render(markdown: markdown, context: context)
    }
}
