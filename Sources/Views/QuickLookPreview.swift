import SwiftUI
import QuickLookUI
import PDFKit

public struct QuickLookPreviewView: NSViewRepresentable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func makeNSView(context: Context) -> QLPreviewView {
        let previewView = QLPreviewView(frame: .zero, style: .normal) ?? QLPreviewView()
        previewView.previewItem = fileURL as QLPreviewItem
        return previewView
    }

    public func updateNSView(_ nsView: QLPreviewView, context: Context) {
        nsView.previewItem = fileURL as QLPreviewItem
        nsView.refreshPreviewItem()
    }
}

public struct QuickLookModal: View {
    public let fileURL: URL
    public var onDismiss: () -> Void

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(fileURL.lastPathComponent)
                    .font(.headline)

                Spacer()

                Button {
                    NSWorkspace.shared.open(fileURL)
                } label: {
                    Label("Open", systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Reveal in Finder")

                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            FileContentPreview(fileURL: fileURL)
                .frame(minWidth: 520, idealWidth: 720, minHeight: 360, idealHeight: 520)
        }
        // Allow pressing Space to toggle/close Quick Look, just like Finder
        .background(
            Button("") {
                onDismiss()
            }
            .keyboardShortcut(.space, modifiers: [])
            .opacity(0)
            .frame(width: 0, height: 0)
        )
    }
}

/// Shows a file's contents: PDFs in a viewer with page navigation, everything else through Quick Look.
public struct FileContentPreview: View {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public var body: some View {
        if fileURL.pathExtension.lowercased() == "pdf" {
            PDFPreviewView(fileURL: fileURL)
        } else {
            QuickLookPreviewView(fileURL: fileURL)
        }
    }
}

// MARK: - PDF

/// Owns the PDFKit views and tracks which page is showing, so the SwiftUI controls can follow and move it.
@MainActor
final class PDFNavigator: NSObject, ObservableObject {
    @Published private(set) var pageIndex = 0
    @Published private(set) var pageCount = 0

    let pdfView = PDFView()
    let thumbnailView = PDFThumbnailView()
    private var loadedURL: URL?

    override init() {
        super.init()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displaysPageBreaks = true
        thumbnailView.pdfView = pdfView
        thumbnailView.thumbnailSize = CGSize(width: 96, height: 124)
        thumbnailView.backgroundColor = .clear
        NotificationCenter.default.addObserver(self, selector: #selector(pageDidChange), name: .PDFViewPageChanged, object: pdfView)
    }

    func load(_ url: URL) {
        guard url != loadedURL else { return }
        loadedURL = url
        pdfView.document = PDFDocument(url: url)
        pdfView.autoScales = true
        syncPage()
    }

    @objc private func pageDidChange(_ note: Notification) {
        syncPage()
    }

    private func syncPage() {
        guard let document = pdfView.document else {
            pageCount = 0
            pageIndex = 0
            return
        }
        pageCount = document.pageCount
        if let page = pdfView.currentPage {
            pageIndex = document.index(for: page)
        }
    }

    var canGoBack: Bool { pageIndex > 0 }
    var canGoForward: Bool { pageIndex < pageCount - 1 }

    func go(toPage index: Int) {
        guard let document = pdfView.document, document.pageCount > 0 else { return }
        let clamped = min(max(index, 0), document.pageCount - 1)
        if let page = document.page(at: clamped) {
            pdfView.go(to: page)
        }
        syncPage()
    }

    func zoomIn() { pdfView.zoomIn(nil) }
    func zoomOut() { pdfView.zoomOut(nil) }
    func zoomToFit() { pdfView.autoScales = true }

    /// Hands keyboard focus to the page so the arrow, Page Up/Down, Home and End keys move through it.
    func focusPage() {
        pdfView.window?.makeFirstResponder(pdfView)
    }
}

/// A PDF with a page strip and controls to step through pages, jump to a page number and zoom.
struct PDFPreviewView: View {
    let fileURL: URL

    @StateObject private var navigator = PDFNavigator()
    @State private var pageText = "1"
    @AppStorage("pdfPreviewShowsThumbnails") private var showsThumbnails = true
    @FocusState private var isPageFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            HStack(spacing: 0) {
                if showsThumbnails && navigator.pageCount > 1 {
                    PlatformViewHost(view: navigator.thumbnailView)
                        .frame(width: 128)
                    Divider()
                }
                PlatformViewHost(view: navigator.pdfView)
            }
        }
        .onAppear { navigator.load(fileURL) }
        .onChange(of: fileURL) { navigator.load(fileURL) }
        .onChange(of: navigator.pageIndex) { syncPageText() }
        .onChange(of: navigator.pageCount) { syncPageText() }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Button {
                showsThumbnails.toggle()
            } label: {
                Image(systemName: "sidebar.left")
            }
            .help(showsThumbnails ? "Hide page thumbnails" : "Show page thumbnails")
            .disabled(navigator.pageCount <= 1)

            Spacer()

            Button {
                navigator.go(toPage: 0)
            } label: {
                Image(systemName: "chevron.left.2")
            }
            .help("First page")
            .disabled(!navigator.canGoBack)

            Button {
                navigator.go(toPage: navigator.pageIndex - 1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .help("Previous page")
            .disabled(!navigator.canGoBack)

            HStack(spacing: 4) {
                Text("Page")
                TextField("", text: $pageText)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.center)
                    .frame(width: 44)
                    .focused($isPageFieldFocused)
                    .onSubmit(jumpToTypedPage)
                Text("of \(navigator.pageCount)")
            }
            .font(.callout)
            .foregroundColor(.secondary)
            .help("Type a page number and press Return")

            Button {
                navigator.go(toPage: navigator.pageIndex + 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .help("Next page")
            .disabled(!navigator.canGoForward)

            Button {
                navigator.go(toPage: navigator.pageCount - 1)
            } label: {
                Image(systemName: "chevron.right.2")
            }
            .help("Last page")
            .disabled(!navigator.canGoForward)

            Spacer()

            Button { navigator.zoomOut() } label: { Image(systemName: "minus.magnifyingglass") }
                .help("Zoom out")
            Button { navigator.zoomToFit() } label: { Image(systemName: "arrow.up.left.and.down.right.magnifyingglass") }
                .help("Fit to width")
            Button { navigator.zoomIn() } label: { Image(systemName: "plus.magnifyingglass") }
                .help("Zoom in")
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func jumpToTypedPage() {
        if let number = Int(pageText.trimmingCharacters(in: .whitespaces)) {
            navigator.go(toPage: number - 1)
        }
        syncPageText()
        isPageFieldFocused = false
        navigator.focusPage()
    }

    private func syncPageText() {
        pageText = navigator.pageCount == 0 ? "0" : "\(navigator.pageIndex + 1)"
    }
}

/// Puts an AppKit view that something else owns into SwiftUI.
private struct PlatformViewHost: NSViewRepresentable {
    let view: NSView

    func makeNSView(context: Context) -> NSView { view }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
