import SwiftUI

struct PendingAudio: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let courseID: String
    let lectureNumber: Int?
}

enum ActiveSheet: Identifiable {
    case newCourse
    case editCourse(courseID: String)
    case settings
    case askAI(courseID: String?)
    case migration
    case trimmer(PendingAudio)

    var id: String {
        switch self {
        case .newCourse: return "newCourse"
        case .editCourse(let id): return "editCourse-\(id)"
        case .settings: return "settings"
        case .askAI(let id): return "askAI-\(id ?? "all")"
        case .migration: return "migration"
        case .trimmer(let pending): return "trimmer-\(pending.id)"
        }
    }
}

public struct MainView: View {
    @StateObject private var storage = CourseStorageService.shared
    @StateObject private var nav = CourseNavigation()
    @ObservedObject private var settings = AppSettings.shared

    @State private var searchText = ""
    @State private var selectedTags: Set<String> = []
    @State private var activeSheet: ActiveSheet?
    @State private var errorMessage: String?
    /// Audio files waiting for the trimmer, shown one after another.
    @State private var audioQueue: [PendingAudio] = []

    public init() {}

    private var filteredCourses: [Course] {
        storage.courses.filter { course in
            let matchesTags = selectedTags.allSatisfy { tag in
                course.tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
            }
            guard matchesTags else { return false }
            guard !searchText.isEmpty else { return true }
            return course.name.localizedCaseInsensitiveContains(searchText)
                || course.metadata.code.localizedCaseInsensitiveContains(searchText)
                || course.tags.contains { $0.localizedCaseInsensitiveContains(searchText) }
                || course.lectures.contains { $0.title.localizedCaseInsensitiveContains(searchText) }
        }
    }

