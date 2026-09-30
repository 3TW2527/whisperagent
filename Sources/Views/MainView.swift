import SwiftUI

public struct MainView: View {
    @StateObject private var storage = ProjectStorageService.shared
    @StateObject private var settings = AppSettings.shared

    @State private var searchText = ""
    @State private var isShowingNewProjectAlert = false
    @State private var newProjectTitle = ""
    @State private var isShowingSettings = false
    @State private var pendingAudioURL: URL?

    public init() {}

    public var filteredProjects: [LectureProject] {
        if searchText.isEmpty {
            return storage.projects
        } else {
            return storage.projects.filter {
                $0.title.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    public var body: some View {
        NavigationSplitView {
            // Sidebar: Project List
            VStack(spacing: 0) {
                List(selection: $storage.selectedProject) {
                    Section("Lecture Projects") {
                        ForEach(filteredProjects) { project in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(project.title)
                                    .font(.headline)
                                    .lineLimit(1)

                                HStack {
                                    Text(project.formattedDate)
                                    Spacer()
                                    if project.transcripts.count > 0 {
                                        Label("\(project.transcripts.count)", systemImage: "doc.text")
                                    }
                                    if project.files.count > 0 {
                                        Label("\(project.files.count)", systemImage: "paperclip")
                                    }
                                }
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                            .tag(project)
                            .contextMenu {
                                Button("Reveal in Finder") {
                                    storage.revealInFinder(url: project.folderURL)
                                }
                                Divider()
                                Button("Delete Project", role: .destructive) {
                                    storage.deleteProject(project)
                                }
                            }
                        }
                    }
                }
                .searchable(text: $searchText, prompt: "Search lectures...")
                .listStyle(.sidebar)

                Divider()

                // Sidebar Bottom Bar
                HStack {
                    Button {
                        isShowingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .buttonStyle(.plain)
                    .help("Settings & Models")

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(spacing: 4) {
                            Image(systemName: settings.isUsingiCloud ? "icloud.fill" : "folder.fill")
                                .foregroundColor(settings.isUsingiCloud ? .blue : .secondary)
                                .font(.caption2)
                            Text(settings.isUsingiCloud ? "iCloud Drive" : "Local")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(10)
                .background(Color(NSColor.controlBackgroundColor))
            }
            .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 360)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        newProjectTitle = "Lecture \(storage.projects.count + 1)"
                        isShowingNewProjectAlert = true
                    } label: {
                        Label("New Lecture", systemImage: "plus")
                    }
                }
            }
        } detail: {
            // Detail Area
            if let selected = storage.selectedProject {
                ProjectDetailView(project: selected) { audioURL in
                    self.pendingAudioURL = audioURL
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "graduationcap")
                        .font(.system(size: 56))
                        .foregroundColor(.secondary.opacity(0.5))

                    Text("No Lecture Selected")
                        .font(.title2.bold())

                    Text("Select a lecture project from the sidebar or create a new one.")
                        .font(.callout)
                        .foregroundColor(.secondary)

                    Button("Create New Lecture") {
                        newProjectTitle = "Lecture \(storage.projects.count + 1)"
                        isShowingNewProjectAlert = true
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(item: $pendingAudioURL) { audioURL in
            if let selectedProject = storage.selectedProject {
                AudioTrimmerSheet(audioURL: audioURL, project: selectedProject) {
                    self.pendingAudioURL = nil
                }
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView {
                isShowingSettings = false
            }
        }
        .alert("New Lecture Project", isPresented: $isShowingNewProjectAlert) {
            TextField("Lecture Name (e.g. CS101 - Lecture 01)", text: $newProjectTitle)
            Button("Create") {
                if let created = storage.createProject(named: newProjectTitle) {
                    storage.selectedProject = created
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter a title for the new lecture. A corresponding folder will be created in your configured storage path.")
        }
    }
}

// Extension to allow URL to be used with .sheet(item:)
extension URL: Identifiable {
    public var id: String { self.absoluteString }
}
