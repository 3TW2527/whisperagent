import SwiftUI

public enum LectureSelection: Hashable {
    case lecture(Int)
    case unassigned
    /// Projects only: the list of actions from every note.
    case actions
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
                Image(systemName: course.isProject ? "person.3" : "list.number")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary.opacity(0.6))
                Text("No \(course.kind.unitPlural) Yet")
                    .font(.title3.bold())
                Text(course.isProject
                     ? "Create a meeting each time the group meets. Meetings are numbered automatically, can belong to a series such as a weekly team meeting, and hold their own notes, recordings and files."
                     : "Create a lecture for each class session. Lectures are numbered automatically, and you can set the date and time.")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
                HStack {
                    Button {
                        onNewLecture()
                    } label: {
                        Label("New \(course.kind.unitName)", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        createNote(lecture: nil)
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
                case .actions:
                    ActionsView(course: course, nav: nav)
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
            lecture: lecture,
            nav: nav,
            onNewNote: { createNote(lecture: lecture) }
        )
    }

    private func createNote(lecture: Lecture?) {
        if let note = try? CourseStorageService.shared.createNote(courseID: course.id, lecture: lecture) {
            nav.barItem = .note(note.id)
        }
    }
}

struct LectureRow: View {
    let course: Course
    let lecture: Lecture
    let recordingCount: Int
    let runningCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(lecture.label)
                    .font(.system(.caption, design: .monospaced).bold())
                    .foregroundColor(.accentColor)
                Text(lecture.shortTitle)
                    .font(.subheadline.bold())
                    .lineLimit(1)
            }
            HStack(spacing: 8) {
                Text(DateFormats.display.string(from: lecture.date))
                if let series = lecture.series, !lecture.title.isEmpty {
                    SeriesChip(name: series)
                }
                Spacer()
                let fileCount = course.files(forMeeting: lecture.number).count
                if course.isProject && fileCount > 0 {
                    Label("\(fileCount)", systemImage: "paperclip")
                        .help("\(fileCount) file\(fileCount == 1 ? "" : "s") from this meeting")
                }
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

/// A small capsule naming a meeting's series.
struct SeriesChip: View {
    let name: String

    var body: some View {
        Text(name)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Capsule().fill(SeriesChip.color(for: name).opacity(0.18)))
            .foregroundColor(SeriesChip.color(for: name))
            .lineLimit(1)
    }

    /// A steady colour per series name, so a series looks the same everywhere.
    static func color(for name: String) -> Color {
        let palette: [Color] = [.blue, .orange, .green, .purple, .pink, .teal, .indigo, .brown]
        let sum = name.lowercased().unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return palette[sum % palette.count]
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
                if let series = lecture.series {
                    SeriesChip(name: series)
                }
                Spacer()
                Button {
                    onTranscribe()
                } label: {
                    Label("Transcribe Recording...", systemImage: "waveform.badge.plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Menu {
                    Button(course.isProject ? "Edit Meeting..." : "Edit Title & Date...") { isEditing = true }
                    if course.isProject {
                        Button("Show Meeting Folder") {
                            let folder = course.meetingFolderURL(number: lecture.number)
                            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                            CourseStorageService.shared.revealInFinder(url: folder)
                        }
                    }
                    Divider()
                    Button("Delete \(course.kind.unitName)...", role: .destructive) { isConfirmingDelete = true }
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
            Button("Delete \(course.kind.unitName) and Its Transcripts", role: .destructive) {
                do {
                    try CourseStorageService.shared.deleteLecture(courseID: course.id, number: lecture.number)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        } message: {
            Text(course.isProject
                 ? "The meeting's transcripts and its files in meetings/\(lecture.label) will be moved to the Trash. Notes and project materials aren't affected."
                 : "The lecture's transcript files will be moved to the Trash. Course materials aren't affected.")
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
    let lecture: Lecture?
    @ObservedObject var nav: CourseNavigation
    let onNewNote: () -> Void

    @State private var renamingNote: NoteFile?
    @State private var renameText = ""
    @State private var deletingNote: NoteFile?
    @State private var errorMessage: String?

    /// Only this lecture's notes; course-wide notes show where no lecture is open.
    private var notes: [NoteFile] {
        course.notes(for: lecture)
    }

    /// A meeting's own files from `meetings/M03/`.
    private var meetingFiles: [LectureFile] {
        guard course.isProject, let lecture else { return [] }
        return course.files(forMeeting: lecture.number)
    }

    var body: some View {
        HSplitView {
            bar
                .frame(minWidth: 150, idealWidth: 190, maxWidth: 280)

            detail
                .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear(perform: validateSelection)
        .onChange(of: groups.map(\.baseName)) { validateSelection() }
        .onChange(of: notes) { validateSelection() }
        .onChange(of: meetingFiles) { validateSelection() }
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
                if notes.isEmpty {
                    Text("None yet")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                ForEach(notes) { note in
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

            if course.isProject, let lecture {
                Section {
                    if meetingFiles.isEmpty {
                        Text("Drop files onto the bar above")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    ForEach(meetingFiles) { file in
                        Label {
                            Text(file.name)
                                .lineLimit(1)
                        } icon: {
                            Image(systemName: file.systemIconName)
                                .foregroundColor(file.iconColor)
                        }
                        .font(.subheadline)
                        .tag(CourseNavigation.BarItem.file(file.id))
                        .contextMenu {
                            Button("Open with Default App") { CourseStorageService.shared.openFile(url: file.url) }
                            Button("Reveal in Finder") { CourseStorageService.shared.revealInFinder(url: file.url) }
                            MoveToMeetingMenu(course: course, file: file, currentMeeting: lecture.number)
                            Divider()
                            Button("Move to Trash", role: .destructive) { CourseStorageService.shared.deleteMaterial(file) }
                        }
                    }
                } header: {
                    HStack {
                        Text("Files")
                        Spacer()
                        Button {
                            addMeetingFiles(to: lecture)
                        } label: {
                            Image(systemName: "plus")
                        }
                        .buttonStyle(.borderless)
                        .help("Add files to this meeting")
                    }
                }
            }
        }
        .listStyle(.inset)
    }

    private func addMeetingFiles(to lecture: Lecture) {
        let panel = NSOpenPanel()
        panel.title = "Add Files to \(lecture.label) · \(lecture.shortTitle)"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.begin { response in
            guard response == .OK else { return }
            for url in panel.urls {
                _ = try? CourseStorageService.shared.ingestMaterial(from: url, courseID: course.id, meetingNumber: lecture.number)
            }
        }
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
            if let note = notes.first(where: { $0.id == id }) {
                NoteEditorView(course: course, note: note) { target in
                    nav.open(target, in: course)
                }
                .id(note.id)
            } else {
                emptyDetail
            }
        case .file(let id):
            if let file = meetingFiles.first(where: { $0.id == id }) {
                FilePreviewPane(file: file)
                    .id(file.id)
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
            Text(groups.isEmpty ? "No transcripts for this \(course.kind.unitName.lowercased()) yet" : "Select a transcript or note")
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
        case .note(let id) where notes.contains(where: { $0.id == id }):
            return
        case .file(let id) where meetingFiles.contains(where: { $0.id == id }):
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
