import SwiftUI

public enum LectureSelection: Hashable {
    case lecture(Int)
    case unassigned
}

/// The selected lecture's header, then a bar of its transcripts and the course's notes beside the open item.
/// The lecture list itself lives in the sidebar.
public struct LecturesView: View {
    public let course: Course
    @ObservedObject var nav: CourseNavigation
    public var onNewLecture: () -> Void
    public var onTranscribe: (Int) -> Void

    init(course: Course, nav: CourseNavigation, onNewLecture: @escaping () -> Void, onTranscribe: @escaping (Int) -> Void) {
        self.course = course
        self.nav = nav
        self.onNewLecture = onNewLecture
        self.onTranscribe = onTranscribe
    }

    public var body: some View {
        if course.lectures.isEmpty && course.unassignedRecordingGroups.isEmpty && course.notes.isEmpty {
            VStack(spacing: 16) {
                Image(systemName: "list.number")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary.opacity(0.6))
                Text("No Lectures Yet")
                    .font(.title3.bold())
                Text("Create a lecture for each class session. Lectures are numbered automatically, and you can set the date and time.")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
                HStack {
                    Button {
                        onNewLecture()
                    } label: {
                        Label("New Lecture", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        createNote(title: "")
                    } label: {
                        Label("New Note", systemImage: "square.and.pencil")
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Group {
                switch nav.lectureSelection {
                case .lecture(let number):
                    if let lecture = course.lecture(number: number) {
                        LectureDetailPane(course: course, lecture: lecture, onTranscribe: { onTranscribe(lecture.number) }) {
                            workspace(groups: course.recordingGroups(for: lecture), lecture: lecture)
                        }
                        .id("\(course.id)#\(number)")
                    } else {
                        workspace(groups: [], lecture: nil)
                    }
                case .unassigned:
                    workspace(groups: course.unassignedRecordingGroups, lecture: nil)
                        .id("\(course.id)#unassigned")
                case nil:
                    workspace(groups: [], lecture: nil)
                }
            }
        }
    }

    private func workspace(groups: [RecordingGroup], lecture: Lecture?) -> some View {
        TranscriptWorkspace(
            course: course,
            groups: groups,
            nav: nav,
            onNewNote: { createNote(title: lecture.map { "Lecture \($0.number) notes" } ?? "") }
        )
    }

    private func createNote(title: String) {
        if let note = try? CourseStorageService.shared.createNote(courseID: course.id, title: title) {
            nav.barItem = .note(note.id)
        }
    }
}

struct LectureRow: View {
    let lecture: Lecture
    let recordingCount: Int
    let runningCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(lecture.label)
                    .font(.system(.caption, design: .monospaced).bold())
                    .foregroundColor(.accentColor)
                Text(lecture.title.isEmpty ? "Lecture \(lecture.number)" : lecture.title)
                    .font(.subheadline.bold())
                    .lineLimit(1)
            }
            HStack(spacing: 8) {
                Text(DateFormats.display.string(from: lecture.date))
                Spacer()
                if runningCount > 0 {
                    Image(systemName: "waveform")
                        .foregroundColor(.accentColor)
                        .help("\(runningCount) transcription\(runningCount == 1 ? "" : "s") in progress")
                }
                if recordingCount > 0 {
                    Label("\(recordingCount)", systemImage: "doc.text")
                }
            }
            .font(.caption2)
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Lecture Detail

struct LectureDetailPane<Content: View>: View {
    let course: Course
    let lecture: Lecture
    let onTranscribe: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var isEditing = false
    @State private var isConfirmingDelete = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                // The title is in the sidebar; this row carries what the sidebar doesn't.
                Label(DateFormats.display.string(from: lecture.date), systemImage: "calendar")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button {
                    onTranscribe()
                } label: {
                    Label("Transcribe Recording...", systemImage: "waveform.badge.plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Menu {
                    Button("Edit Title & Date...") { isEditing = true }
                    Divider()
                    Button("Delete Lecture...", role: .destructive) { isConfirmingDelete = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor))

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(8)
            }

            content()
        }
        .sheet(isPresented: $isEditing) {
            LectureEditorSheet(course: course, lecture: lecture) {
                isEditing = false
            }
        }
        .confirmationDialog("Delete \(lecture.displayTitle)?", isPresented: $isConfirmingDelete) {
            Button("Delete Lecture and Its Transcripts", role: .destructive) {
                do {
                    try CourseStorageService.shared.deleteLecture(courseID: course.id, number: lecture.number)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        } message: {
            Text("The lecture's transcript files will be moved to the Trash. Course materials aren't affected.")
        }
    }
}

private extension JobPhase {
    var isCompleted: Bool {
        if case .completed = self { return true }
        return false
    }
}

// MARK: - Recordings

/// Bar of transcripts and notes on the left, the open transcript or note on the right.
struct TranscriptWorkspace: View {
    let course: Course
    let groups: [RecordingGroup]
    @ObservedObject var nav: CourseNavigation
    let onNewNote: () -> Void

    @State private var renamingNote: NoteFile?
    @State private var renameText = ""
    @State private var deletingNote: NoteFile?
    @State private var errorMessage: String?

    var body: some View {
        HSplitView {
            bar
                .frame(minWidth: 150, idealWidth: 190, maxWidth: 280)

            detail
                .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear(perform: validateSelection)
        .onChange(of: groups.map(\.baseName)) { validateSelection() }
        .onChange(of: course.notes) { validateSelection() }
        .alert("Rename Note", isPresented: Binding(get: { renamingNote != nil }, set: { if !$0 { renamingNote = nil } })) {
            TextField("Name", text: $renameText)
            Button("Rename") { rename() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Links like [[old name]] in other notes won't be updated.")
        }
        .confirmationDialog("Delete \(deletingNote?.name ?? "note")?", isPresented: Binding(get: { deletingNote != nil }, set: { if !$0 { deletingNote = nil } })) {
            Button("Move Note to Trash", role: .destructive) { deleteNote() }
        }
    }

    private var bar: some View {
        List(selection: $nav.barItem) {
            Section("Transcripts") {
                if groups.isEmpty {
                    Text("None yet")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                ForEach(groups) { group in
                    TranscriptBarRow(group: group)
                        .tag(CourseNavigation.BarItem.recording(group.baseName))
                }
            }

            Section {
                if course.notes.isEmpty {
                    Text("None yet")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                ForEach(course.notes) { note in
                    Label(note.name, systemImage: "note.text")
                        .font(.subheadline)
                        .lineLimit(1)
                        .tag(CourseNavigation.BarItem.note(note.id))
                        .contextMenu {
                            Button("Rename...") {
                                renameText = note.name
                                renamingNote = note
                            }
                            Button("Reveal in Finder") { CourseStorageService.shared.revealInFinder(url: note.url) }
                            Divider()
                            Button("Delete...", role: .destructive) { deletingNote = note }
                        }
                }
            } header: {
                HStack {
                    Text("Notes")
                    Spacer()
                    Button(action: onNewNote) {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    .help("New note")
                }
            }
        }
        .listStyle(.inset)
    }

    private var detail: some View {
        VStack(spacing: 0) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(8)
            }
            detailContent
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch nav.barItem {
        case .recording(let baseName):
            if let group = groups.first(where: { $0.baseName == baseName }) {
                RecordingDetailView(course: course, group: group)
                    .id(group.id)
            } else {
                emptyDetail
            }
        case .note(let id):
            if let note = course.notes.first(where: { $0.id == id }) {
                NoteEditorView(course: course, note: note) { target in
                    nav.open(target, in: course)
                }
                .id(note.id)
            } else {
                emptyDetail
            }
        case nil:
            emptyDetail
        }
    }

    private var emptyDetail: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 36))
                .foregroundColor(.secondary.opacity(0.6))
            Text(groups.isEmpty ? "No transcripts for this lecture yet" : "Select a transcript or note")
                .font(.headline)
            if groups.isEmpty {
                Text("Drop an audio recording onto the bar above, or use Transcribe Recording. You can also add a note with the + beside Notes.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Keeps the open item valid: a note stays open across lectures, a transcript of another lecture doesn't.
    private func validateSelection() {
        switch nav.barItem {
        case .recording(let baseName) where groups.contains(where: { $0.baseName == baseName }):
            return
        case .note(let id) where course.notes.contains(where: { $0.id == id }):
            return
        default:
            nav.barItem = groups.first.map { .recording($0.baseName) }
        }
    }

    private func rename() {
        guard let note = renamingNote else { return }
        do {
            let renamed = try CourseStorageService.shared.renameNote(courseID: course.id, note: note, to: renameText)
            if nav.barItem == .note(note.id) { nav.barItem = .note(renamed.id) }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteNote() {
        guard let note = deletingNote else { return }
        do {
            try CourseStorageService.shared.deleteNote(courseID: course.id, note: note)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct TranscriptBarRow: View {
    let group: RecordingGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(group.info.map { "Recording \($0.number)" } ?? group.baseName, systemImage: "doc.text")
                .font(.subheadline)
                .lineLimit(1)
            if let info = group.info, info.durationSeconds > 0 {
                Text(TranscriptFormatter.clock(info.durationSeconds))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.leading, 22)
            }
        }
        .help(group.baseName)
    }
}

struct RecordingDetailView: View {
    let course: Course
    let group: RecordingGroup

    @State private var selectedFileID: String?
    @State private var content: String = ""
    @State private var isCopied = false
    @State private var isShowingQuickLook = false
    @State private var isConfirmingDelete = false
    @State private var errorMessage: String?

    private var activeFile: TranscriptFile? {
        group.files.first { $0.id == selectedFileID } ?? group.primaryFile
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.baseName)
                        .font(.headline)
                    if let info = group.info {
                        Text(recordingSummary(info))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                if group.files.count > 1 {
                    Picker("Format", selection: Binding(get: { activeFile?.id ?? "" }, set: { selectedFileID = $0 })) {
                        ForEach(group.files.sorted { $0.fileExtension < $1.fileExtension }) { file in
                            Text(file.fileExtension.uppercased()).tag(file.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .fixedSize()
                }

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(content, forType: .string)
                    isCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { isCopied = false }
                } label: {
                    Label(isCopied ? "Copied!" : "Copy", systemImage: isCopied ? "checkmark" : "doc.on.doc")
                }

                Menu {
                    Section("Export as") {
                        ForEach(TranscriptFormat.allCases) { format in
                            Button(format.displayName + (group.file(for: format) == nil ? "" : " (replace)")) {
                                export(format)
                            }
                        }
                    }
                    Divider()
                    if let file = activeFile {
                        Button("Quick Look") { isShowingQuickLook = true }
                        Button("Open with Default App") { CourseStorageService.shared.openFile(url: file.url) }
                        Button("Reveal in Finder") { CourseStorageService.shared.revealInFinder(url: file.url) }
                    }
                    Divider()
                    Button("Delete Recording...", role: .destructive) { isConfirmingDelete = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .padding(.horizontal)
            .padding(.vertical, 10)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal)
                    .padding(.bottom, 6)
            }

            Divider()

            ScrollView {
                Text(content)
                    .textSelection(.enabled)
                    .font(activeFile?.isMarkdown == false && activeFile?.fileExtension != "txt" ? .system(.callout, design: .monospaced) : .body)
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        }
        .onAppear(perform: loadContent)
        .onChange(of: selectedFileID) { loadContent() }
        .onChange(of: group.files) { loadContent() }
        .sheet(isPresented: $isShowingQuickLook) {
            if let file = activeFile {
                QuickLookModal(fileURL: file.url) { isShowingQuickLook = false }
            }
        }
        .confirmationDialog("Delete \(group.baseName)?", isPresented: $isConfirmingDelete) {
            Button("Move Transcript Files to Trash", role: .destructive) {
                do {
                    try CourseStorageService.shared.deleteRecording(courseID: course.id, baseName: group.baseName)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func recordingSummary(_ info: RecordingInfo) -> String {
        var parts = ["Recording \(info.number)"]
        if info.durationSeconds > 0 { parts.append(TranscriptFormatter.clock(info.durationSeconds)) }
        if !info.sourceAudio.isEmpty { parts.append(info.sourceAudio) }
        if info.model != "unknown" { parts.append(info.model) }
        return parts.joined(separator: " · ")
    }

    private func loadContent() {
        content = activeFile?.content ?? ""
    }

    private func export(_ format: TranscriptFormat) {
        do {
            let url = try CourseStorageService.shared.exportRecording(courseID: course.id, baseName: group.baseName, format: format)
            selectedFileID = url.path
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
