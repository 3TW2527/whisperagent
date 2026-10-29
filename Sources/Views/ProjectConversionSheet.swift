import SwiftUI

/// Turns a course that has been used for meetings into a project. Shows exactly what will be renamed and moved
/// before anything changes.
struct ProjectConversionSheet: View {
    let course: Course
    let onDismiss: () -> Void

    @ObservedObject private var storage = CourseStorageService.shared
    @State private var root: URL
    @State private var code: String
    @State private var plan: CourseStorageService.ProjectConversionPlan?
    @State private var errorMessage: String?
    @State private var isConverting = false

    init(course: Course, onDismiss: @escaping () -> Void) {
        self.course = course
        self.onDismiss = onDismiss
        // A course kept in a folder of its own (e.g. Project/Meetings) most likely belongs to the folder around it.
        let initialRoot = course.isExternal ? course.folderURL.deletingLastPathComponent() : course.folderURL
        _root = State(initialValue: initialRoot)
        let suggested = course.metadata.code.isEmpty ? Self.initials(initialRoot.lastPathComponent) : course.metadata.code
        _code = State(initialValue: suggested)
    }

    private var movesUp: Bool { root.standardizedFileURL.path != course.folderURL.standardizedFileURL.path }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Convert to Project")
                    .font(.title2.bold())
                Text("\(course.displayName) becomes a project: lectures become meetings (M01, M02, ...) that can belong to series, with their own files, plus key dates and folders of your own work.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Form {
                LabeledContent("Project folder") {
                    HStack {
                        Text(root.path)
                            .lineLimit(1)
                            .truncationMode(.head)
                            .foregroundColor(.secondary)
                        Button("Change...") { chooseRoot() }
                            .controlSize(.small)
                    }
                }
                TextField("Code", text: $code, prompt: Text("e.g. CAP"))
            }
            .formStyle(.grouped)
            .onChange(of: code) { makePlan() }
            .onChange(of: root) { makePlan() }

            if let plan {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        summary(plan)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                }
                .frame(height: 300)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor)))
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            HStack {
                Text("Transcription jobs for this course must be finished first.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Cancel", role: .cancel) { onDismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Convert") { convert() }
                    .buttonStyle(.borderedProminent)
                    .disabled(plan == nil || isConverting)
            }
        }
        .padding(20)
        .frame(width: 600)
        .onAppear(perform: makePlan)
    }

    @ViewBuilder
    private func summary(_ plan: CourseStorageService.ProjectConversionPlan) -> some View {
        group("Folders") {
            if movesUp {
                bullet("The course's materials, notes, transcripts and settings move up from \(course.folderURL.lastPathComponent)/ into \(root.lastPathComponent)/, which becomes the project folder. \(course.folderURL.lastPathComponent)/ is removed once empty.")
            } else {
                bullet("\(root.lastPathComponent)/ stays where it is and becomes the project folder.")
            }
            bullet("A meetings/ folder is added for files from individual meetings. Everything already in materials/ stays there as project-wide material; move files to a meeting from its right-click menu.")
            bullet("Other folders in \(root.lastPathComponent)/ are left alone and shown under Files.")
        }
        group("Transcripts (\(plan.recordingRenames.count) renamed)") {
            ForEach(Array(plan.recordingRenames.enumerated()), id: \.offset) { _, rename in
                renameRow(rename.0, rename.1)
            }
            if plan.recordingRenames.isEmpty { bullet("Nothing to rename.") }
        }
        group("Notes (\(plan.noteRenames.count) renamed, links updated)") {
            ForEach(Array(plan.noteRenames.enumerated()), id: \.offset) { _, rename in
                renameRow(rename.0, rename.1)
            }
            if plan.noteRenames.isEmpty { bullet("Nothing to rename.") }
        }
        group("Meeting series found in titles") {
            if plan.series.isEmpty {
                bullet("None. You can add series in the project's settings.")
            }
            ForEach(plan.series) { series in
                let count = course.lectures.filter { $0.title.lowercased().hasPrefix(series.name.lowercased() + " ") }.count
                bullet("\(series.name): \(count) meeting\(count == 1 ? "" : "s")\(series.scheduleDescription.map { ", usually \($0)" } ?? "")")
            }
            if !plan.titlesCleared.isEmpty {
                bullet("Titles like \"Team Meeting 2\" are cleared so they keep numbering themselves within their series.")
            }
        }
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.bold())
            content()
        }
    }

    private func bullet(_ text: String) -> some View {
        Text("• " + text)
            .font(.caption)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func renameRow(_ from: String, _ to: String) -> some View {
        HStack(spacing: 6) {
            Text(from).foregroundColor(.secondary)
            Image(systemName: "arrow.right")
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(to)
        }
        .font(.system(.caption, design: .monospaced))
        .lineLimit(1)
    }

    private func makePlan() {
        do {
            plan = try storage.planProjectConversion(courseID: course.id, root: root, code: code)
            errorMessage = nil
        } catch {
            plan = nil
            errorMessage = error.localizedDescription
        }
    }

    private func chooseRoot() {
        let panel = NSOpenPanel()
        panel.title = "Choose the project folder"
        panel.message = "Choose the course's own folder, or a folder that contains it."
        panel.prompt = "Use This Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.directoryURL = root
        if panel.runModal() == .OK, let url = panel.url {
            root = url
        }
    }

    private func convert() {
        guard let plan else { return }
        isConverting = true
        do {
            try storage.convertToProject(courseID: course.id, plan: plan)
            onDismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isConverting = false
    }

    /// `CAP` for "CAP", `CP` for "Capstone Project".
    static func initials(_ name: String) -> String {
        let words = name.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        if words.count == 1, let word = words.first, word.count <= 6 { return String(word).uppercased() }
        return String(words.compactMap(\.first)).uppercased()
    }
}
