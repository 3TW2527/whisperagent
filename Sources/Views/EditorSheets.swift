import SwiftUI

/// Creates a new course or project, or edits an existing one when `course` is set.
public struct CourseEditorSheet: View {
    public let course: Course?
    public var onDismiss: () -> Void

    @ObservedObject private var storage = CourseStorageService.shared
    @State private var kind: CourseKind
    @State private var name = ""
    @State private var code = ""
    @State private var tagsText = ""
    /// The course's own folder when it is kept outside the library. Nil means the library folder.
    @State private var customLocation: URL?
    @State private var series: [SeriesDraft] = []
    @State private var keyDates: [KeyDate] = []
    @State private var errorMessage: String?

    public init(course: Course? = nil, kind: CourseKind = .course, onDismiss: @escaping () -> Void) {
        self.course = course
        self.onDismiss = onDismiss
        _kind = State(initialValue: course?.kind ?? kind)
    }

    private var isEditing: Bool { course != nil }

    private var parsedTags: [String] { CourseStorageService.parseTags(tagsText) }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(isEditing ? "Edit \(kind.displayName)" : "New \(kind.displayName)")
                    .font(.title2.bold())
                Spacer()
                if !isEditing {
                    Picker("", selection: $kind) {
                        ForEach(CourseKind.allCases) { kind in
                            Label(kind.displayName, systemImage: kind.systemImage).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 200)
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !isEditing {
                        Text(kind == .project
                             ? "A project has recurring meetings with their own notes, recordings and files, project-wide materials, key dates, and folders of your own work."
                             : "A course has numbered lectures with transcripts and notes, plus materials shared by all of them.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Form {
                        TextField("Name", text: $name, prompt: Text(kind == .project ? "e.g. Capstone Project" : "e.g. Introduction to Algorithms"))
                        TextField("Code (optional)", text: $code, prompt: Text(kind == .project ? "e.g. CAP" : "e.g. CS101"))
                        TextField("Tags", text: $tagsText, prompt: Text("Comma-separated, e.g. semester-1, maths"))
                    }
                    .formStyle(.grouped)

                    tagsSection

                    if kind == .project {
                        seriesSection
                        keyDatesSection
                    }

                    locationSection

                    Text("Transcripts are named after the code, or the name if there's no code, e.g. `\(Course.slug(code.isEmpty ? (name.isEmpty ? kind.displayName : name) : code))_\(Lecture.label(number: 1, kind: kind))_R1.md`.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxHeight: 560)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { onDismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isEditing ? "Save" : "Create \(kind.displayName)") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 540)
        .onAppear {
            if let course {
                name = course.metadata.name
                code = course.metadata.code
                tagsText = course.tags.joined(separator: ", ")
                customLocation = course.isExternal ? course.folderURL : nil
                series = course.metadata.series.map(SeriesDraft.init)
                keyDates = course.metadata.keyDates
            }
        }
    }

    @ViewBuilder
    private var tagsSection: some View {
        if !parsedTags.isEmpty {
            HStack(spacing: 6) {
                ForEach(parsedTags, id: \.self) { tag in
                    TagChip(tag: tag)
                }
            }
        }

        if !storage.allTags.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Existing tags (click to add)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                WrappingHStack(items: storage.allTags.filter { tag in !parsedTags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame } }) { tag in
                    Button {
                        tagsText = (parsedTags + [tag]).joined(separator: ", ")
                    } label: {
                        TagChip(tag: tag, isSelected: false)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Series and Key Dates

    private var seriesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("Meeting series", add: "Add Series") {
                series.append(SeriesDraft(MeetingSeries(name: "")))
            }
            Text("Kinds of meeting that repeat, e.g. a Team meeting every Monday at 10:00. A new meeting can pick its series, which sets its usual day and time and numbers it within the series.")
                .font(.caption2)
                .foregroundColor(.secondary)
            ForEach($series) { $item in
                HStack(spacing: 8) {
                    TextField("Name, e.g. Team", text: $item.name)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)
                    Picker("", selection: $item.weekday) {
                        Text("Any day").tag(Int?.none)
                        ForEach(SeriesDraft.weekdayOrder, id: \.self) { day in
                            Text(Calendar.current.weekdaySymbols[day - 1]).tag(Int?.some(day))
                        }
                    }
                    .labelsHidden()
                    .frame(width: 120)
                    if item.weekday != nil {
                        DatePicker("", selection: $item.time, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                    }
                    Spacer()
                    Button {
                        series.removeAll { $0.id == item.id }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Remove this series. Its meetings keep their series name.")
                }
            }
        }
    }

    private var keyDatesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("Key dates", add: "Add Date") {
                keyDates.append(KeyDate(title: "", date: Calendar.current.startOfDay(for: Date())))
            }
            Text("Deadlines and reviews. They show on the home screen and in PROJECT.md.")
                .font(.caption2)
                .foregroundColor(.secondary)
            ForEach($keyDates) { $item in
                HStack(spacing: 8) {
                    TextField("e.g. Final presentation", text: $item.title)
                        .textFieldStyle(.roundedBorder)
                    DatePicker("", selection: $item.date, displayedComponents: .date)
                        .labelsHidden()
                    Button {
                        keyDates.removeAll { $0.id == item.id }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    private func sectionHeader(_ title: String, add: String, action: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
                .font(.caption.bold())
                .foregroundColor(.secondary)
            Spacer()
            Button(action: action) {
                Label(add, systemImage: "plus")
            }
            .controlSize(.small)
        }
    }

    // MARK: - Location

    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Location")
                .font(.caption.bold())
                .foregroundColor(.secondary)
            HStack(spacing: 8) {
                Picker("", selection: Binding(
                    get: { customLocation == nil },
                    set: { inLibrary in
                        if inLibrary { customLocation = nil } else { chooseLocation() }
                    }
                )) {
                    Text("Library folder").tag(true)
                    Text("Another folder...").tag(false)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 280)

                if customLocation != nil {
                    Button("Change...") { chooseLocation() }
                        .controlSize(.small)
                }
            }
            Text(customLocation?.path ?? "\(AppSettings.shared.rootFolderURL.path)/ (a folder named after the \(kind.displayName.lowercased()))")
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            if customLocation != nil {
                Text(locationNote)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var locationNote: String {
        if isEditing { return "The \(kind.displayName.lowercased())'s files are moved into this folder. It must be empty." }
        if kind == .project {
            return "This folder becomes the project's root. Files already in it stay where they are and appear under Files; the app adds materials, meetings, notes and transcripts folders."
        }
        return "The course's files go directly in this folder. It must be empty."
    }

    private func chooseLocation() {
        let panel = NSOpenPanel()
        let adopting = kind == .project && !isEditing
        panel.title = "Choose the folder for this \(kind.displayName.lowercased())"
        panel.message = adopting
            ? "Choose the project's folder. It can already hold your files."
            : "The \(kind.displayName.lowercased())'s files go directly in the folder you choose, so pick or create an empty one."
        panel.prompt = "Use This Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = customLocation?.deletingLastPathComponent() ?? AppSettings.shared.rootFolderURL
        if panel.runModal() == .OK, let url = panel.url {
            customLocation = url
        }
    }

    private func save() {
        let plan = series.map(\.series)
        if let course {
            do {
                let newID = try storage.updateCourse(id: course.id, name: name, code: code, tags: parsedTags)
                let movedID = try storage.moveCourse(id: newID, to: customLocation)
                if kind == .project {
                    try storage.updateProjectPlan(id: movedID, series: plan, keyDates: keyDates)
                }
                onDismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        } else if let customLocation, !CourseStorageService.isUsableFolder(customLocation, for: kind) {
            errorMessage = (kind == .project ? StorageError.projectFolderTaken : StorageError.destinationNotEmpty).localizedDescription
        } else if let created = storage.createCourse(kind: kind, name: name, code: code, tags: parsedTags, location: customLocation) {
            if kind == .project {
                try? storage.updateProjectPlan(id: created.id, series: plan, keyDates: keyDates)
            }
            onDismiss()
        } else {
            errorMessage = "Could not create the \(kind.displayName.lowercased()) folder. Check the storage location in Settings."
        }
    }
}

/// A meeting series being edited, with a stable id so rows don't jump while the name is typed.
private struct SeriesDraft: Identifiable {
    /// Monday first.
    static let weekdayOrder = [2, 3, 4, 5, 6, 7, 1]

    let id = UUID()
    var name: String
    var weekday: Int?
    var time: Date

    init(_ series: MeetingSeries) {
        name = series.name
        weekday = series.weekday
        let minutes = series.minuteOfDay ?? 9 * 60
        time = Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
    }

    var series: MeetingSeries {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
        return MeetingSeries(name: name, weekday: weekday, minuteOfDay: weekday == nil ? nil : (parts.hour ?? 0) * 60 + (parts.minute ?? 0))
    }
}

/// Creates a new lecture or meeting (numbered automatically), or edits one when `lecture` is set.
public struct LectureEditorSheet: View {
    public let course: Course
    public let lecture: Lecture?
    public var onSaved: (Lecture?) -> Void
    public var onDismiss: () -> Void

    @ObservedObject private var storage = CourseStorageService.shared
    @State private var title = ""
    @State private var date = Date()
    @State private var series: String?
    @State private var errorMessage: String?

    public init(course: Course, lecture: Lecture? = nil, initialSeries: String? = nil, onSaved: @escaping (Lecture?) -> Void = { _ in }, onDismiss: @escaping () -> Void) {
        self.course = course
        self.lecture = lecture
        self.onSaved = onSaved
        self.onDismiss = onDismiss
        _series = State(initialValue: lecture?.series ?? initialSeries)
        if lecture == nil, let start = initialSeries.flatMap({ name in course.metadata.series.first { $0.name == name } })?.nextOccurrence() {
            _date = State(initialValue: start)
        }
    }

    private var number: Int { lecture?.number ?? course.metadata.nextLectureNumber }
    private var unit: String { course.kind.unitName }

    /// Series to offer: the project's, plus this meeting's own if it was removed from the list.
    private var seriesNames: [String] {
        var names = course.metadata.series.map(\.name)
        if let own = lecture?.series, !names.contains(own) { names.append(own) }
        return names
    }

    /// What an untitled meeting will be called, e.g. "Team Meeting 3".
    private var defaultTitle: String? {
        guard let series else { return nil }
        let earlier = course.lectures.filter { $0.series == series && $0.number != lecture?.number && ($0.date, $0.number) < (date, number) }
        return MeetingSeries.meetingTitle(series: series, index: earlier.count + 1)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(lecture == nil ? "New \(unit)" : "Edit \(unit)")
                    .font(.title2.bold())
                Text("\(course.displayName) · \(unit) \(number)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Form {
                if course.isProject && !seriesNames.isEmpty {
                    Picker("Series", selection: $series) {
                        Text("None").tag(String?.none)
                        ForEach(seriesNames, id: \.self) { name in
                            Text(name).tag(String?.some(name))
                        }
                    }
                    .onChange(of: series) { applyUsualSlot() }
                }
                TextField("Title (optional)", text: $title, prompt: Text(defaultTitle ?? (course.isProject ? "e.g. Sub-team sync" : "e.g. Sorting and Searching")))
                DatePicker("Date & time", selection: $date)
            }
            .formStyle(.grouped)

            if let defaultTitle, title.trimmingCharacters(in: .whitespaces).isEmpty {
                Text("Without a title it's shown as \(defaultTitle).")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if course.isProject && seriesNames.isEmpty {
                Text("Add meeting series, such as a weekly Team meeting, in the project's settings.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { onDismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(lecture == nil ? "Create \(unit)" : "Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
        .onAppear {
            if let lecture {
                title = lecture.title
                date = lecture.date
            }
        }
    }

    /// A new meeting moves to its series' usual day and time (today's slot on the meeting day itself).
    private func applyUsualSlot() {
        guard lecture == nil, let series, let start = course.metadata.series.first(where: { $0.name == series })?.nextOccurrence() else { return }
        date = start
    }

    private func save() {
        do {
            if let lecture {
                try storage.updateLecture(courseID: course.id, number: lecture.number, title: title, date: date, series: series)
                onSaved(nil)
            } else {
                let created = try storage.addLecture(courseID: course.id, title: title, date: date, series: series)
                onSaved(created)
            }
            onDismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Small Shared Components

public struct TagChip: View {
    public let tag: String
    public var isSelected: Bool = true

    public init(tag: String, isSelected: Bool = true) {
        self.tag = tag
        self.isSelected = isSelected
    }

    public var body: some View {
        Text(tag)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(isSelected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12))
            .foregroundColor(isSelected ? .accentColor : .secondary)
            .clipShape(Capsule())
    }
}

/// Lays out items left to right, wrapping onto new lines.
public struct WrappingHStack<Item: Hashable, Content: View>: View {
    let items: [Item]
    let spacing: CGFloat
    let content: (Item) -> Content

    public init(items: [Item], spacing: CGFloat = 6, @ViewBuilder content: @escaping (Item) -> Content) {
        self.items = items
        self.spacing = spacing
        self.content = content
    }

    public var body: some View {
        FlowLayout(spacing: spacing) {
            ForEach(items, id: \.self) { content($0) }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews: subviews, width: proposal.width ?? .infinity)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews: subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let extra = rows[rows.count - 1].indices.isEmpty ? size.width : size.width + spacing
            if rows[rows.count - 1].width + extra > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            let isFirst = rows[rows.count - 1].indices.isEmpty
            rows[rows.count - 1].indices.append(index)
            rows[rows.count - 1].width += isFirst ? size.width : size.width + spacing
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
        }
        return rows
    }
}
