import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// How to point popular AI assistants at the study library and start asking questions.
///
/// Terminal agents read the folder directly, and pick up the generated AGENTS.md / CLAUDE.md /
/// GEMINI.md automatically. Chat apps that only take uploads get a single-file study bundle instead.
public struct AskAIView: View {
    public let initialCourseID: String?
    public var onDismiss: () -> Void

    @ObservedObject private var storage = CourseStorageService.shared
    @ObservedObject private var settings = AppSettings.shared
    @State private var scopeCourseID: String?
    @State private var provider: AIProvider = .claudeCode
    @State private var exportMessage: String?

    public init(initialCourseID: String?, onDismiss: @escaping () -> Void) {
        self.initialCourseID = initialCourseID
        self.onDismiss = onDismiss
        _scopeCourseID = State(initialValue: initialCourseID)
    }

    private var scopeCourse: Course? {
        scopeCourseID.flatMap { storage.course(id: $0) }
    }

    private var scopeURL: URL {
        scopeCourse?.folderURL ?? settings.rootFolderURL
    }

    private var scopeName: String {
        scopeCourse?.name ?? "my courses"
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HSplitView {
                List(selection: Binding(get: { provider }, set: { if let p = $0 { provider = p } })) {
                    ForEach(AIProvider.Group.allCases, id: \.self) { group in
                        Section(group.rawValue) {
                            ForEach(AIProvider.allCases.filter { $0.group == group }) { item in
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.title)
                                    Text(item.vendor)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                .tag(item)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
                .frame(minWidth: 200, idealWidth: 220, maxWidth: 260)

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        providerGuide
                        Divider()
                        starterPrompts
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minWidth: 400)
            }
            Divider()
            HStack {
                Text("Tools and plans change often. Check each provider's own docs if a step doesn't match what you see.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Done") { onDismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(minWidth: 780, idealWidth: 900, maxWidth: 1000, minHeight: 480, idealHeight: 660, maxHeight: 800)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Ask an AI About Your Courses", systemImage: "sparkles")
                    .font(.title2.bold())
                Spacer()
                Picker("Scope", selection: $scopeCourseID) {
                    Text("Whole library").tag(String?.none)
                    Divider()
                    ForEach(storage.courses) { course in
                        Text(course.displayName).tag(Optional(course.id))
                    }
                }
                .frame(width: 280)
            }

            HStack(spacing: 8) {
                Image(systemName: "folder")
                    .foregroundColor(.secondary)
                Text(scopeURL.path)
                    .font(.system(.callout, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Spacer()
                CopyButton(text: scopeURL.path, label: "Copy Path")
                Button {
                    storage.revealInFinder(url: scopeURL)
                } label: {
                    Image(systemName: "arrow.up.forward.square")
                }
                .help("Reveal in Finder")
                Button {
                    exportBundle()
                } label: {
                    Label("Export Study Bundle...", systemImage: "square.and.arrow.up")
                }
                .help("Combine transcripts into one Markdown file for apps that only accept uploads")
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            if let exportMessage {
                Text(exportMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
    }

    // MARK: - Guides

    private var quotedPath: String {
        "'" + scopeURL.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private var samplePrompt: String {
        scopeCourse == nil
            ? "Read INDEX.md, then summarise what each of my courses has covered so far."
            : "Read COURSE.md, then summarise each lecture in 3 bullet points with timestamps."
    }

    @ViewBuilder
    private var providerGuide: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(provider.title)
                .font(.title3.bold())
            Text(provider.summary)
                .font(.callout)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        switch provider {
        case .claudeCode:
            GuideStep(number: 1, title: "Install Claude Code (once)", detail: "Needs a Claude Pro, Max, Team or Enterprise plan, or an Anthropic Console account. Homebrew users can run `brew install --cask claude-code` instead.") {
                CommandBlock(command: "curl -fsSL https://claude.ai/install.sh | bash")
            }
            GuideStep(number: 2, title: "Open your library", detail: "Claude Code reads CLAUDE.md from this folder automatically, so it already knows the layout. The first run signs you in through your browser.") {
                CommandBlock(command: "cd \(quotedPath) && claude")
            }
            GuideStep(number: 3, title: "Or ask a single question without a session", detail: nil) {
                CommandBlock(command: "cd \(quotedPath) && claude -p \"\(samplePrompt)\"")
            }
            DocsLink(title: "Claude Code setup docs", url: "https://code.claude.com/docs/en/setup")

        case .claudeDesktop:
            GuideStep(number: 1, title: "Option A: Cowork in the Claude desktop app", detail: "Cowork can read the files in a folder you choose. Start a Cowork task, grant access to the folder below, then ask your question. Cowork is a research preview on paid plans, so if you don't see it, update the app.") {
                CommandBlock(command: scopeURL.path, label: "Folder to grant")
            }
            GuideStep(number: 2, title: "Option B: a claude.ai Project", detail: "Create a Project for the course and add the study bundle (Export Study Bundle above) to its knowledge, along with any slide PDFs. Each chat in that Project can then use them.") {
                EmptyView()
            }
            DocsLink(title: "Cowork overview", url: "https://claude.com/cowork")

        case .codex:
            GuideStep(number: 1, title: "Install Codex CLI (once)", detail: "Or use `brew install --cask codex`. Sign in with your ChatGPT account when it first starts.") {
                CommandBlock(command: "npm install -g @openai/codex")
            }
            GuideStep(number: 2, title: "Open your library", detail: "Codex reads AGENTS.md from the folder, which describes the layout and how to cite lectures.") {
                CommandBlock(command: "cd \(quotedPath) && codex")
            }
            GuideStep(number: 3, title: "Or ask a single question non-interactively", detail: nil) {
                CommandBlock(command: "cd \(quotedPath) && codex exec \"\(samplePrompt)\"")
            }
            DocsLink(title: "Codex on GitHub", url: "https://github.com/openai/codex")

        case .chatGPT:
            GuideStep(number: 1, title: "Export a study bundle", detail: "Use Export Study Bundle above to save one Markdown file that has every transcript in the course. A single file stays well within per-project file limits.") {
                EmptyView()
            }
            GuideStep(number: 2, title: "Create a ChatGPT Project", detail: "In ChatGPT (web or desktop app), create a Project for the course and add the bundle to its files, along with slide PDFs from the course's materials folder. The number of files allowed per project depends on your plan.") {
                EmptyView()
            }
            GuideStep(number: 3, title: "Add instructions to the Project (optional)", detail: "Paste this into the Project's instructions so answers cite their sources:") {
                CommandBlock(command: "Answer from the uploaded lecture transcripts and materials. Cite sources as <lecture> [mm:ss] or <file> page N. The transcripts are automatic and may mishear technical terms, so check them against the slides.", label: "Instructions")
            }

        case .antigravity:
            GuideStep(number: 1, title: "Install Antigravity CLI (once)", detail: "Google replaced Gemini CLI with Antigravity CLI (`agy`) for free and Google One users on 18 June 2026. Download it from Google's site.") {
                EmptyView()
            }
            DocsLink(title: "Antigravity download", url: "https://antigravity.google/download")
            GuideStep(number: 2, title: "Open your library", detail: "Antigravity reads the AGENTS.md and GEMINI.md context files in this folder.") {
                CommandBlock(command: "cd \(quotedPath) && agy")
            }
            GuideStep(number: 3, title: "Still on Gemini CLI?", detail: "Paid and API-key users can keep using Gemini CLI. It reads GEMINI.md, and `-p` asks a single question.") {
                CommandBlock(command: "cd \(quotedPath) && gemini -p \"\(samplePrompt)\"")
            }

        case .notebookLM:
            GuideStep(number: 1, title: "Export a study bundle", detail: "Use Export Study Bundle above. Gemini Notebook accepts Markdown, text and PDF sources, and one bundle uses only one source slot.") {
                EmptyView()
            }
            GuideStep(number: 2, title: "Create a notebook", detail: "Create a notebook for the course in Gemini Notebook, then add the bundle and the slide PDFs from the materials folder as sources. Its answers link back to the exact passages in each source. The number of sources per notebook depends on your plan.") {
                EmptyView()
            }
            DocsLink(title: "Gemini Notebook", url: "https://notebooklm.google.com")

        case .otherAgents:
            GuideStep(number: 1, title: "Open the folder in any tool that reads AGENTS.md", detail: "AGENTS.md is a shared convention that many coding agents and AI editors read. Open the folder below as the project or workspace, and the agent gets the library layout and citation rules from that file.") {
                CommandBlock(command: scopeURL.path, label: "Folder")
            }
            GuideStep(number: 2, title: "Customise the instructions (optional)", detail: "To write your own AGENTS.md, CLAUDE.md or GEMINI.md, delete the first line (the \"Generated by WhisperLectures\" comment). The app then stops overwriting that file.") {
                EmptyView()
            }
        }
    }

    private var starterPrompts: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Questions to Try")
                .font(.headline)
            ForEach(StarterPrompt.all(courseName: scopeName), id: \.self) { prompt in
                HStack(alignment: .top) {
                    Text(prompt)
                        .font(.callout)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    CopyButton(text: prompt, label: nil)
                }
                .padding(8)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    // MARK: - Export

    private func exportBundle() {
        let courses = scopeCourse.map { [$0] } ?? storage.courses
        guard !courses.isEmpty else {
            exportMessage = "There are no courses to export yet."
            return
        }
        let panel = NSSavePanel()
        panel.title = "Export Study Bundle"
        panel.nameFieldStringValue = "\(scopeCourse?.name ?? "Study Library") - study bundle.md"
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let text = StudyBundleExporter.bundle(for: courses)
                try text.write(to: url, atomically: true, encoding: .utf8)
                let words = text.split { $0.isWhitespace || $0.isNewline }.count
                exportMessage = "Saved \(url.lastPathComponent) (about \(words.formatted()) words)."
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch {
                exportMessage = "Export failed: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Providers

enum AIProvider: String, CaseIterable, Identifiable, Hashable {
    case claudeCode, claudeDesktop, codex, chatGPT, antigravity, notebookLM, otherAgents

    enum Group: String, CaseIterable {
        case reads = "Reads the folder directly"
        case uploads = "Upload a bundle"
        case other = "Other"
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .claudeDesktop: return "Claude Desktop / claude.ai"
        case .codex: return "Codex CLI"
        case .chatGPT: return "ChatGPT"
        case .antigravity: return "Antigravity / Gemini CLI"
        case .notebookLM: return "Gemini Notebook"
        case .otherAgents: return "Other AI agents"
        }
    }

    var vendor: String {
        switch self {
        case .claudeCode, .claudeDesktop: return "Anthropic"
        case .codex, .chatGPT: return "OpenAI"
        case .antigravity, .notebookLM: return "Google"
        case .otherAgents: return "Cursor, Copilot, and others"
        }
    }

    var group: Group {
        switch self {
        case .claudeCode, .codex, .antigravity, .claudeDesktop: return .reads
        case .chatGPT, .notebookLM: return .uploads
        case .otherAgents: return .other
        }
    }

    var summary: String {
        switch self {
        case .claudeCode:
            return "A terminal agent that can search and read the whole library, including transcripts and materials, and only opens what it needs. Best for questions across many lectures or courses."
        case .claudeDesktop:
            return "Use the Claude desktop app with folder access (Cowork), or upload a bundle to a claude.ai Project."
        case .codex:
            return "OpenAI's terminal agent. Sign in with your ChatGPT plan. It searches and reads the library folder directly."
        case .chatGPT:
            return "Upload a single study bundle to a ChatGPT Project, then chat about the course in any conversation in that Project."
        case .antigravity:
            return "Google's terminal agent (formerly Gemini CLI). It reads the library folder directly."
        case .notebookLM:
            return "Google's source-grounded notebook. Answers cite the passages they came from, and it can make study guides and audio overviews. Good for revision."
        case .otherAgents:
            return "Any agent or AI editor that reads AGENTS.md can use the library as a workspace."
        }
    }
}

enum StarterPrompt {
    static func all(courseName: String) -> [String] {
        [
            "Summarise every lecture of \(courseName) in 3–5 bullet points each, with timestamps for the main topics.",
            "Make revision notes for \(courseName), grouped by topic rather than by lecture. Cite each point as L<n> [mm:ss].",
            "What did the lecturer say about <topic>? Quote the relevant parts of the transcript and cite them.",
            "Write 10 exam-style questions on \(courseName) with model answers, and say which lecture covers each one.",
            "Which topics from the slides in materials/ were never discussed in the lectures?",
            "Explain <concept> as simply as you can, using the lecturer's own examples."
        ]
    }
}

// MARK: - Components

struct GuideStep<Content: View>: View {
    let number: Int
    let title: String
    let detail: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption.bold())
                .foregroundColor(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.accentColor))
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.subheadline.bold())
                if let detail {
                    Text(.init(detail))
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                content()
            }
        }
    }
}

struct CommandBlock: View {
    let command: String
    var label: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let label {
                Text(label)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            HStack(alignment: .top) {
                Text(command)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                CopyButton(text: command, label: nil)
            }
            .padding(10)
            .background(Color(NSColor.textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2)))
        }
    }
}

struct CopyButton: View {
    let text: String
    let label: String?
    @State private var copied = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
        } label: {
            if let label {
                Label(copied ? "Copied" : label, systemImage: copied ? "checkmark" : "doc.on.doc")
            } else {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
            }
        }
        .buttonStyle(.borderless)
        .help("Copy")
    }
}

struct DocsLink: View {
    let title: String
    let url: String

    var body: some View {
        if let link = URL(string: url) {
            Link(destination: link) {
                Label(title, systemImage: "arrow.up.right.square")
                    .font(.caption)
            }
            .padding(.leading, 34)
        }
    }
}
