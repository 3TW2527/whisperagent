import SwiftUI

public struct MainView: View {
    @StateObject private var storage = ProjectStorageService.shared
    @ObservedObject private var transcriptionService = WhisperTranscriptionService.shared
    @ObservedObject private var settings = AppSettings.shared

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
            VStack(spacing: 0) {
                // Persistent Background Transcription Banner
                if let job = transcriptionService.activeJob {
                    ActiveJobBanner(job: job)
                } else if let completed = transcriptionService.recentCompletedJob {
                    CompletedJobBanner(job: completed) {
                        transcriptionService.recentCompletedJob = nil
                    }
                }

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

struct ActiveJobBanner: View {
    let job: TranscriptionJob

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform.circle.fill")
                .font(.title2)
                .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("Transcribing:")
                        .font(.subheadline.bold())
                    Text(job.originalFileName)
                        .font(.subheadline)
                        .lineLimit(1)
                    Text("• \(job.projectTitle)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 8) {
                    ProgressView(value: job.progressFraction)
                        .progressViewStyle(.linear)
                        .frame(maxWidth: 240)
                    Text(job.statusDescription)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Label("Background Task Active", systemImage: "arrow.triangle.2.circlepath")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.12))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color.accentColor.opacity(0.25)),
            alignment: .bottom
        )
    }
}

struct CompletedJobBanner: View {
    let job: TranscriptionJob
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text("Transcription Finished!")
                    .font(.subheadline.bold())
                Text("Saved transcript for \(job.projectTitle). Temporary audio was removed.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button("Dismiss") {
                onDismiss()
            }
            .buttonStyle(.plain)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.green.opacity(0.12))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color.green.opacity(0.25)),
            alignment: .bottom
        )
    }
}

// Extension to allow URL to be used with .sheet(item:)
extension URL: @retroactive Identifiable {
    public var id: String { self.absoluteString }
}
