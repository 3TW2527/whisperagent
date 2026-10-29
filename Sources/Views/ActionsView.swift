import SwiftUI

/// A project's actions from every note, grouped by meeting, newest first. Ticking one updates its note.
struct ActionsView: View {
    let course: Course
    @ObservedObject var nav: CourseNavigation

    enum Filter: String, CaseIterable, Identifiable {
        case open = "Open"
        case done = "Done"
        case all = "All"

        var id: String { rawValue }
    }

    @AppStorage("whisperlectures_actions_filter") private var filter: Filter = .open
    @State private var errorMessage: String?

    private var shown: [ActionItem] {
        switch filter {
        case .open: return course.actions.filter { !$0.isDone }
        case .done: return course.actions.filter(\.isDone)
        case .all: return course.actions
        }
    }

    /// Meetings newest first, then the project-wide notes.
    private var groups: [(meeting: Lecture?, items: [ActionItem])] {
        let byMeeting = Dictionary(grouping: shown, by: \.meetingNumber)
        var result: [(Lecture?, [ActionItem])] = course.lectures.reversed().compactMap { lecture in
            byMeeting[lecture.number].map { (lecture, $0) }
        }
        // Notes whose meeting was deleted, and notes for the whole project.
        let known = Set(course.lectures.map(\.number))
        let rest = shown.filter { $0.meetingNumber.map { !known.contains($0) } ?? true }
        if !rest.isEmpty { result.append((nil, rest)) }
        return result
    }

    private var openCount: Int { course.actions.filter { !$0.isDone }.count }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Actions")
                        .font(.headline)
                    Text("\(openCount) open · from `- [ ]` checkboxes in your notes. Add `due:2026-11-05` for a due date.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Picker("Show", selection: $filter) {
                    ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 180)
                Button {
                    CourseStorageService.shared.openFile(url: course.folderURL.appendingPathComponent(Course.actionsFileName))
                } label: {
                    Image(systemName: "doc.text")
                }
                .buttonStyle(.borderless)
                .help("Open ACTIONS.md, the list AI assistants read")
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(Color(NSColor.controlBackgroundColor))

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(8)
            }
            Divider()

            if shown.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: filter == .done ? "checkmark.circle" : "checklist")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary.opacity(0.6))
                    Text(filter == .done ? "Nothing done yet" : (filter == .open ? "No open actions" : "No actions yet"))
                        .font(.headline)
                    Text("Write `- [ ] what to do` in a meeting's note (or from the phone notepad) and it shows up here.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(groups, id: \.meeting?.number) { group in
                        Section {
                            ForEach(group.items) { item in
                                ActionRow(item: item, onToggle: { toggle(item) }, onOpen: { open(item) })
                            }
                        } header: {
                            if let meeting = group.meeting {
                                HStack(spacing: 6) {
                                    Text(meeting.label)
                                        .font(.system(.caption, design: .monospaced).bold())
                                        .foregroundColor(.accentColor)
                                    Text(meeting.shortTitle)
                                    Text(DateFormats.isoDay.string(from: meeting.date))
                                        .foregroundColor(.secondary)
                                }
                            } else {
                                Text("Project notes")
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private func toggle(_ item: ActionItem) {
        do {
            try CourseStorageService.shared.setAction(item, done: !item.isDone, courseID: course.id)
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't update \(item.noteName). It may have changed; try again."
            CourseStorageService.shared.refresh(courseID: course.id)
        }
    }

    private func open(_ item: ActionItem) {
        guard let number = item.meetingNumber, course.lecture(number: number) != nil else {
            CourseStorageService.shared.openFile(url: item.noteURL)
            return
        }
        nav.lectureSelection = .lecture(number)
        nav.barItem = .note(item.noteURL.path)
    }
}

private struct ActionRow: View {
    let item: ActionItem
    let onToggle: () -> Void
    let onOpen: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Button(action: onToggle) {
                Image(systemName: item.isDone ? "checkmark.square.fill" : "square")
                    .foregroundColor(item.isDone ? .green : .secondary)
                    .font(.body)
            }
            .buttonStyle(.plain)
            .help(item.isDone ? "Mark as not done" : "Mark as done")

            Text(item.text)
                .strikethrough(item.isDone)
                .foregroundColor(item.isDone ? .secondary : .primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let due = item.due {
                Label(DateFormats.isoDay.string(from: due), systemImage: "calendar")
                    .font(.caption)
                    .foregroundColor(item.isOverdue() ? .red : .secondary)
                    .help(item.isOverdue() ? "Overdue" : "Due date")
            }

            Button(action: onOpen) {
                Image(systemName: "arrow.right.circle")
            }
            .buttonStyle(.borderless)
            .help("Open \(item.noteName)")
        }
        .padding(.vertical, 2)
    }
}
