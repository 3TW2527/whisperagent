import SwiftUI

@main
struct WhisperLecturesApp: App {
    var body: some Scene {
        WindowGroup {
            MainView()
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            SidebarCommands()
            CommandGroup(after: .newItem) {
                Button("New Lecture Project...") {
                    NotificationCenter.default.post(name: .createNewLectureProject, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command])

                Button("Import Audio Recording...") {
                    VoiceMemosService.shared.promptForAudioFile { url in
                        if let url = url {
                            NotificationCenter.default.post(name: .importAudioRecording, object: url)
                        }
                    }
                }
                .keyboardShortcut("i", modifiers: [.command])
            }
        }
    }
}

extension Notification.Name {
    static let createNewLectureProject = Notification.Name("createNewLectureProject")
    static let importAudioRecording = Notification.Name("importAudioRecording")
}
