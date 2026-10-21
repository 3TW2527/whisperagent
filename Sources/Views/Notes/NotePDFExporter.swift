import AppKit
import WebKit

/// Renders a note with the same pipeline as the live preview and writes it to a paginated PDF.
///
/// The page is rendered once in an off-screen web view, cut into page-sized slices at block
/// boundaries (so paragraphs, tables and equations aren't split when they fit on a page), and each
/// slice is placed on a US Letter page.
@MainActor
enum NotePDFExporter {
    enum ExportError: LocalizedError {
        case previewMissing
        case writeFailed

        var errorDescription: String? {
            switch self {
            case .previewMissing: return "The preview resources are missing from the app bundle."
            case .writeFailed: return "The PDF could not be created."
            }
        }
    }

    private static let paperSize = CGSize(width: 612, height: 792)
    private static let margin: CGFloat = 54

    static func export(markdown: String, context: WikilinkContext, to destination: URL) async throws {
        guard MarkdownRenderer.previewFolderURL != nil else { throw ExportError.previewMissing }

        let contentWidth = paperSize.width - margin * 2
        let pageHeight = paperSize.height - margin * 2
        let renderer = MarkdownRenderer(frame: CGRect(x: 0, y: 0, width: contentWidth, height: pageHeight))

        let window = NSWindow(contentRect: CGRect(x: -10_000, y: -10_000, width: contentWidth, height: pageHeight),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = renderer.webView
        defer { window.close() }

        await renderer.renderAndWait(markdown: markdown, context: context, printMode: true)
        // Layout settles a moment after the DOM and fonts are ready.
        try? await Task.sleep(nanoseconds: 300_000_000)

        let breaks = try await pageBreaks(in: renderer.webView, pageHeight: pageHeight)

        var mediaBox = CGRect(origin: .zero, size: paperSize)
        guard let consumer = CGDataConsumer(url: destination as CFURL),
              let pdf = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { throw ExportError.writeFailed }

        for (start, end) in zip(breaks, breaks.dropFirst()) {
            let height = end - start
            let configuration = WKPDFConfiguration()
            configuration.rect = CGRect(x: 0, y: start, width: contentWidth, height: height)
            let data = try await renderer.webView.pdf(configuration: configuration)
            guard let provider = CGDataProvider(data: data as CFData),
                  let document = CGPDFDocument(provider),
                  let page = document.page(at: 1) else { throw ExportError.writeFailed }

            pdf.beginPDFPage(nil)
            pdf.saveGState()
            pdf.translateBy(x: margin, y: paperSize.height - margin - height)
            pdf.drawPDFPage(page)
            pdf.restoreGState()
            pdf.endPDFPage()
        }
        pdf.closePDF()
    }

    /// Y offsets (in page points) where each PDF page starts, ending with the content height.
    private static func pageBreaks(in webView: WKWebView, pageHeight: CGFloat) async throws -> [CGFloat] {
        let script = """
        const pageHeight = height;
        const top = window.scrollY;
        const blocks = Array.from(document.getElementById("content").children).map(el => {
          const r = el.getBoundingClientRect();
          return { top: r.top + top, bottom: r.bottom + top };
        });
        const total = Math.max(document.documentElement.scrollHeight, blocks.length ? blocks[blocks.length - 1].bottom : 0);
        const breaks = [0];
        let start = 0;
        while (total - start > pageHeight) {
          const limit = start + pageHeight;
          // The first block that crosses the limit moves to the next page if it fits on one.
          const crossing = blocks.find(b => b.top < limit && b.bottom > limit);
          let next = limit;
          if (crossing && crossing.top > start + 1 && crossing.bottom - crossing.top <= pageHeight) next = crossing.top;
          breaks.push(next);
          start = next;
        }
        breaks.push(total);
        return breaks;
        """
        let result = try await webView.callAsyncJavaScript(script, arguments: ["height": pageHeight], in: nil, contentWorld: .page)
        guard let values = result as? [Double], values.count >= 2 else { throw ExportError.writeFailed }
        return values.map { CGFloat($0) }
    }
}
