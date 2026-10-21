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

/// Markdown note editor with a live preview (LaTeX, wikilinks) and PDF export.
struct NoteEditorView: View {
    let course: Course
    let note: NoteFile
    let onWikilink: (WikilinkTarget) -> Void

    @AppStorage("whisperlectures_note_mode") private var mode: NoteViewMode = .split
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

    private var linkContext: WikilinkContext { WikilinkContext(course: course) }

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
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(note.name)
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
                Button("Open with Default App") { CourseStorageService.shared.openFile(url: note.url) }
                Button("Reveal in Finder") { CourseStorageService.shared.revealInFinder(url: note.url) }
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
        text = (try? String(contentsOf: note.url, encoding: .utf8)) ?? ""
        lastSaved = text
        isLoaded = true
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
        // The note may have been renamed or deleted while this view was closing.
        guard FileManager.default.fileExists(atPath: note.url.path) else { return }
        do {
            try CourseStorageService.shared.writeNote(note, text: text)
            lastSaved = text
            savedAt = Date()
            errorMessage = nil
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
        panel.nameFieldStringValue = "\(note.name).pdf"
        panel.directoryURL = course.folderURL
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
