import SwiftUI

public enum LectureSelection: Hashable {
    case lecture(Int)
    case unassigned
}

/// Lecture list on the left; the selected lecture's recordings and transcript on the right.
public struct LecturesView: View {
    public let course: Course
    @Binding public var selection: LectureSelection?
    public var onNewLecture: () -> Void
    public var onTranscribe: (Int) -> Void

    @ObservedObject private var transcriptionService = WhisperTranscriptionService.shared

    public init(course: Course, selection: Binding<LectureSelection?>, onNewLecture: @escaping () -> Void, onTranscribe: @escaping (Int) -> Void) {
        self.course = course
        self._selection = selection
        self.onNewLecture = onNewLecture
        self.onTranscribe = onTranscribe
    }

    public var body: some View {
        if course.lectures.isEmpty && course.unassignedRecordingGroups.isEmpty {
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
                Button {
                    onNewLecture()
                } label: {
                    Label("New Lecture", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HSplitView {
                VStack(spacing: 0) {
                    List(selection: $selection) {
                        ForEach(course.lectures.reversed()) { lecture in
                            LectureRow(
                                lecture: lecture,
                                recordingCount: course.recordingGroups(for: lecture).count,
                                runningCount: transcriptionService.activeJobs.filter { $0.courseID == course.id && $0.lectureNumber == lecture.number }.count
                            )
                            .tag(LectureSelection.lecture(lecture.number))
                        }
                        if !course.unassignedRecordingGroups.isEmpty {
                            Label("Other transcripts (\(course.unassignedRecordingGroups.count))", systemImage: "tray")
                                .font(.subheadline)
                                .tag(LectureSelection.unassigned)
                        }
                    }
                    .listStyle(.inset)

                    Divider()
                    Button {
                        onNewLecture()
                    } label: {
                        Label("New Lecture", systemImage: "plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderless)
                    .padding(8)
                }
                .frame(minWidth: 200, idealWidth: 240, maxWidth: 300)

                Group {
                    switch selection {
                    case .lecture(let number):
                        if let lecture = course.lecture(number: number) {
                            LectureDetailPane(course: course, lecture: lecture, onTranscribe: { onTranscribe(lecture.number) })
                                .id("\(course.id)#\(number)")
                        } else {
                            placeholder
                        }
                    case .unassigned:
                        RecordingsBrowser(course: course, groups: course.unassignedRecordingGroups)
                            .id("\(course.id)#unassigned")
                    case nil:
                        placeholder
                    }
                }
                .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
            }
            .onAppear(perform: validateSelection)
            .onChange(of: course.id) { validateSelection() }
            .onChange(of: course.lectures) { validateSelection() }
        }
    }

    private var placeholder: some View {
        Text("Select a lecture")
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func validateSelection() {
        switch selection {
        case .lecture(let number) where course.lecture(number: number) != nil:
            return
        case .unassigned where !course.unassignedRecordingGroups.isEmpty:
            return
        default:
            if let latest = course.lectures.last {
                selection = .lecture(latest.number)
            } else if !course.unassignedRecordingGroups.isEmpty {
                selection = .unassigned
            } else {
                selection = nil
            }
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

struct LectureDetailPane: View {
    let course: Course
    let lecture: Lecture
    let onTranscribe: () -> Void

    @ObservedObject private var transcriptionService = WhisperTranscriptionService.shared
    @State private var isEditing = false
    @State private var isConfirmingDelete = false
    @State private var errorMessage: String?

    private var jobs: [TranscriptionJob] {
        transcriptionService.jobs.filter { $0.courseID == course.id && $0.lectureNumber == lecture.number && !$0.phase.isCompleted }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(lecture.displayTitle)
                        .font(.title3.bold())
                    Label(DateFormats.display.string(from: lecture.date), systemImage: "calendar")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button {
                    onTranscribe()
                } label: {
                    Label("Transcribe Recording...", systemImage: "waveform.badge.plus")
                }
                .buttonStyle(.borderedProminent)

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
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            if !jobs.isEmpty {
                VStack(spacing: 6) {
                    ForEach(jobs) { job in
                        JobRowView(job: job, showsCourse: false)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                Divider()
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(8)
            }

            RecordingsBrowser(course: course, groups: course.recordingGroups(for: lecture))
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

/// Recording picker plus a viewer for the selected recording's transcript.
struct RecordingsBrowser: View {
    let course: Course
    let groups: [RecordingGroup]

    @State private var selectedBaseName: String?

    private var activeGroup: RecordingGroup? {
        groups.first { $0.baseName == selectedBaseName } ?? groups.first
    }

    var body: some View {
        if groups.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 36))
                    .foregroundColor(.secondary.opacity(0.6))
                Text("No transcripts for this lecture yet")
                    .font(.headline)
                Text("Drop an audio recording onto the bar above, or use Transcribe Recording.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                if groups.count > 1 {
                    Picker("Recording (\(groups.count))", selection: Binding(get: { activeGroup?.baseName ?? "" }, set: { selectedBaseName = $0 })) {
                        ForEach(groups) { group in
                            Text(group.baseName).tag(group.baseName)
                        }
                    }
                    .pickerStyle(.menu)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    Divider()
                }
                if let group = activeGroup {
                    RecordingDetailView(course: course, group: group)
                        .id(group.id)
                }
            }
        }
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
