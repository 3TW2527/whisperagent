import SwiftUI
import UniformTypeIdentifiers

enum NoteViewMode: String, CaseIterable, Identifiable {
    case edit, split, preview

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .edit: return "pencil"
        case .split: return "rectangle.split.2x1"
        case .preview: return "eye"
        }
    }

    var label: String {
        switch self {
        case .edit: return "Edit"
        case .split: return "Edit and preview side by side"
        case .preview: return "Preview"
        }
    }
}

/// A course note: the shared Markdown editor wired to the course's notes, lectures and files.
struct NoteEditorView: View {
    let course: Course
    let note: NoteFile
    let onWikilink: (WikilinkTarget) -> Void

    var body: some View {
        MarkdownDocumentEditor(
            fileURL: note.url,
            title: note.name,
            linkContext: WikilinkContext(course: course),
            exportDirectory: course.folderURL,
            onWikilink: onWikilink,
            // A project's actions come from its notes, so they're re-read after each save.
            onSaved: course.isProject ? { [id = course.id] in CourseStorageService.shared.refresh(courseID: id) } : nil
        )
    }
}

/// Markdown editor for any `.md` file, with a live preview (LaTeX, wikilinks), autosave and PDF export.
/// Used for course notes and for files in the Markdown Library.
///
/// Changes made to the file elsewhere (the phone notepad, ticking an action, another app) are picked up every
/// couple of seconds: with no unsaved edits the file is reloaded, and text added to its end is kept alongside
/// unsaved edits.
struct MarkdownDocumentEditor: View {
    let fileURL: URL
    let title: String
    let linkContext: WikilinkContext
    let exportDirectory: URL
    let onWikilink: (WikilinkTarget) -> Void
    var onSaved: (() -> Void)?

    @AppStorage private var mode: NoteViewMode
    @State private var text = ""
    @State private var lastSaved = ""
    @State private var isLoaded = false
    @State private var saveTask: Task<Void, Never>?
    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @State private var isExporting = false
    @State private var savedAt: Date?
    @State private var isShowingHelp = false
    @State private var editorController = MarkdownEditorController()
    /// When the file was last read or written here, to notice changes made elsewhere.
    @State private var knownModificationDate: Date?

