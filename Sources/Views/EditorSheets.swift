import SwiftUI

/// Creates a new course, or edits an existing one when `course` is set.
public struct CourseEditorSheet: View {
    public let course: Course?
    public var onDismiss: () -> Void

    @ObservedObject private var storage = CourseStorageService.shared
    @State private var name = ""
    @State private var code = ""
    @State private var tagsText = ""
    /// The course's own folder when it is kept outside the library. Nil means the library folder.
    @State private var customLocation: URL?
    @State private var errorMessage: String?

    public init(course: Course? = nil, onDismiss: @escaping () -> Void) {
        self.course = course
        self.onDismiss = onDismiss
    }

    private var isEditing: Bool { course != nil }

    private var parsedTags: [String] { CourseStorageService.parseTags(tagsText) }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isEditing ? "Edit Course" : "New Course")
                .font(.title2.bold())

            Form {
                TextField("Name", text: $name, prompt: Text("e.g. Introduction to Algorithms"))
                TextField("Code (optional)", text: $code, prompt: Text("e.g. CS101"))
                TextField("Tags", text: $tagsText, prompt: Text("Comma-separated, e.g. semester-1, maths"))
            }
            .formStyle(.grouped)

            locationSection

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

            Text("Transcripts are named after the course code, or the name if there's no code, e.g. `\(Course.slug(code.isEmpty ? (name.isEmpty ? "Course" : name) : code))_L01_R1.md`.")
                .font(.caption)
                .foregroundColor(.secondary)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { onDismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isEditing ? "Save" : "Create Course") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 480)
        .onAppear {
            if let course {
                name = course.metadata.name
                code = course.metadata.code
                tagsText = course.tags.joined(separator: ", ")
                customLocation = course.isExternal ? course.folderURL : nil
            }
        }
    }

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
            Text(customLocation?.path ?? "\(AppSettings.shared.rootFolderURL.path)/ (a folder named after the course)")
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            if customLocation != nil {
                Text(isEditing ? "The course's files are moved into this folder. It must be empty." : "The course's files go directly in this folder. It must be empty.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func chooseLocation() {
        let panel = NSOpenPanel()
        panel.title = "Choose the folder for this course"
        panel.message = "The course's files go directly in the folder you choose, so pick or create an empty one."
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
        if let course {
            do {
                let newID = try storage.updateCourse(id: course.id, name: name, code: code, tags: parsedTags)
                try storage.moveCourse(id: newID, to: customLocation)
                onDismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        } else if let customLocation, !CourseStorageService.isUsableCourseFolder(customLocation) {
            errorMessage = StorageError.destinationNotEmpty.localizedDescription
        } else if storage.createCourse(name: name, code: code, tags: parsedTags, location: customLocation) != nil {
            onDismiss()
        } else {
            errorMessage = "Could not create the course folder. Check the storage location in Settings."
        }
    }
}

/// Creates a new lecture (numbered automatically), or edits one when `lecture` is set.
public struct LectureEditorSheet: View {
    public let course: Course
    public let lecture: Lecture?
    public var onSaved: (Lecture?) -> Void
    public var onDismiss: () -> Void

    @ObservedObject private var storage = CourseStorageService.shared
    @State private var title = ""
    @State private var date = Date()
    @State private var errorMessage: String?

    public init(course: Course, lecture: Lecture? = nil, onSaved: @escaping (Lecture?) -> Void = { _ in }, onDismiss: @escaping () -> Void) {
        self.course = course
        self.lecture = lecture
        self.onSaved = onSaved
        self.onDismiss = onDismiss
    }

    private var number: Int { lecture?.number ?? course.metadata.nextLectureNumber }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(lecture == nil ? "New Lecture" : "Edit Lecture")
                    .font(.title2.bold())
                Text("\(course.displayName) · Lecture \(number)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Form {
                TextField("Title (optional)", text: $title, prompt: Text("e.g. Sorting and Searching"))
                DatePicker("Date & time", selection: $date)
            }
            .formStyle(.grouped)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { onDismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(lecture == nil ? "Create Lecture" : "Save") { save() }
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

    private func save() {
        do {
            if let lecture {
                try storage.updateLecture(courseID: course.id, number: lecture.number, title: title, date: date)
                onSaved(nil)
            } else {
                let created = try storage.addLecture(courseID: course.id, title: title, date: date)
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
