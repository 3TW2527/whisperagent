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

    /// Launches or brings macOS Voice Memos app to the foreground so the user can easily drag recordings into WhisperLectures
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
