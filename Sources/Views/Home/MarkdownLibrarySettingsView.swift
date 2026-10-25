import SwiftUI

/// The Markdown Library's settings: which folders it reads. Shown from the tool's gear and in Settings → Tools.
struct MarkdownLibrarySettingsView: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Folders")
                .font(.subheadline.bold())

            Text("The library lists every Markdown file in these folders, including subfolders. Removing a folder only removes it from the list; its files stay where they are.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 0) {
                if settings.markdownFolderPaths.isEmpty {
                    Text("No folders added")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                ForEach(settings.markdownFolderPaths, id: \.self) { path in
                    HStack {
                        Image(systemName: FileManager.default.fileExists(atPath: path) ? "folder" : "exclamationmark.triangle")
                            .foregroundColor(FileManager.default.fileExists(atPath: path) ? .accentColor : .orange)
                        Text(path)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(path)
                        Spacer()
                        Button {
                            MarkdownLibraryService.shared.removeFolder(id: path)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Remove from the Markdown Library")
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
            }
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Button("Add Folder...") {
                promptForMarkdownFolders()
            }
        }
    }
}

/// Asks for one or more folders and adds them to the Markdown Library.
@MainActor
func promptForMarkdownFolders() {
    let panel = NSOpenPanel()
    panel.title = "Add a Folder to the Markdown Library"
    panel.prompt = "Add Folder"
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.canCreateDirectories = true
    panel.allowsMultipleSelection = true
    guard panel.runModal() == .OK else { return }
    for url in panel.urls {
        MarkdownLibraryService.shared.addFolder(url)
    }
}