    /// `modeKey` keeps the edit/split/preview choice separate per place the editor is used.
    init(
        fileURL: URL,
        title: String,
        linkContext: WikilinkContext,
        exportDirectory: URL,
        modeKey: String = "whisperlectures_note_mode",
        defaultMode: NoteViewMode = .split,
        onWikilink: @escaping (WikilinkTarget) -> Void,
        onSaved: (() -> Void)? = nil
    ) {
        self.fileURL = fileURL
        self.title = title
        self.linkContext = linkContext
        self.exportDirectory = exportDirectory
        self.onWikilink = onWikilink
        self.onSaved = onSaved
        self._mode = AppStorage(wrappedValue: defaultMode, modeKey)
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal)
                    .padding(.bottom, 6)
            }
            Divider()
            content
        }
        .onAppear(perform: load)
        .onDisappear(perform: flush)
        .onChange(of: text) { scheduleSave() }
        .task(id: fileURL) {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                checkForOutsideChanges()
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                if let statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                } else {
                    saveIndicator
                }
            }

            Spacer()

            Picker("View", selection: $mode) {
                ForEach(NoteViewMode.allCases) { mode in
                    Image(systemName: mode.icon).help(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 120)

            Button {
                isShowingHelp = true
            } label: {
                Image(systemName: "questionmark.circle")
            }
            .buttonStyle(.borderless)
            .help("Markdown, LaTeX and wikilink help")
            .popover(isPresented: $isShowingHelp, arrowEdge: .bottom) {
                NoteHelpView(context: linkContext, canInsertAtCursor: editorController.isAvailable) { snippet, cursorBack in
                    insert(snippet, cursorBack: cursorBack)
                }
            }

            Button {
                exportPDF()
            } label: {
                Label("Export PDF", systemImage: "arrow.down.doc")
            }
            .disabled(isExporting)

            Menu {
                Button("Open with Default App") { CourseStorageService.shared.openFile(url: fileURL) }
                Button("Reveal in Finder") { CourseStorageService.shared.revealInFinder(url: fileURL) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private var saveIndicator: some View {
        let isDirty = isLoaded && text != lastSaved
        return Label(
            isDirty ? "Saving..." : (savedAt.map { "Saved at \(Self.timeFormatter.string(from: $0))" } ?? "All changes saved"),
            systemImage: isDirty ? "ellipsis.circle" : "checkmark.circle.fill"
        )
        .font(.caption)
        .foregroundColor(isDirty ? .secondary : .green)
        .lineLimit(1)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .none
        return formatter
    }()

    private func insert(_ snippet: String, cursorBack: Int) {
        if editorController.isAvailable {
            editorController.insert(snippet, cursorBack: cursorBack)
        } else {
            // Preview-only mode has no cursor; add to the end instead.
            text += (text.hasSuffix("\n") || text.isEmpty ? "" : "\n") + snippet
        }
    }

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .edit:
            MarkdownEditorView(text: $text, controller: editorController)
        case .preview:
            preview
        case .split:
            HSplitView {
                MarkdownEditorView(text: $text, controller: editorController)
                    .frame(minWidth: 220, maxWidth: .infinity, maxHeight: .infinity)
                preview
                    .frame(minWidth: 220, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var preview: some View {
        MarkdownPreviewView(markdown: text, context: linkContext, onWikilink: onWikilink)
    }

    // MARK: - Saving

    private func load() {
        guard !isLoaded else { return }
        text = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
        lastSaved = text
        knownModificationDate = modificationDate()
        isLoaded = true
    }

    private func modificationDate() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.modificationDate] as? Date
    }

    /// Takes in what was written to the file elsewhere since it was last read or saved here.
    private func checkForOutsideChanges() {
        guard isLoaded, let date = modificationDate(), date != knownModificationDate else { return }
        knownModificationDate = date
        guard let disk = try? String(contentsOf: fileURL, encoding: .utf8), disk != lastSaved else { return }
        if text == lastSaved {
            text = disk
            lastSaved = disk
        } else if disk.hasPrefix(lastSaved) {
            // Added to the end elsewhere (e.g. from the phone) while there are unsaved edits here: keep both.
            text += disk.dropFirst(lastSaved.count)
            lastSaved = disk
        } else {
            statusMessage = "This note was also changed elsewhere. Your version here will be saved."
            lastSaved = disk
        }
    }

    private func scheduleSave() {
        guard isLoaded, text != lastSaved else { return }
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            if !Task.isCancelled { flush() }
        }
    }

    private func flush() {
        saveTask?.cancel()
        guard isLoaded, text != lastSaved else { return }
        // The file may have been renamed or deleted while this view was closing.
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            try text.write(to: fileURL, atomically: true, encoding: .utf8)
            lastSaved = text
            knownModificationDate = modificationDate()
            savedAt = Date()
            errorMessage = nil
            onSaved?()
        } catch {
            errorMessage = "Could not save: \(error.localizedDescription)"
        }
    }

    // MARK: - Export

    private func exportPDF() {
        flush()
        let panel = NSSavePanel()
        panel.title = "Export Note as PDF"
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "\(title).pdf"
        panel.directoryURL = exportDirectory
        guard panel.runModal() == .OK, let url = panel.url else { return }

        isExporting = true
        errorMessage = nil
        statusMessage = "Exporting PDF..."
        let markdown = text
        let context = linkContext
        Task {
            do {
                try await NotePDFExporter.export(markdown: markdown, context: context, to: url)
                statusMessage = "Exported \(url.lastPathComponent)"
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch {
                statusMessage = nil
                errorMessage = "PDF export failed: \(error.localizedDescription)"
            }
            isExporting = false
        }
    }
}
