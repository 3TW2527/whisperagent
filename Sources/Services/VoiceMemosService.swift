import Foundation
import AppKit
import UniformTypeIdentifiers

public final class VoiceMemosService: Sendable {
    public static let shared = VoiceMemosService()

    private init() {}

    public static let supportedAudioExtensions: Set<String> = [
        "m4a", "mp3", "wav", "aac", "caf", "flac", "aiff", "aif"
    ]

    /// Checks if a given file URL is an audio recording
    public func isAudioFile(url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return Self.supportedAudioExtensions.contains(ext)
    }

    /// Launches or brings macOS Voice Memos app to the foreground so the user can drag recordings straight into WhisperLectures
    public func openVoiceMemosApp() {
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.VoiceMemos") {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: appURL, configuration: config) { _, error in
                if let error = error {
                    print("Could not open Voice Memos app: \(error)")
                }
            }
        } else {
            // Fallback try by path
            let voiceMemosURL = URL(fileURLWithPath: "/System/Applications/VoiceMemos.app")
            if FileManager.default.fileExists(atPath: voiceMemosURL.path) {
                NSWorkspace.shared.open(voiceMemosURL)
            }
        }
    }

    // MARK: - Drops

    /// The types a drop target should accept so recordings can come straight from apps that hand over the audio
    /// itself instead of a file on disk (e.g. Voice Memos, which drags a file promise rather than a file URL).
    public static let droppableTypes: [UTType] = [.fileURL, .audio]

    /// Turns one dropped item into a file on disk: a dragged file is used where it is, and dragged audio data is
    /// saved into `droppedRecordingsFolder` first. Calls `completion` on the main actor, with nil if nothing usable came.
    public func loadDroppedFile(from provider: NSItemProvider, completion: @escaping @MainActor @Sendable (URL?) -> Void) {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                Task { @MainActor in completion(url) }
            }
            return
        }

        let audioType = provider.registeredTypeIdentifiers
            .compactMap { UTType($0) }
            .first { $0.conforms(to: .audio) }
        guard let audioType else {
            Task { @MainActor in completion(nil) }
            return
        }

        let suggestedName = provider.suggestedName
        provider.loadFileRepresentation(forTypeIdentifier: audioType.identifier) { tempURL, _ in
            // The temporary file is deleted once this closure returns, so keep a copy before hopping queues.
            let saved = tempURL.flatMap { try? self.keepDroppedRecording($0, suggestedName: suggestedName, type: audioType) }
            Task { @MainActor in completion(saved) }
        }
    }

    /// Where recordings dropped as data are kept until they are transcribed.
    public var droppedRecordingsFolder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Dropped Recordings", isDirectory: true)
    }

    /// Whether `url` is a copy this service made of a recording dropped as data, rather than the user's own file.
    public func isDroppedRecordingCopy(_ url: URL) -> Bool {
        url.standardizedFileURL.deletingLastPathComponent().path == droppedRecordingsFolder.standardizedFileURL.path
    }

    private func keepDroppedRecording(_ tempURL: URL, suggestedName: String?, type: UTType) throws -> URL {
        let fileManager = FileManager.default
        let folder = droppedRecordingsFolder
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        removeOldDroppedRecordings(in: folder)

        var ext = tempURL.pathExtension
        if ext.isEmpty { ext = type.preferredFilenameExtension ?? "m4a" }
        var name = (suggestedName ?? tempURL.deletingPathExtension().lastPathComponent)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if name.lowercased().hasSuffix(".\(ext.lowercased())") { name = String(name.dropLast(ext.count + 1)) }
        if name.isEmpty { name = "Recording" }

        var destination = folder.appendingPathComponent(name).appendingPathExtension(ext)
        var counter = 2
        while fileManager.fileExists(atPath: destination.path) {
            destination = folder.appendingPathComponent("\(name) \(counter)").appendingPathExtension(ext)
            counter += 1
        }
        try fileManager.copyItem(at: tempURL, to: destination)
        return destination
    }

    /// Dropped copies are only needed until transcription finishes, so clear out ones older than a week.
    private func removeOldDroppedRecordings(in folder: URL) {
        let fileManager = FileManager.default
        let cutoff = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        let files = (try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for file in files {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modified, modified < cutoff { try? fileManager.removeItem(at: file) }
        }
    }

    /// Opens a native NSOpenPanel starting in iCloud Drive, filtered to audio recordings
    @MainActor
    public func promptForAudioFile(completion: @escaping (URL?) -> Void) {
        let panel = NSOpenPanel()
        panel.title = "Select Audio Recording (iCloud Drive / Local)"
        panel.prompt = "Choose Recording"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        
        let audioTypes: [UTType] = [
            .audio,
            .mp3,
            .mpeg4Audio,
            .wav,
            .aiff
        ]
        panel.allowedContentTypes = audioTypes

        // Default to iCloud Drive if available
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let cloudDocs = homeDir.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        if FileManager.default.fileExists(atPath: cloudDocs.path) {
            panel.directoryURL = cloudDocs
        } else {
            panel.directoryURL = homeDir.appendingPathComponent("Documents")
        }

        panel.begin { response in
            if response == .OK, let selectedURL = panel.url {
                completion(selectedURL)
            } else {
                completion(nil)
            }
        }
    }
}
