import SwiftUI

/// Sidebar shown once a course is entered: a way back, the course's lectures, and its documents.
/// A project's sidebar shows meetings, project materials and the user's own files instead.
struct CourseSidebarView: View {
    let course: Course
    @ObservedObject var nav: CourseNavigation
    let onBack: () -> Void
    let onEditCourse: () -> Void
    let onConvertToProject: () -> Void

    @ObservedObject private var transcriptionService = WhisperTranscriptionService.shared

    var body: some View {
        VStack(spacing: 0) {
            header

            Picker("", selection: $nav.sidebarTab) {
                ForEach(CourseNavigation.SidebarTab.tabs(for: course.kind)) { tab in
                    Text(tabTitle(tab)).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            Divider()

            switch nav.sidebarTab {
            case .lectures:
                lectureList
            case .documents:
                documentList
            case .files:
                ProjectFilesList(course: course, nav: nav)
            }
        }
    }

    /// Courses show counts; a project's three tabs would be too wide with them.
    private func tabTitle(_ tab: CourseNavigation.SidebarTab) -> String {
        let title = tab.title(for: course.kind)
        guard !course.isProject else { return title }
        switch tab {
        case .lectures: return "\(title) (\(course.lectures.count))"
        case .documents: return "\(title) (\(course.materials.count))"
        case .files: return title
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: onBack) {
                Label("All Courses", systemImage: "chevron.left")
                    .font(.caption)
            }
            .buttonStyle(.borderless)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    if !course.metadata.code.isEmpty {
                        Text(course.metadata.code)
                            .font(.system(.caption, design: .monospaced).bold())
                            .foregroundColor(.accentColor)
                    }
                    Text(course.name)
                        .font(.headline)
                        .lineLimit(2)
                }
                Spacer()
                Menu {
                    Button("\(course.kind.displayName) Settings...", action: onEditCourse)
                    if !course.isProject {
                        Button("Convert to Project...", action: onConvertToProject)
                    }
                    Button("Reveal in Finder") { CourseStorageService.shared.revealInFinder(url: course.folderURL) }
                } label: {
                    Image(systemName: "gearshape")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help(course.isProject ? "Project settings: name, code, meeting series, key dates and location" : "Course settings: name, code, tags and location")
            }

            if !course.tags.isEmpty {
                Text(course.tags.joined(separator: " · "))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    // MARK: - Lectures

    private var lectureList: some View {
        VStack(spacing: 0) {
            List(selection: $nav.lectureSelection) {
                if course.isProject {
                    let open = course.actions.filter { !$0.isDone }
                    Label {
                        HStack {
                            Text("Actions")
                            Spacer()
                            if !open.isEmpty {
                                Text("\(open.count)")
                                    .font(.caption.monospacedDigit())
                                    .padding(.horizontal, 6)
                                    .background(Capsule().fill(open.contains { $0.isOverdue() } ? Color.red.opacity(0.2) : Color.secondary.opacity(0.15)))
                            }
                        }
                    } icon: {
                        Image(systemName: "checklist")
                    }
                    .font(.subheadline)
                    .tag(LectureSelection.actions)
                    .help("Open actions from every note")
                }
                ForEach(course.lectures.reversed()) { lecture in
                    LectureRow(
                        course: course,
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
            .listStyle(.sidebar)
            .overlay {
                if course.lectures.isEmpty && course.unassignedRecordingGroups.isEmpty {
                    Text("No \(course.kind.unitPlural.lowercased()) yet")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Divider()
            Button {
                nav.isAddingLecture = true
            } label: {
                Label("New \(course.kind.unitName)", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderless)
            .padding(8)
        }
    }

    // MARK: - Documents

    private var documentList: some View {
        VStack(spacing: 0) {
            List(selection: $nav.documentID) {
                ForEach(course.materials) { file in
                    Label {
                        Text(file.name)
                            .lineLimit(1)
                    } icon: {
                        Image(systemName: file.systemIconName)
                            .foregroundColor(file.iconColor)
                    }
                    .tag(file.id)
                    .contextMenu {
                        Button("Open with Default App") { CourseStorageService.shared.openFile(url: file.url) }
                        Button("Reveal in Finder") { CourseStorageService.shared.revealInFinder(url: file.url) }
                        if course.isProject {
                            MoveToMeetingMenu(course: course, file: file, currentMeeting: nil)
                        }
                        Divider()
                        Button("Move to Trash", role: .destructive) { CourseStorageService.shared.deleteMaterial(file) }
                    }
                }
            }
            .listStyle(.sidebar)
            .overlay {
                if course.materials.isEmpty {
                    Text(course.isProject ? "No project materials yet\nAdd reference files for the whole project" : "No documents yet\nDrop files onto the bar above")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }

            Divider()
            Button {
                addFiles()
            } label: {
                Label("Add Files...", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderless)
            .padding(8)
        }
    }

    private func addFiles() {
        let panel = NSOpenPanel()
        panel.title = course.isProject ? "Select Project Materials to Add" : "Select Course Materials to Add"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.begin { response in
            guard response == .OK else { return }
            for url in panel.urls {
                _ = try? CourseStorageService.shared.ingestMaterial(from: url, courseID: course.id)
            }
        }
    }
}

/// Inline preview of the document selected in the sidebar.
struct DocumentPane: View {
    let course: Course
    @ObservedObject var nav: CourseNavigation

    private var file: LectureFile? {
        course.materials.first { $0.id == nav.documentID }
    }

    var body: some View {
        if let file {
            FilePreviewPane(file: file)
        } else {
            VStack(spacing: 10) {
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 40))
                    .foregroundColor(.secondary.opacity(0.6))
                Text(course.materials.isEmpty ? (course.isProject ? "No project materials yet" : "No documents yet") : "Select a document")
                    .font(.headline)
                Text(course.isProject
                     ? "Materials are reference files for the whole project. Files from one meeting go in that meeting: select it and drop them onto the bar above."
                     : "Drop slides, PDFs or readings onto the bar above to add them to this course.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Context menu items that move a project file to one of its meetings, or back to the project's materials.
struct MoveToMeetingMenu: View {
    let course: Course
    let file: LectureFile
    /// The meeting the file is in now, or nil when it's in the project's materials.
    let currentMeeting: Int?

    var body: some View {
        Menu("Move to Meeting") {
            ForEach(course.lectures.reversed().filter { $0.number != currentMeeting }) { meeting in
                Button("\(meeting.label) · \(meeting.shortTitle)") { move(to: meeting.number) }
            }
        }
        if currentMeeting != nil {
            Button("Move to Project Materials") { move(to: nil) }
        }
    }

    private func move(to meeting: Int?) {
        try? CourseStorageService.shared.moveFile(file, courseID: course.id, toMeeting: meeting)
    }
}

/// Files: the user's own folders in a project, as a tree.
struct ProjectFilesList: View {
    let course: Course
    @ObservedObject var nav: CourseNavigation

    @State private var tree: [ProjectFileNode] = []

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $nav.projectFileID) {
                OutlineGroup(tree, children: \.children) { node in
                    Label {
                        Text(node.name)
                            .lineLimit(1)
                    } icon: {
                        Image(systemName: node.isDirectory ? "folder" : LectureFile.systemIconName(forExtension: node.fileExtension))
                            .foregroundColor(node.isDirectory ? .accentColor : LectureFile.iconColor(forExtension: node.fileExtension))
                    }
                    .tag(node.id)
                    .contextMenu {
                        if !node.isDirectory {
                            Button("Open with Default App") { CourseStorageService.shared.openFile(url: node.url) }
                        }
                        Button("Reveal in Finder") { CourseStorageService.shared.revealInFinder(url: node.url) }
                    }
                }
            }
            .listStyle(.sidebar)
            .overlay {
                if tree.isEmpty {
                    Text("No files of your own yet\nFolders you make in the project folder show up here")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                }
            }

            Divider()
            HStack {
                Button {
                    CourseStorageService.shared.revealInFinder(url: course.folderURL)
                } label: {
                    Label("Show Project Folder", systemImage: "folder")
                }
                Spacer()
                Button {
                    refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh")
            }
            .buttonStyle(.borderless)
            .padding(8)
        }
        .onAppear(perform: refresh)
        .onChange(of: course) { refresh() }
    }

    private func refresh() {
        tree = ProjectFiles.tree(of: course)
    }
}

/// Preview of the file selected under Files. Markdown files open in the note editor.
struct ProjectFilePane: View {
    let course: Course
    @ObservedObject var nav: CourseNavigation

    var body: some View {
        if let path = nav.projectFileID, FileManager.default.fileExists(atPath: path), !isDirectory(path) {
            let url = URL(fileURLWithPath: path)
            if url.pathExtension.lowercased() == "md" {
                MarkdownDocumentEditor(
                    fileURL: url,
                    title: url.deletingPathExtension().lastPathComponent,
                    linkContext: WikilinkContext(course: course),
                    exportDirectory: url.deletingLastPathComponent(),
                    onWikilink: { nav.open($0, in: course) }
                )
                .id(path)
            } else {
                FilePreviewPane(file: LectureFile(url: url))
                    .id(path)
            }
        } else {
            VStack(spacing: 10) {
                Image(systemName: "folder")
                    .font(.system(size: 40))
                    .foregroundColor(.secondary.opacity(0.6))
                Text("Your own files")
                    .font(.headline)
                Text("Everything in the project folder apart from materials, meetings, notes and transcripts is listed here, as it is in Finder. Select a file to preview it.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func isDirectory(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }
}

/// A file's name and details, buttons to open it, and a Quick Look preview.
struct FilePreviewPane: View {
    let file: LectureFile

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.name)
                        .font(.headline)
                        .lineLimit(1)
                    Text("\(file.kindDescription) · \(file.formattedSize) · \(file.formattedModifiedDate)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button {
                    CourseStorageService.shared.openFile(url: file.url)
                } label: {
                    Label("Open", systemImage: "arrow.up.forward.app")
                }
                Button {
                    CourseStorageService.shared.revealInFinder(url: file.url)
                } label: {
                    Image(systemName: "folder")
                }
                .help("Reveal in Finder")
            }
            .padding(.horizontal)
            .padding(.vertical, 10)

            Divider()

            QuickLookPreviewView(fileURL: file.url)
                .id(file.id)
        }
    }
}