    public var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            activeSheet = .newCourse
                        } label: {
                            Label("New Course", systemImage: "plus")
                        }
                        .help("New Course (⌘N)")
                    }
                }
        } detail: {
            VStack(spacing: 0) {
                JobsPanelView()

                if let course = storage.selectedCourse {
                    CourseDetailView(
                        course: course,
                        nav: nav,
                        onSelectAudio: { url, lecture in
                            enqueueAudio(url, courseID: course.id, lectureNumber: lecture)
                        }
                    )
                    .id(course.id)
                } else {
                    emptyState
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        activeSheet = .askAI(courseID: storage.selectedCourseID)
                    } label: {
                        Label("Ask an AI", systemImage: "sparkles")
                    }
                    .help("How to use Claude, ChatGPT/Codex or Gemini with \(storage.selectedCourse == nil ? "your study library" : "this course")")
                }
            }
        }
        .sheet(item: $activeSheet, onDismiss: showNextQueuedAudio) { sheet in
            switch sheet {
            case .newCourse:
                CourseEditorSheet { activeSheet = nil }
            case .editCourse(let courseID):
                if let course = storage.course(id: courseID) {
                    CourseEditorSheet(course: course) { activeSheet = nil }
                }
            case .settings:
                SettingsView { activeSheet = nil }
            case .askAI(let courseID):
                AskAIView(initialCourseID: courseID) { activeSheet = nil }
            case .migration:
                MigrationSheet { activeSheet = nil }
            case .trimmer(let pending):
                if let course = storage.course(id: pending.courseID) {
                    AudioTrimmerSheet(audioURL: pending.url, course: course, initialLecture: pending.lectureNumber) {
                        activeSheet = nil
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .createNewCourse)) { _ in
            activeSheet = .newCourse
        }
        .onChange(of: storage.selectedCourseID) {
            nav.reset()
        }
        .alert("Something went wrong", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .onAppear {
            if !storage.legacyFolders.isEmpty {
                activeSheet = .migration
            }
        }
    }

    // MARK: - Sidebar

    @ViewBuilder
    private var sidebar: some View {
        // Selecting a course opens it: one change drives both the sidebar and the main area.
        if let course = storage.selectedCourse {
            VStack(spacing: 0) {
                CourseSidebarView(
                    course: course,
                    nav: nav,
                    onBack: { storage.selectedCourseID = nil },
                    onEditCourse: { activeSheet = .editCourse(courseID: course.id) }
                )
                sidebarFooter
            }
        } else {
            courseListSidebar
        }
    }

    private var courseListSidebar: some View {
        VStack(spacing: 0) {
            if !storage.allTags.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Filter by tag")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                        Spacer()
                        if !selectedTags.isEmpty {
                            Button("Clear") { selectedTags = [] }
                                .buttonStyle(.borderless)
                                .font(.caption)
                        }
                    }
                    WrappingHStack(items: storage.allTags) { tag in
                        Button {
                            if selectedTags.contains(tag) {
                                selectedTags.remove(tag)
                            } else {
                                selectedTags.insert(tag)
                            }
                        } label: {
                            TagChip(tag: tag, isSelected: selectedTags.contains(tag))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                Divider()
            }

            List(selection: $storage.selectedCourseID) {
                Section(selectedTags.isEmpty ? "Courses" : "Courses (\(filteredCourses.count) of \(storage.courses.count))") {
                    ForEach(filteredCourses) { course in
                        CourseRow(course: course)
                            .tag(course.id)
                            .contextMenu {
                                Button("Course Settings...") {
                                    activeSheet = .editCourse(courseID: course.id)
                                }
                                Button("Move to Another Folder...") {
                                    chooseFolder(for: course)
                                }
                                if course.isExternal {
                                    Button("Move Back to Library Folder") {
                                        move(course, to: nil)
                                    }
                                }
                                Divider()
                                Button("Reveal in Finder") {
                                    storage.revealInFinder(url: course.folderURL)
                                }
                                Divider()
                                Button("Move Course to Trash", role: .destructive) {
                                    storage.deleteCourse(id: course.id)
                                }
                            }
                    }
                }
            }
            .searchable(text: $searchText, placement: .sidebar, prompt: "Search courses, tags, lectures")
            .listStyle(.sidebar)

            if !storage.legacyFolders.isEmpty {
                Button {
                    activeSheet = .migration
                } label: {
                    Label("\(storage.legacyFolders.count) older lecture folder\(storage.legacyFolders.count == 1 ? "" : "s") to organise", systemImage: "tray.and.arrow.down")
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderless)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.12))
            }

            sidebarFooter
        }
    }

    private var sidebarFooter: some View {
        VStack(spacing: 0) {
            Divider()

            HStack {
                Button {
                    activeSheet = .settings
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.plain)
                .help("Settings & Models")

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: settings.isUsingiCloud ? "icloud.fill" : "folder.fill")
                        .foregroundColor(settings.isUsingiCloud ? .blue : .secondary)
                    Text(settings.isUsingiCloud ? "iCloud Drive" : "Local")
                        .foregroundColor(.secondary)
                }
                .font(.caption2)
            }
            .padding(10)
            .background(Color(NSColor.controlBackgroundColor))
        }
    }

    private func chooseFolder(for course: Course) {
        let panel = NSOpenPanel()
        panel.title = "Choose the folder for \(course.name)"
        panel.message = "The course's files are moved directly into the folder you choose. It must be empty."
        panel.prompt = "Use This Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = course.folderURL.deletingLastPathComponent()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        move(course, to: url)
    }

    private func move(_ course: Course, to destination: URL?) {
        do {
            try storage.moveCourse(id: course.id, to: destination)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "books.vertical")
                .font(.system(size: 56))
                .foregroundColor(.secondary.opacity(0.5))

            Text(storage.courses.isEmpty ? "Create Your First Course" : "No Course Selected")
                .font(.title2.bold())

            Text("Each course holds numbered lectures with their transcripts, plus shared materials like slides and readings. The folder is laid out so AI assistants can read it.")
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            Button("New Course") {
                activeSheet = .newCourse
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Audio Queue

    private func enqueueAudio(_ url: URL, courseID: String, lectureNumber: Int?) {
        audioQueue.append(PendingAudio(url: url, courseID: courseID, lectureNumber: lectureNumber))
        if activeSheet == nil {
            showNextQueuedAudio()
        }
    }

    private func showNextQueuedAudio() {
        guard activeSheet == nil, !audioQueue.isEmpty else { return }
        activeSheet = .trimmer(audioQueue.removeFirst())
    }
}

struct CourseRow: View {
    let course: Course

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if !course.metadata.code.isEmpty {
                    Text(course.metadata.code)
                        .font(.system(.caption, design: .monospaced).bold())
                        .foregroundColor(.accentColor)
                }
                Text(course.name)
                    .font(.headline)
                    .lineLimit(1)
                if course.isExternal {
                    Image(systemName: "folder.badge.gearshape")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .help("Stored outside the library: \(course.folderURL.path)")
                }
            }

            HStack(spacing: 8) {
                Label("\(course.lectures.count)", systemImage: "list.number")
                if !course.materials.isEmpty {
                    Label("\(course.materials.count)", systemImage: "paperclip")
                }
                if let latest = course.lectures.last {
                    Text(DateFormats.isoDay.string(from: latest.date))
                }
                Spacer()
            }
            .font(.caption2)
            .foregroundColor(.secondary)

            if !course.tags.isEmpty {
                Text(course.tags.joined(separator: " · "))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }
}

// Extension to allow URL to be used with .sheet(item:)
extension URL: @retroactive Identifiable {
    public var id: String { self.absoluteString }
}
