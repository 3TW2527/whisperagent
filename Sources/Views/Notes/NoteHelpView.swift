import SwiftUI

/// Popover with a quick reference for the note editor and a picker that inserts `[[wikilinks]]`.
struct NoteHelpView: View {
    let context: WikilinkContext
    let canInsertAtCursor: Bool
    /// Inserts text at the cursor; `cursorBack` places the cursor inside the inserted brackets.
    let onInsert: (String, Int) -> Void

    @State private var search = ""

    private struct LinkOption: Identifiable {
        let id: String
        let label: String
        let icon: String
        let link: String
    }

    private var linkOptions: [LinkOption] {
        let notes = context.notes.map { LinkOption(id: "n-\($0)", label: $0, icon: "note.text", link: "[[\($0)]]") }
        let unit = context.unitName
        let lectures = context.lectures.map { lecture in
            let name = lecture.title.isEmpty ? lecture.seriesTitle : lecture.title
            return LinkOption(id: "l-\(lecture.number)", label: name.map { "\(unit) \(lecture.number): \($0)" } ?? "\(unit) \(lecture.number)", icon: "list.number", link: "[[\(unit) \(lecture.number)]]")
        }
        let files = context.files.map { LinkOption(id: "f-\($0)", label: $0, icon: "doc", link: "[[\($0)]]") }
        let all = notes + lectures + files
        return search.isEmpty ? all : all.filter { $0.label.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                linkPicker

                section("Markdown", rows: [
                    ("# Heading, ## Subheading", "# ", 0),
                    ("**bold**  and  *italic*", "**bold**", 0),
                    ("- bullet list", "- ", 0),
                    ("1. numbered list", "1. ", 0),
                    ("- [ ] checklist", "- [ ] ", 0),
                    ("> quote", "> ", 0),
                    ("`inline code`", "``", 1),
                    ("[text](https://...)", "[text](https://)", 1),
                    ("| a | b |  table", "| a | b |\n|---|---|\n| 1 | 2 |\n", 0),
                ])

                section("LaTeX math", rows: [
                    ("$x^2 + y^2$  inline", "$$", 1),
                    ("$$ ... $$  on its own lines", "$$\n\n$$", 3),
                    ("\\frac{a}{b}   fraction", "\\frac{}{}", 3),
                    ("\\sqrt{x}   root", "\\sqrt{}", 1),
                    ("x_i,  x^2   sub / superscript", "x_{i}", 0),
                    ("\\sum_{i=1}^{n}   sum", "\\sum_{i=1}^{n}", 0),
                    ("\\int_a^b f(x)\\,dx   integral", "\\int_a^b f(x)\\,dx", 0),
                    ("\\alpha \\beta \\pi   Greek letters", "\\alpha", 0),
                ], footnote: "A lone $ before a number, like $5, stays plain text.")

                VStack(alignment: .leading, spacing: 6) {
                    Text("Wikilinks")
                        .font(.headline)
                    Text("[[Note name]] links to another note, [[\(context.unitName) 3]] to a \(context.unitName.lowercased()), and [[file name]] to a document. Use [[Note|shown text]] to show different text. Click a link in the preview to open it. Links to something that doesn't exist yet are orange; clicking one creates that note.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("Notes save automatically as you type and are plain .md files in the course's notes folder.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
        }
        .frame(width: 380, height: 520)
    }

    // MARK: - Pieces

    private var linkPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Insert a wikilink")
                .font(.headline)
            TextField("Search notes, \(context.unitName.lowercased())s, documents", text: $search)
                .textFieldStyle(.roundedBorder)
            if !canInsertAtCursor {
                Text("Switch to Edit or Side by side to insert at the cursor. Links are added to the end of the note.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            let options = linkOptions
            if options.isEmpty {
                Text(search.isEmpty ? "Nothing to link to yet." : "No matches.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(options) { option in
                            Button {
                                onInsert(option.link, 0)
                            } label: {
                                Label(option.label, systemImage: option.icon)
                                    .font(.callout)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 4)
                                    .padding(.horizontal, 6)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 110)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            Button {
                onInsert("[[]]", 2)
            } label: {
                Label("Empty link [[ ]]", systemImage: "link")
            }
            .controlSize(.small)
        }
    }

    private func section(_ title: String, rows: [(String, String, Int)], footnote: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            Text("Click an example to insert it at the cursor.")
                .font(.caption2)
                .foregroundColor(.secondary)
            ForEach(rows.indices, id: \.self) { index in
                Button {
                    onInsert(rows[index].1, rows[index].2)
                } label: {
                    Text(rows[index].0)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 6)
                        .background(Color(NSColor.controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if let footnote {
                Text(footnote)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
}
