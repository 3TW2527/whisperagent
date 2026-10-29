import SwiftUI

enum CanvasViewMode: String, CaseIterable, Identifiable {
    case byDate = "By Date"
    case byCourse = "By Course"

    var id: String { rawValue }
}

enum CanvasSortOrder: String, CaseIterable, Identifiable {
    case newest = "Newest First"
    case name = "Name A–Z"

    var id: String { rawValue }
}

/// A group of files under one heading: a course, or a day.
private struct CanvasFileSection: Identifiable {
    let id: String
    let title: String
    var subtitle: String?
    var notice: String?
    let files: [CanvasFileRecord]
}

/// Home-screen tool: files from the user's Canvas courses, by course or by date, with checkboxes to download them.
struct CanvasView: View {
    @ObservedObject private var canvas = CanvasSyncService.shared
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var storage = CourseStorageService.shared

    @AppStorage("whisperlectures_canvas_mode") private var mode: CanvasViewMode = .byDate
    @AppStorage("whisperlectures_canvas_sort") private var sort: CanvasSortOrder = .newest
    @State private var search = ""
    @State private var selection: Set<Int> = []
    @State private var collapsed: Set<String> = []

    var body: some View {
        Group {
            if canvas.isConfigured {
                VStack(spacing: 0) {
                    toolbar
                    Divider()
                    if let error = canvas.errorMessage {
                        errorBanner(error)
                    }
                    content
                }
            } else {
                setup
            }
        }
        .task {
            if canvas.isConfigured { await canvas.sync() }
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            Picker("", selection: $mode) {
                ForEach(CanvasViewMode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            if mode == .byCourse {
                Picker("Sort", selection: $sort) {
                    ForEach(CanvasSortOrder.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                .help("How files are sorted within each course")
            }

            TextField("Filter files", text: $search)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 120, maxWidth: 220)

            Spacer(minLength: 8)

            syncStatus

            Menu {
                Button("Select Not Downloaded") { selection = Set(selectable.filter { isWaiting($0) }.map(\.id)) }
                Button("Deselect All") { selection = [] }
            } label: {
                Text(allSelected ? "Deselect All" : "Select All")
            } primaryAction: {
                selection = allSelected ? [] : Set(selectable.map(\.id))
            }
            .fixedSize()
            .disabled(selectable.isEmpty)
            .help("Select every file shown that can be downloaded")

            Button {
                let ids = filesShown.filter { selection.contains($0.id) && canvas.canDownload($0) }.map(\.id)
                selection = []
                Task { await canvas.download(ids) }
            } label: {
                Label(selectedCount > 0 ? "Download \(selectedCount)" : "Download", systemImage: "arrow.down.circle")
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedCount == 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var syncStatus: some View {
        HStack(spacing: 6) {
            if canvas.isSyncing {
                ProgressView().controlSize(.small)
                Text("Syncing...")
            } else if let last = canvas.lastSyncedAt {
                Text("Synced \(last, format: .relative(presentation: .named))")
            }
            Button {
                Task { await canvas.sync() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(canvas.isSyncing)
            .help("Check Canvas for new files")
        }
        .font(.caption)
        .foregroundColor(.secondary)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text(message)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button {
                canvas.errorMessage = nil
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.12))
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if canvas.visibleCourses.isEmpty {
            placeholder(
                icon: "graduationcap",
                title: canvas.isSyncing ? "Looking through your courses..." : "No courses",
                detail: canvas.isSyncing ? "The first sync reads every course, so it can take a minute." : "Courses you're enrolled in appear here. Hidden courses can be shown again in this tool's settings."
            )
        } else if canvas.files.isEmpty && canvas.isSyncing {
            placeholder(icon: "arrow.triangle.2.circlepath", title: "Looking through your courses...", detail: "The first sync reads every course, so it can take a minute.")
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(sections) { section in
                        Section {
                            if !collapsed.contains(section.id) {
                                sectionBody(section)
                            }
                        } header: {
                            sectionHeader(section)
                        }
                    }
                }
                .padding(.bottom, 12)
            }
        }
    }

    @ViewBuilder
    private func sectionBody(_ section: CanvasFileSection) -> some View {
        if let notice = section.notice {
            Label(notice, systemImage: "info.circle")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
        }
        if section.files.isEmpty {
            Text(search.isEmpty ? "No files found" : "No matches")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
        }
        ForEach(section.files) { file in
            CanvasFileRow(
                file: file,
                courseLabel: mode == .byDate ? courseLabel(file.courseID) : nil,
                isSelected: Binding(
                    get: { selection.contains(file.id) },
                    set: { if $0 { selection.insert(file.id) } else { selection.remove(file.id) } }
                )
            )
            Divider().padding(.leading, 44)
        }
    }

    private func sectionHeader(_ section: CanvasFileSection) -> some View {
        let ids = Set(section.files.filter { canvas.canDownload($0) }.map(\.id))
        let selectedHere = ids.intersection(selection).count
        let isCollapsed = collapsed.contains(section.id)
        return HStack(spacing: 8) {
            Button {
                if selectedHere == ids.count { selection.subtract(ids) } else { selection.formUnion(ids) }
            } label: {
                Image(systemName: selectedHere == 0 ? "square" : selectedHere == ids.count ? "checkmark.square.fill" : "minus.square.fill")
                    .foregroundColor(selectedHere == 0 ? .secondary : .accentColor)
            }
            .buttonStyle(.borderless)
            .disabled(ids.isEmpty)
            .help("Select every file in \(section.title)")

            Button {
                if isCollapsed { collapsed.remove(section.id) } else { collapsed.insert(section.id) }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                        .foregroundColor(.secondary)
                    Text(section.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text("\(section.files.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    if let subtitle = section.subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.97))
        .overlay(alignment: .bottom) { Divider() }
    }

    private func placeholder(icon: String, title: String, detail: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 36))
                .foregroundColor(.secondary.opacity(0.6))
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var setup: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Label("Connect to Canvas", systemImage: "graduationcap.fill")
                    .font(.title3.bold())
                Text("The app lists the files in your Canvas courses, including ones that are only linked from pages or modules, and shows which are new. Files you download go into the materials folder of the course you link in this tool's settings, or into Downloads.")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                CanvasConnectionForm()
            }
            .padding(24)
            .frame(maxWidth: 520, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Sections

    private var filesShown: [CanvasFileRecord] {
        let all = canvas.visibleFiles
        guard !search.isEmpty else { return all }
        return all.filter { file in
            file.name.localizedCaseInsensitiveContains(search)
                || (file.moduleName ?? "").localizedCaseInsensitiveContains(search)
                || courseLabel(file.courseID).localizedCaseInsensitiveContains(search)
        }
    }

    private var selectable: [CanvasFileRecord] {
        filesShown.filter { canvas.canDownload($0) }
    }

    private var selectedCount: Int {
        selectable.filter { selection.contains($0.id) }.count
    }

    private var allSelected: Bool {
        !selectable.isEmpty && selectable.allSatisfy { selection.contains($0.id) }
    }

    private func isWaiting(_ file: CanvasFileRecord) -> Bool {
        switch canvas.downloadState(of: file) {
        case .notDownloaded, .updateAvailable: return true
        case .downloaded, .locked: return false
        }
    }

    private var sections: [CanvasFileSection] {
        switch mode {
        case .byCourse: return courseSections
        case .byDate: return dateSections
        }
    }

    private var courseSections: [CanvasFileSection] {
        let shown = Dictionary(grouping: filesShown, by: \.courseID)
        return canvas.visibleCourses.compactMap { course in
            let files = shown[course.id] ?? []
            if !search.isEmpty && files.isEmpty { return nil }
            let sorted: [CanvasFileRecord]
            switch sort {
            case .name: sorted = files.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            case .newest: sorted = files.sorted { $0.effectiveDate() > $1.effectiveDate() }
            }
            return CanvasFileSection(
                id: "course-\(course.id)",
                title: course.displayName,
                subtitle: "Saves to \(canvas.destinationName(forCourse: course.id))",
                notice: canvas.notices[course.id],
                files: sorted
            )
        }
    }

    private var dateSections: [CanvasFileSection] {
        let now = Date()
        let calendar = Calendar.current
        var result: [CanvasFileSection] = []

        let upcoming = filesShown.filter { $0.isUpcoming(now: now) }.sorted { $0.effectiveDate(now: now) < $1.effectiveDate(now: now) }
        if !upcoming.isEmpty {
            result.append(CanvasFileSection(id: "upcoming", title: "Upcoming", subtitle: "Unlock later", files: upcoming))
        }

        let released = filesShown.filter { !$0.isUpcoming(now: now) }
        let dated = Dictionary(grouping: released.filter { $0.effectiveDate(now: now) != .distantPast }) {
            calendar.startOfDay(for: $0.effectiveDate(now: now))
        }
        for day in dated.keys.sorted(by: >) {
            let files = dated[day]!.sorted { $0.effectiveDate(now: now) > $1.effectiveDate(now: now) }
            result.append(CanvasFileSection(id: "day-\(day.timeIntervalSince1970)", title: dayTitle(day), files: files))
        }

        let undated = released.filter { $0.effectiveDate(now: now) == .distantPast }
        if !undated.isEmpty {
            result.append(CanvasFileSection(id: "undated", title: "No Date", files: undated.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }))
        }
        return result
    }

    private func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        let sameYear = calendar.isDate(day, equalTo: Date(), toGranularity: .year)
        return day.formatted(sameYear ? .dateTime.weekday(.wide).day().month(.wide) : .dateTime.weekday(.wide).day().month(.wide).year())
    }

    private func courseLabel(_ courseID: Int) -> String {
        guard let course = canvas.course(id: courseID) else { return "" }
        if let code = course.courseCode, !code.isEmpty { return code }
        return course.name
    }
}

// MARK: - Row

private struct CanvasFileRow: View {
    let file: CanvasFileRecord
    /// The course, shown when files from several courses are listed together.
    let courseLabel: String?
    @Binding var isSelected: Bool

    @ObservedObject private var canvas = CanvasSyncService.shared
    @State private var isHovered = false

    private var state: CanvasDownloadState { canvas.downloadState(of: file) }
    private var isDownloading: Bool { canvas.downloading.contains(file.id) }

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: $isSelected)
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(!canvas.canDownload(file))

            Image(systemName: LectureFile.systemIconName(forExtension: file.fileExtension))
                .foregroundColor(LectureFile.iconColor(forExtension: file.fileExtension))
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(file.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    reasonBadge
                }
                details
            }

            Spacer(minLength: 8)

            if let size = file.formattedSize {
                Text(size)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
            stateView
                .frame(minWidth: 130, alignment: .trailing)
        }
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .padding(.vertical, 6)
        .background(isHovered ? Color.accentColor.opacity(0.06) : Color.clear)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture(count: 2) { open() }
        .contextMenu { menu }
        .help(file.lockExplanation ?? file.name)
    }

    /// Why the file is on its date. Only shown for the last week, so older files stay quiet.
    @ViewBuilder
    private var reasonBadge: some View {
        let reason = file.reason()
        let recent = file.effectiveDate() > Date().addingTimeInterval(-7 * 24 * 3600)
        if reason == .upcoming || (recent && file.effectiveDate() != .distantPast) {
            Text(reason.rawValue)
                .font(.caption2.bold())
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .foregroundColor(color(for: reason))
                .background(Capsule().fill(color(for: reason).opacity(0.15)))
        }
    }

    private func color(for reason: CanvasFileReason) -> Color {
        switch reason {
        case .new: return .blue
        case .updated: return .orange
        case .released: return .green
        case .found: return .purple
        case .upcoming: return .secondary
        }
    }

    private var details: some View {
        HStack(spacing: 6) {
            if let courseLabel, !courseLabel.isEmpty {
                Text(courseLabel)
                    .font(.system(.caption, design: .monospaced))
            }
            if let module = file.moduleName {
                Label(module, systemImage: "square.stack")
                    .lineLimit(1)
            } else if file.source == .link {
                Label("Linked from course content", systemImage: "link")
            }
            let date = file.effectiveDate()
            if date != .distantPast {
                Text(date.formatted(date: .abbreviated, time: .shortened))
            }
        }
        .font(.caption)
        .foregroundColor(.secondary)
        .labelStyle(.titleAndIcon)
    }

    @ViewBuilder
    private var stateView: some View {
        if isDownloading {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Downloading").font(.caption).foregroundColor(.secondary)
            }
        } else {
            switch state {
            case .downloaded(let url):
                Button {
                    CourseStorageService.shared.revealInFinder(url: url)
                } label: {
                    Label("Downloaded", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .foregroundColor(.green)
                .font(.caption)
                .help("Show in Finder: \(url.path)")
            case .updateAvailable:
                Button {
                    Task { await canvas.download([file.id]) }
                } label: {
                    Label("Update", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.borderless)
                .foregroundColor(.orange)
                .font(.caption)
                .help("Canvas has a newer version. Downloading it moves the old copy to the Trash.")
            case .locked:
                Label(lockText, systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
            case .notDownloaded:
                Button {
                    Task { await canvas.download([file.id]) }
                } label: {
                    Label("Download", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
        }
    }

    private var lockText: String {
        if let unlockAt = file.unlockAt, unlockAt > Date() {
            return "Unlocks " + unlockAt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
        }
        return "Locked"
    }

    @ViewBuilder
    private var menu: some View {
        switch state {
        case .downloaded(let url), .updateAvailable(let url):
            Button("Open") { CourseStorageService.shared.openFile(url: url) }
            Button("Show in Finder") { CourseStorageService.shared.revealInFinder(url: url) }
            Button("Download Again") { Task { await canvas.download([file.id]) } }
        case .notDownloaded:
            Button("Download") { Task { await canvas.download([file.id]) } }
        case .locked:
            EmptyView()
        }
        if let url = canvas.webURL(for: file) {
            Divider()
            Button("Open in Canvas") { NSWorkspace.shared.open(url) }
        }
    }

    private func open() {
        switch state {
        case .downloaded(let url), .updateAvailable(let url):
            CourseStorageService.shared.openFile(url: url)
        case .notDownloaded:
            Task { await canvas.download([file.id]) }
        case .locked:
            break
        }
    }
}

/// The new-today count on the Canvas tool's home-screen card.
struct CanvasToolBadge: View {
    @ObservedObject private var canvas = CanvasSyncService.shared

    var body: some View {
        let count = canvas.newTodayCount
        if count > 0 {
            Text("\(count) new today")
                .font(.caption2.bold())
                .foregroundColor(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.red))
        }
    }
}
