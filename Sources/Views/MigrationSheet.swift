import SwiftUI

/// Moves folders from the old one-folder-per-lecture layout into courses. Nothing moves until the
/// user confirms, and each folder can be skipped.
public struct MigrationSheet: View {
    public var onDismiss: () -> Void

    @ObservedObject private var storage = CourseStorageService.shared
    @State private var choices: [URL: Choice] = [:]
    @State private var newCourseNames: [URL: String] = [:]
    @State private var errors: [String] = []
    @State private var isWorking = false

    enum Choice: Hashable {
        case skip
        case newCourse
        case existing(String)
    }

    public init(onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Organise Older Lecture Folders")
                .font(.title2.bold())
            Text("These folders use the old one-folder-per-lecture layout. Choose a course for each one. It becomes a new numbered lecture in that course: transcripts are renamed to the course naming scheme, and other files move to the course's materials. Choose Skip to leave a folder as it is.")
                .font(.callout)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(storage.legacyFolders, id: \.self) { folder in
                        row(for: folder)
                    }
                }
            }
            .frame(minHeight: 160, maxHeight: 360)

            if !errors.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(errors, id: \.self) { error in
                        Text(error).font(.caption).foregroundColor(.red)
                    }
                }
            }

            HStack {
                Text("Folders are processed in the order shown, so lecture numbers follow that order.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Close") { onDismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Organise") { migrate() }
                    .buttonStyle(.borderedProminent)
                    .disabled(isWorking || storage.legacyFolders.allSatisfy { (choices[$0] ?? .skip) == .skip })
            }
        }
        .padding(20)
        .frame(width: 640)
    }

    private func row(for folder: URL) -> some View {
        let binding = Binding<Choice>(
            get: { choices[folder] ?? .skip },
            set: { choices[folder] = $0 }
        )
        return HStack(spacing: 10) {
            Image(systemName: "folder")
                .foregroundColor(.secondary)
            Text(folder.lastPathComponent)
                .font(.subheadline)
                .lineLimit(1)
                .frame(width: 200, alignment: .leading)

            Picker("", selection: binding) {
                Text("Skip").tag(Choice.skip)
                Text("New course...").tag(Choice.newCourse)
                if !storage.courses.isEmpty {
                    Divider()
                    ForEach(storage.courses) { course in
                        Text(course.displayName).tag(Choice.existing(course.id))
                    }
                }
            }
            .labelsHidden()
            .frame(width: 200)

            if binding.wrappedValue == .newCourse {
                TextField("Course name", text: Binding(
                    get: { newCourseNames[folder] ?? "" },
                    set: { newCourseNames[folder] = $0 }
                ))
                .textFieldStyle(.roundedBorder)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func migrate() {
        isWorking = true
        errors = []
        // Folders mapped to the same new course name share one course.
        var createdCourses: [String: String] = [:]

        for folder in storage.legacyFolders {
            let choice = choices[folder] ?? .skip
            do {
                switch choice {
                case .skip:
                    continue
                case .existing(let courseID):
                    try storage.migrateLegacyFolder(folder, intoCourseID: courseID)
                case .newCourse:
                    let rawName = (newCourseNames[folder] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    let name = rawName.isEmpty ? "Imported Lectures" : rawName
                    let key = name.lowercased()
                    let courseID: String
                    if let existing = createdCourses[key] {
                        courseID = existing
                    } else if let created = storage.createCourse(name: name) {
                        courseID = created.id
                        createdCourses[key] = created.id
                    } else {
                        throw StorageError.courseNotFound
                    }
                    try storage.migrateLegacyFolder(folder, intoCourseID: courseID)
                }
            } catch {
                errors.append("\(folder.lastPathComponent): \(error.localizedDescription)")
            }
        }
        choices = [:]
        isWorking = false
        if errors.isEmpty && storage.legacyFolders.isEmpty {
            onDismiss()
        }
    }
}
