import SwiftUI

/// Sidebar shown once a course is entered: a way back, the course's lectures, and its documents.
struct CourseSidebarView: View {
    let course: Course
    @ObservedObject var nav: CourseNavigation
    let onBack: () -> Void
    let onEditCourse: () -> Void

    @ObservedObject private var transcriptionService = WhisperTranscriptionService.shared

    var body: some View {
        VStack(spacing: 0) {
            header

            Picker("", selection: $nav.sidebarTab) {
                Text("Lectures (\(course.lectures.count))").tag(CourseNavigation.SidebarTab.lectures)
                Text("Documents (\(course.materials.count))").tag(CourseNavigation.SidebarTab.documents)
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
            }
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
                    Button("Course Settings...", action: onEditCourse)
                    Button("Reveal in Finder") { CourseStorageService.shared.revealInFinder(url: course.folderURL) }
                } label: {
                    Image(systemName: "gearshape")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Course settings: name, code, tags and location")
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
            .listStyle(.sidebar)
            .overlay {
                if course.lectures.isEmpty && course.unassignedRecordingGroups.isEmpty {
                    Text("No lectures yet")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Divider()
            Button {
                nav.isAddingLecture = true
            } label: {
                Label("New Lecture", systemImage: "plus")
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
                        Divider()
                        Button("Move to Trash", role: .destructive) { CourseStorageService.shared.deleteMaterial(file) }
                    }
                }
            }
            .listStyle(.sidebar)
            .overlay {
                if course.materials.isEmpty {
                    Text("No documents yet\nDrop files onto the bar above")
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
        panel.title = "Select Course Materials to Add"
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
        } else {
            VStack(spacing: 10) {
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 40))
                    .foregroundColor(.secondary.opacity(0.6))
                Text(course.materials.isEmpty ? "No documents yet" : "Select a document")
                    .font(.headline)
                Text("Drop slides, PDFs or readings onto the bar above to add them to this course.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
