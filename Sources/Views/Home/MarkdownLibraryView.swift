import SwiftUI

/// Home-screen tool: the Markdown files in the folders the user added, listed beside the note editor.
struct MarkdownLibraryView: View {
    @ObservedObject private var library = MarkdownLibraryService.shared

    /// Path of the open file, remembered between launches.
    @AppStorage("whisperlectures_library_selection") private var selectedPath = ""
    @State private var search = ""
    @State private var collapsedFolders: Set<String> = []
    @State private var renamingDocument: MarkdownDocument?
    @State private var renameText = ""
    @State private var deletingDocument: MarkdownDocument?
    @State private var errorMessage: String?

    private var selection: Binding<String?> {
        Binding(get: { selectedPath.isEmpty ? nil : selectedPath }, set: { selectedPath = $0 ?? "" })
    }

    private var selectedDocument: MarkdownDocument? {
        selectedPath.isEmpty ? nil : library.document(id: selectedPath)
    }

    var body: some View {
        Group {
            if library.folders.isEmpty && AppSettings.shared.markdownFolderPaths.isEmpty {
                emptyLibrary
            } else {
                HSplitView {
                    bar
                        .frame(minWidth: 180, idealWidth: 240, maxWidth: 360)
                    detail
                        .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .onAppear { library.reload() }
        // Picks up files added or changed in other apps.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            library.reload()
        }
        .alert("Rename File", isPresented: Binding(get: { renamingDocument != nil }, set: { if !$0 { renamingDocument = nil } })) {
            TextField("Name", text: $renameText)
            Button("Rename") { rename() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Links like [[old name]] in other files won't be updated.")
        }
        .confirmationDialog("Delete \(deletingDocument?.name ?? "file")?", isPresented: Binding(get: { deletingDocument != nil }, set: { if !$0 { deletingDocument = nil } })) {
            Button("Move File to Trash", role: .destructive) { delete() }
        }
    }

    // MARK: - Bar

    private var bar: some View {
        VStack(spacing: 0) {
            TextField("Filter files", text: $search)
                .textFieldStyle(.roundedBorder)
                .padding(8)

            List(selection: selection) {
                ForEach(library.folders) { folder in
                    Section(isExpanded: Binding(
                        get: { !collapsedFolders.contains(folder.id) || !search.isEmpty },
                        set: { isExpanded in
                            if isExpanded { collapsedFolders.remove(folder.id) } else { collapsedFolders.insert(folder.id) }
                        }
                    )) {
                        folderContents(folder)
                    } header: {
                        folderHeader(folder)
                    }
                }
            }
            .listStyle(.sidebar)

            Divider()
            HStack {
                Button {
                    promptForMarkdownFolders()
                } label: {
                    Label("Add Folder...", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                Spacer()
                if library.isScanning {
                    ProgressView().controlSize(.small)
                }
                Button {
                    library.reload()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Rescan folders")
            }
            .padding(8)
        }
    }

    @ViewBuilder
    private func folderContents(_ folder: MarkdownFolder) -> some View {
        let documents = filtered(folder.documents)
        if folder.isMissing {
            Label("Folder not found", systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundColor(.orange)
        } else if documents.isEmpty {
            Text(search.isEmpty ? "No Markdown files" : "No matches")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        ForEach(documents) { document in
            DocumentRow(document: document)
                .tag(document.id)
                .contextMenu {
                    Button("Rename...") {
                        renameText = document.name
                        renamingDocument = document
                    }
                    Button("New File Next to This...") { createDocument(in: document.url.deletingLastPathComponent()) }
                    Divider()
                    Button("Open with Default App") { CourseStorageService.shared.openFile(url: document.url) }
                    Button("Reveal in Finder") { CourseStorageService.shared.revealInFinder(url: document.url) }
                    Divider()
                    Button("Delete...", role: .destructive) { deletingDocument = document }
                }
        }
        if folder.isTruncated {
            Text("Showing the first \(MarkdownLibraryService.maxFilesPerFolder) files")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private func folderHeader(_ folder: MarkdownFolder) -> some View {
        HStack(spacing: 4) {
            Text(folder.name)
                .lineLimit(1)
                .help(folder.url.path)
            Spacer()
            Button {
                createDocument(in: folder.url)
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .disabled(folder.isMissing)
            .help("New Markdown file in \(folder.name)")
            Menu {
                Button("Reveal in Finder") { NSWorkspace.shared.open(folder.url) }
                Divider()
                Button("Remove from Library") { library.removeFolder(id: folder.id) }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("The folder's files stay where they are when you remove it")
        }
    }

    private func filtered(_ documents: [MarkdownDocument]) -> [MarkdownDocument] {
        guard !search.isEmpty else { return documents }
        return documents.filter { $0.relativePath.localizedCaseInsensitiveContains(search) }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        VStack(spacing: 0) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(8)
            }
            if let document = selectedDocument, let folder = library.folder(containing: document) {
                MarkdownDocumentEditor(
                    fileURL: document.url,
                    title: document.name,
                    linkContext: WikilinkContext(notes: folder.documents.map(\.name)),
                    exportDirectory: document.url.deletingLastPathComponent(),
                    modeKey: "whisperlectures_library_mode",
                    defaultMode: .preview,
                    onWikilink: { follow($0, in: folder) }
                )
                .id(document.id)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary.opacity(0.6))
                    Text("Select a file")
                        .font(.headline)
                    Text("Files open in preview. Switch to edit or side-by-side with the buttons at the top right.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 320)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var emptyLibrary: some View {
        VStack(spacing: 16) {
            Image(systemName: "books.vertical")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.6))
            Text("Add a Folder of Markdown Files")
                .font(.title3.bold())
            Text("The app remembers the folders you add and lists every Markdown file inside them, including subfolders. Files stay where they are; edits save straight back to them.")
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Button {
                promptForMarkdownFolders()
            } label: {
                Label("Add Folder...", systemImage: "folder.badge.plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    /// `[[Name]]` opens the file of that name in the same folder. A missing one is created, as with course notes.
    private func follow(_ target: WikilinkTarget, in folder: MarkdownFolder) {
        switch target {
        case .note(let name):
            if let document = folder.documents.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                selectedPath = document.id
            }
        case .missing(let name):
            do {
                selectedPath = try library.createDocument(in: folder.url, title: name).path
            } catch {
                errorMessage = error.localizedDescription
            }
        case .lecture, .file:
            break
        }
    }

    private func createDocument(in directory: URL) {
        do {
            selectedPath = try library.createDocument(in: directory, title: "Untitled").path
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func rename() {
        guard let document = renamingDocument else { return }
        do {
            let url = try library.rename(document, to: renameText)
            if selectedPath == document.id { selectedPath = url.path }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete() {
        guard let document = deletingDocument else { return }
        do {
            try library.delete(document)
            if selectedPath == document.id { selectedPath = "" }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct DocumentRow: View {
    let document: MarkdownDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Label(document.name, systemImage: "doc.text")
                .font(.subheadline)
                .lineLimit(1)
            if !document.subfolder.isEmpty {
                Text(document.subfolder)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .padding(.leading, 22)
            }
        }
        .help(document.relativePath)
    }
}
