import SwiftUI
import AppKit

/// Lets other views insert text at the editor's cursor.
@MainActor
final class MarkdownEditorController {
    fileprivate weak var textView: NSTextView?

    var isAvailable: Bool { textView != nil }

    /// Inserts `snippet` at the cursor (replacing any selection), then moves the cursor back by `cursorBack`
    /// characters so it lands inside the brackets or dollar signs just inserted.
    func insert(_ snippet: String, cursorBack: Int = 0) {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
        textView.insertText(snippet, replacementRange: textView.selectedRange())
        if cursorBack > 0 {
            let location = max(0, textView.selectedRange().location - cursorBack)
            textView.setSelectedRange(NSRange(location: location, length: 0))
        }
    }
}

/// Plain-text Markdown editor with light syntax colouring. Smart quotes and dashes are off so
/// LaTeX and code are never rewritten while typing.
struct MarkdownEditorView: NSViewRepresentable {
    @Binding var text: String
    var controller: MarkdownEditorController?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }

        textView.delegate = context.coordinator
        controller?.textView = textView
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.font = Coordinator.baseFont
        textView.textColor = .labelColor
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 14, height: 14)
        textView.typingAttributes = Coordinator.baseAttributes

        textView.string = text
        context.coordinator.highlight(textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.parent = self
        if textView.string != text {
            let selection = textView.selectedRange()
            textView.string = text
            textView.setSelectedRange(NSRange(location: min(selection.location, (text as NSString).length), length: 0))
            context.coordinator.highlight(textView)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownEditorView

        static let baseFont = NSFont.monospacedSystemFont(ofSize: 13.5, weight: .regular)
        static var baseAttributes: [NSAttributedString.Key: Any] {
            let style = NSMutableParagraphStyle()
            style.lineSpacing = 3
            return [.font: baseFont, .foregroundColor: NSColor.labelColor, .paragraphStyle: style]
        }

        private static let rules: [(NSRegularExpression, [NSAttributedString.Key: Any])] = {
            func rule(_ pattern: String, _ options: NSRegularExpression.Options = [], _ attrs: [NSAttributedString.Key: Any]) -> (NSRegularExpression, [NSAttributedString.Key: Any]) {
                (try! NSRegularExpression(pattern: pattern, options: options), attrs)
            }
            let bold = NSFont.monospacedSystemFont(ofSize: 13.5, weight: .bold)
            return [
                rule("^#{1,6} .*$", .anchorsMatchLines, [.font: bold, .foregroundColor: NSColor.systemPurple]),
                rule("\\*\\*[^*\\n]+\\*\\*", [], [.font: bold]),
                rule("^>.*$", .anchorsMatchLines, [.foregroundColor: NSColor.secondaryLabelColor]),
                rule("`[^`\\n]+`", [], [.foregroundColor: NSColor.systemOrange]),
                rule("^```[\\s\\S]*?^```", .anchorsMatchLines, [.foregroundColor: NSColor.systemOrange]),
                rule("\\$\\$[\\s\\S]+?\\$\\$", [], [.foregroundColor: NSColor.systemTeal]),
                rule("(?<![\\\\$])\\$(?![\\s$])[^$\\n]+?(?<!\\s)\\$(?!\\d)", [], [.foregroundColor: NSColor.systemTeal]),
                rule("\\\\\\([\\s\\S]+?\\\\\\)|\\\\\\[[\\s\\S]+?\\\\\\]", [], [.foregroundColor: NSColor.systemTeal]),
                rule("\\[\\[[^\\[\\]\\n]+\\]\\]", [], [.foregroundColor: NSColor.systemBlue]),
                rule("^\\s*([-*+]|\\d+\\.)(?= )", .anchorsMatchLines, [.foregroundColor: NSColor.systemPink]),
            ]
        }()

        init(_ parent: MarkdownEditorView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            highlight(textView)
        }

        func highlight(_ textView: NSTextView) {
            guard let storage = textView.textStorage else { return }
            let full = NSRange(location: 0, length: storage.length)
            storage.beginEditing()
            storage.setAttributes(Self.baseAttributes, range: full)
            for (regex, attributes) in Self.rules {
                regex.enumerateMatches(in: storage.string, range: full) { match, _, _ in
                    guard let range = match?.range else { return }
                    storage.addAttributes(attributes, range: range)
                }
            }
            storage.endEditing()
        }
    }
}
