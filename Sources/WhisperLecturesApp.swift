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
                Button("New Course...") {
                    NotificationCenter.default.post(name: .createNewCourse, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command])

                Button("New Lecture...") {
                    NotificationCenter.default.post(name: .createNewLecture, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

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
    static let createNewCourse = Notification.Name("createNewCourse")
    static let createNewLecture = Notification.Name("createNewLecture")
    static let importAudioRecording = Notification.Name("importAudioRecording")
}
