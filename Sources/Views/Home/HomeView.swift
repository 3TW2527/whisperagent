import SwiftUI

/// A lecture from any course, as listed under Recent Lectures.
struct RecentLecture: Identifiable {
    let course: Course
    let lecture: Lecture

    var id: String { "\(course.id)#\(lecture.number)" }

    var recordingCount: Int { course.recordingGroups(for: lecture).count }
    var noteCount: Int { course.notes.filter { $0.lectureNumber == lecture.number }.count }
    var totalDuration: Double { lecture.recordings.reduce(0) { $0 + $1.durationSeconds } }
}

/// Shown when no course is open: the latest lectures across all courses, then the tools.
struct HomeView: View {
    let onOpenLecture: (Course, Int) -> Void
    let onOpenTool: (HomeTool) -> Void
    let onNewCourse: () -> Void

    @ObservedObject private var storage = CourseStorageService.shared
    @ObservedObject private var settings = AppSettings.shared

    /// Newest first. Lectures dated after today are scheduled ones that haven't happened yet, so they're left out.
    private var recentLectures: [RecentLecture] {
        let endOfToday = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date())) ?? Date()
        let all = storage.courses.flatMap { course in
            course.lectures.filter { $0.date < endOfToday }.map { RecentLecture(course: course, lecture: $0) }
        }
        return Array(all.sorted { $0.lecture.date > $1.lecture.date }.prefix(settings.recentLectureCount))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                recentSection
                toolsSection
            }
            .padding(24)
            .frame(maxWidth: 880, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Home")
                    .font(.largeTitle.bold())
                Text(librarySummary)
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button {
                onNewCourse()
            } label: {
                Label("New Course", systemImage: "plus")
            }
        }
    }

    private var librarySummary: String {
        let courses = storage.courses.count
        let lectures = storage.courses.reduce(0) { $0 + $1.lectures.count }
        let notes = storage.courses.reduce(0) { $0 + $1.notes.count }
        func plural(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n == 1 ? "" : "s")" }
        return [plural(courses, "course"), plural(lectures, "lecture"), plural(notes, "note")].joined(separator: " · ")
    }

    // MARK: - Recent Lectures

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Recent Lectures", detail: recentLectures.isEmpty ? nil : "Showing \(recentLectures.count).")

            if recentLectures.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "list.number")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary.opacity(0.6))
                    Text(storage.courses.isEmpty ? "Create your first course to get started" : "No lectures yet")
                        .font(.headline)
                    Text("Each course holds numbered lectures with their transcripts and notes, plus shared materials like slides and readings. The latest lectures from every course show up here.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                    if storage.courses.isEmpty {
                        Button("New Course", action: onNewCourse)
                            .buttonStyle(.borderedProminent)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(24)
                .background(cardBackground)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(recentLectures.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { Divider().padding(.leading, 14) }
                        RecentLectureRow(item: item) {
                            onOpenLecture(item.course, item.lecture.number)
                        }
                    }
                }
                .background(cardBackground)
            }
        }
    }

    // MARK: - Tools

    private var toolsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Tools", detail: nil)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 12)], spacing: 12) {
                ForEach(HomeTool.all) { tool in
                    ToolCard(tool: tool) { onOpenTool(tool) }
                }
                comingSoonCard
            }
        }
    }

    private var comingSoonCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "puzzlepiece.extension")
                .font(.title2)
                .foregroundColor(.secondary)
            Text("More tools")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("New tools will appear here.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .padding(14)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        )
    }

    private func sectionTitle(_ title: String, detail: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title3.bold())
            Spacer()
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color(NSColor.controlBackgroundColor))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08)))
    }
}

private struct RecentLectureRow: View {
    let item: RecentLecture
    let onOpen: () -> Void

    @ObservedObject private var transcriptionService = WhisperTranscriptionService.shared
    @State private var isHovered = false

    private var runningCount: Int {
        transcriptionService.activeJobs.filter { $0.courseID == item.course.id && $0.lectureNumber == item.lecture.number }.count
    }

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(item.lecture.label)
                            .font(.system(.caption, design: .monospaced).bold())
                            .foregroundColor(.accentColor)
                        Text(item.lecture.title.isEmpty ? "Lecture \(item.lecture.number)" : item.lecture.title)
                            .font(.headline)
                            .lineLimit(1)
                    }
                    HStack(spacing: 6) {
                        if !item.course.metadata.code.isEmpty {
                            Text(item.course.metadata.code)
                                .font(.system(.caption, design: .monospaced))
                        }
                        Text(item.course.name)
                            .lineLimit(1)
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }

                Spacer(minLength: 12)

                HStack(spacing: 12) {
                    if runningCount > 0 {
                        Label("Transcribing", systemImage: "waveform")
                            .foregroundColor(.accentColor)
                    }
                    stat("doc.text", item.recordingCount, help: "Recordings")
                    if item.totalDuration > 0 {
                        Label(TranscriptFormatter.clock(item.totalDuration), systemImage: "clock")
                            .help("Total recorded time")
                    }
                    stat("note.text", item.noteCount, help: "Notes")
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .labelStyle(.titleAndIcon)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(item.lecture.date, format: .relative(presentation: .named))
                        .font(.caption.bold())
                    Text(DateFormats.display.string(from: item.lecture.date))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(minWidth: 120, alignment: .trailing)

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .background(isHovered ? Color.accentColor.opacity(0.08) : Color.clear)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .contextMenu {
            Button("Open Lecture", action: onOpen)
            Button("Reveal Course in Finder") { CourseStorageService.shared.revealInFinder(url: item.course.folderURL) }
        }
    }

    private func stat(_ icon: String, _ count: Int, help: String) -> some View {
        Label("\(count)", systemImage: icon)
            .opacity(count == 0 ? 0.5 : 1)
            .help(help)
    }
}

private struct ToolCard: View {
    let tool: HomeTool
    let onOpen: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    Image(systemName: tool.systemImage)
                        .font(.title2)
                        .foregroundColor(tool.tint)
                    Spacer()
                    tool.makeBadge?()
                }
                Text(tool.title)
                    .font(.headline)
                Text(tool.summary)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isHovered ? tool.tint.opacity(0.10) : Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isHovered ? tool.tint.opacity(0.5) : Color.primary.opacity(0.08))
            )
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
