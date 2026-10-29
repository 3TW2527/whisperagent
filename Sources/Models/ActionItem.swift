import Foundation

/// A to-do taken from a Markdown checkbox in a project note: `- [ ] Draft the report due:2026-11-05`.
/// The note is the record; ticking an action rewrites its checkbox there.
public struct ActionItem: Identifiable, Hashable, Sendable {
    public let noteURL: URL
    public let noteName: String
    /// Zero-based line in the note, and that line as read, so a toggle can check it hasn't moved.
    public let lineIndex: Int
    public let line: String
    /// The action without its checkbox and due date.
    public let text: String
    public let isDone: Bool
    public let due: Date?
    /// The meeting whose note this is, or nil for a project-wide note.
    public let meetingNumber: Int?

    public var id: String { "\(noteURL.path)#\(lineIndex)" }

    public func isOverdue(now: Date = Date()) -> Bool {
        guard let due, !isDone else { return false }
        return due < Calendar.current.startOfDay(for: now)
    }
}

public enum ActionScanner {
    // Computed: a stored Regex isn't Sendable.
    static var checkbox: Regex<(Substring, Substring, Substring, Substring)> { /^(\s*[-*+]\s+)\[([ xX])\]\s+(.*)$/ }
    static var dueToken: Regex<(Substring, Substring)> { /\s*due:(\d{4}-\d{2}-\d{2})\b/ }

    /// Every action in the course's notes, in note order.
    public static func scan(_ notes: [NoteFile]) -> [ActionItem] {
        notes.flatMap { note in
            parse((try? String(contentsOf: note.url, encoding: .utf8)) ?? "", note: note)
        }
    }

    public static func parse(_ text: String, note: NoteFile) -> [ActionItem] {
        var items: [ActionItem] = []
        var inCodeBlock = false
        for (index, line) in text.components(separatedBy: "\n").enumerated() {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                inCodeBlock.toggle()
                continue
            }
            guard !inCodeBlock, let match = line.firstMatch(of: checkbox) else { continue }
            var body = String(match.3)
            var due: Date?
            if let token = body.firstMatch(of: dueToken) {
                due = DateFormats.isoDay.date(from: String(token.1))
                body.removeSubrange(token.range)
            }
            body = body.trimmingCharacters(in: .whitespaces)
            guard !body.isEmpty else { continue }  // the empty "- [ ] " a new meeting note starts with
            items.append(ActionItem(
                noteURL: note.url,
                noteName: note.name,
                lineIndex: index,
                line: line,
                text: body,
                isDone: match.2 != " ",
                due: due,
                meetingNumber: note.lectureNumber
            ))
        }
        return items
    }

    /// Ticks or unticks an action in its note. Finds the line again if the note changed since it was read.
    public static func setDone(_ item: ActionItem, _ done: Bool) throws {
        let text = try String(contentsOf: item.noteURL, encoding: .utf8)
        var lines = text.components(separatedBy: "\n")
        let index: Int
        if item.lineIndex < lines.count, lines[item.lineIndex] == item.line {
            index = item.lineIndex
        } else if let found = lines.firstIndex(of: item.line) {
            index = found
        } else {
            throw CocoaError(.fileReadCorruptFile)
        }
        guard let match = lines[index].firstMatch(of: checkbox) else { return }
        lines[index] = "\(match.1)[\(done ? "x" : " ")] \(match.3)"
        try lines.joined(separator: "\n").write(to: item.noteURL, atomically: true, encoding: .utf8)
    }
}
