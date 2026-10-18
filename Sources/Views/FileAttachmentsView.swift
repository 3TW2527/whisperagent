import SwiftUI
import UniformTypeIdentifiers
import AppKit

public enum FileViewMode: String, CaseIterable, Identifiable {
    case card = "Card"
    case list = "List"

    public var id: String { rawValue }
}

public struct FileAttachmentsView: View {
    public let course: Course
    public var onAudioDropped: (URL) -> Void

    @ObservedObject private var settings = AppSettings.shared
    @AppStorage("whisperlectures_file_view_mode") private var viewMode: FileViewMode = .card

    @State private var isTargeted = false
    @State private var selectedFileID: String?
    @State private var previewFile: LectureFile?
    @State private var isShowingQuickLook = false
    @State private var keyMonitor: Any?

    public init(course: Course, onAudioDropped: @escaping (URL) -> Void) {
        self.course = course
        self.onAudioDropped = onAudioDropped
    }

    private var activeSelectedFile: LectureFile? {
        if let id = selectedFileID, let file = course.materials.first(where: { $0.id == id }) {
            return file
        }
        return course.materials.first
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Action Mode & View Switcher Bar
            HStack(spacing: 12) {
                Text("File action:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Picker("", selection: $settings.fileIngestionAction) {
                    ForEach(FileIngestionAction.allCases) { action in
                        Text(action.rawValue).tag(action)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 140)

                Text(settings.fileIngestionAction == .copy ? "(Copies original)" : "(Moves into course)")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Spacer()

                // List / Card View Toggle
                Picker("View Mode", selection: $viewMode) {
                    Image(systemName: "square.grid.2x2")
                        .tag(FileViewMode.card)
                        .help("Card View")
                    Image(systemName: "list.bullet")
                        .tag(FileViewMode.list)
                        .help("List View")
                }
                .pickerStyle(.segmented)
                .frame(width: 180)

                Button {
                    selectAndAddFiles()
                } label: {
                    Label("Add Files...", systemImage: "plus")
                }
                .controlSize(.small)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Drop & File Content
            if course.materials.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 44))
                        .foregroundColor(isTargeted ? .accentColor : .secondary.opacity(0.6))

                    Text("Drop Course Materials Here")
                        .font(.headline)

                    Text("Drag & drop lecture slides (PDF, PPTX), notes, syllabus, or documents. Files will be \(settings.fileIngestionAction == .copy ? "copied" : "moved") into this course's materials folder.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 400)

                    Button("Choose Files...") {
                        selectAndAddFiles()
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(isTargeted ? Color.accentColor : Color.secondary.opacity(0.2), style: StrokeStyle(lineWidth: 2, dash: [8]))
                        .padding(24)
                )
            } else {
                Group {
                    if viewMode == .card {
                        cardGridView
                    } else {
                        fileListView
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(isTargeted ? Color.accentColor : Color.clear, lineWidth: 2)
                )
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            handleDroppedItems(providers)
            return true
        }
        .sheet(isPresented: $isShowingQuickLook) {
            if let file = previewFile ?? activeSelectedFile {
                QuickLookModal(fileURL: file.url) {
                    isShowingQuickLook = false
                    previewFile = nil
                }
            }
        }
        .onAppear {
            validateSelection()
            setupKeyMonitor()
        }
        .onDisappear {
            removeKeyMonitor()
        }
        .onChange(of: course.id) {
            validateSelection()
        }
        .onChange(of: course.materials) {
            validateSelection()
        }
        // Fallback spacebar shortcut trigger
        .background(
            Button("") {
                toggleQuickLook()
            }
            .keyboardShortcut(.space, modifiers: [])
            .opacity(0)
            .frame(width: 0, height: 0)
        )
    }

    // MARK: - Card View
    private var cardGridView: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 16)], spacing: 16) {
                ForEach(course.materials) { file in
                    FileCardView(
                        file: file,
                        isSelected: selectedFileID == file.id,
                        onSelect: {
                            selectedFileID = file.id
                        },
                        onOpenPreview: {
                            openQuickLook(for: file)
                        }
                    )
                }
            }
            .padding()
        }
    }

    // MARK: - List View
    private var fileListView: some View {
        VStack(spacing: 0) {
            // Header Row
            HStack(spacing: 12) {
                Text("Name")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 36)

                Text("Kind")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                    .frame(width: 150, alignment: .leading)

                Text("Date Modified")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                    .frame(width: 140, alignment: .leading)

                Text("Size")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                    .frame(width: 80, alignment: .trailing)
                    .padding(.trailing, 8)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(course.materials) { file in
                        FileListRowView(
                            file: file,
                            isSelected: selectedFileID == file.id,
                            onSelect: {
                                selectedFileID = file.id
                            },
                            onOpenPreview: {
                                openQuickLook(for: file)
                            }
                        )
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Selection & Navigation
    private func validateSelection() {
        if let currentID = selectedFileID, course.materials.contains(where: { $0.id == currentID }) {
            return
        }
        selectedFileID = course.materials.first?.id
    }

    private func openQuickLook(for file: LectureFile) {
        selectedFileID = file.id
        previewFile = file
        isShowingQuickLook = true
    }

    private func toggleQuickLook() {
        if isShowingQuickLook {
            isShowingQuickLook = false
            previewFile = nil
        } else if let target = activeSelectedFile {
            openQuickLook(for: target)
        }
    }

    private func navigateSelection(step: Int) {
        guard !course.materials.isEmpty else { return }
        let currentIndex = course.materials.firstIndex(where: { $0.id == selectedFileID }) ?? 0
        let nextIndex = min(max(0, currentIndex + step), course.materials.count - 1)
        let nextFile = course.materials[nextIndex]
        selectedFileID = nextFile.id

        // If Quick Look is currently open, dynamically update the previewed file like Finder
        if isShowingQuickLook {
            previewFile = nextFile
        }
    }

    private func setupKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Don't intercept if user is currently typing in an editable field
            if let responder = NSApp.keyWindow?.firstResponder, responder is NSTextView || responder is NSTextField {
                return event
            }

            switch event.keyCode {
            case 49: // Spacebar
                self.toggleQuickLook()
                return nil
            case 125, 124: // Down Arrow, Right Arrow
                self.navigateSelection(step: 1)
                return nil
            case 126, 123: // Up Arrow, Left Arrow
                self.navigateSelection(step: -1)
                return nil
            case 53: // Escape
                if self.isShowingQuickLook {
                    self.isShowingQuickLook = false
                    self.previewFile = nil
                    return nil
                }
            default:
                break
            }
            return event
        }
    }

    private func removeKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    // MARK: - Drag & Drop / File Addition
    private func handleDroppedItems(_ providers: [NSItemProvider]) {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url = url else { return }
                DispatchQueue.main.async {
                    if VoiceMemosService.shared.isAudioFile(url: url) {
                        onAudioDropped(url)
                    } else {
                        do {
                            _ = try CourseStorageService.shared.ingestMaterial(
                                from: url,
                                courseID: course.id,
                                action: settings.fileIngestionAction
                            )
                        } catch {
                            print("Failed to \(settings.fileIngestionAction.rawValue.lowercased()) dropped file: \(error)")
                        }
                    }
                }
            }
        }
    }

    private func selectAndAddFiles() {
        let panel = NSOpenPanel()
        panel.title = "Select Course Materials to Add"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true

        panel.begin { response in
            if response == .OK {
                for url in panel.urls {
                    if VoiceMemosService.shared.isAudioFile(url: url) {
                        onAudioDropped(url)
                    } else {
                        _ = try? CourseStorageService.shared.ingestMaterial(
                            from: url,
                            courseID: course.id,
                            action: settings.fileIngestionAction
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Card View Item
struct FileCardView: View {
    let file: LectureFile
    let isSelected: Bool
    let onSelect: () -> Void
    let onOpenPreview: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: file.systemIconName)
                .font(.system(size: 38))
                .foregroundColor(isSelected ? .accentColor : file.iconColor)
                .frame(height: 50)

            Text(file.name)
                .font(.caption.bold())
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundColor(isSelected ? .accentColor : .primary)

            Text(file.formattedSize)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(width: 150, height: 130)
        .padding(8)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.15), lineWidth: isSelected ? 2 : 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .onTapGesture(count: 2) {
            onOpenPreview()
        }
        .contextMenu {
            Button("Quick Look Preview (Space)") {
                onOpenPreview()
            }
            Button("Open with Default App") {
                CourseStorageService.shared.openFile(url: file.url)
            }
            Button("Reveal in Finder") {
                CourseStorageService.shared.revealInFinder(url: file.url)
            }
            Divider()
            Button("Delete", role: .destructive) {
                try? FileManager.default.removeItem(at: file.url)
                CourseStorageService.shared.reload()
            }
        }
    }
}

// MARK: - List View Item
struct FileListRowView: View {
    let file: LectureFile
    let isSelected: Bool
    let onSelect: () -> Void
    let onOpenPreview: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            // Icon & Name
            HStack(spacing: 8) {
                Image(systemName: file.systemIconName)
                    .font(.system(size: 18))
                    .foregroundColor(isSelected ? .white : file.iconColor)
                    .frame(width: 24)

                Text(file.name)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundColor(isSelected ? .white : .primary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Kind
            Text(file.kindDescription)
                .font(.caption)
                .foregroundColor(isSelected ? .white.opacity(0.85) : .secondary)
                .lineLimit(1)
                .frame(width: 150, alignment: .leading)

            // Modified Date
            Text(file.formattedModifiedDate)
                .font(.caption)
                .foregroundColor(isSelected ? .white.opacity(0.85) : .secondary)
                .lineLimit(1)
                .frame(width: 140, alignment: .leading)

            // Size
            Text(file.formattedSize)
                .font(.caption)
                .foregroundColor(isSelected ? .white.opacity(0.85) : .secondary)
                .frame(width: 80, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(
            Group {
                if isSelected {
                    Color.accentColor
                } else if isHovered {
                    Color.secondary.opacity(0.08)
                } else {
                    Color.clear
                }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            onSelect()
        }
        .onTapGesture(count: 2) {
            onOpenPreview()
        }
        .contextMenu {
            Button("Quick Look Preview (Space)") {
                onOpenPreview()
            }
            Button("Open with Default App") {
                CourseStorageService.shared.openFile(url: file.url)
            }
            Button("Reveal in Finder") {
                CourseStorageService.shared.revealInFinder(url: file.url)
            }
            Divider()
            Button("Delete", role: .destructive) {
                try? FileManager.default.removeItem(at: file.url)
                CourseStorageService.shared.reload()
            }
        }
    }
}
