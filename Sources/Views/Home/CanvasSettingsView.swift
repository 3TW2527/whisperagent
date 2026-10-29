import SwiftUI

/// The Canvas tool's settings: the connection, where each course's files go, and how often to sync.
/// Shown from the tool's gear and in Settings → Tools.
struct CanvasSettingsView: View {
    @ObservedObject private var canvas = CanvasSyncService.shared
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var storage = CourseStorageService.shared

    @State private var linkError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Connection")
                    .font(.subheadline.bold())
                CanvasConnectionForm()
            }

            if canvas.isConfigured {
                coursesSection
                syncSection
            }
        }
    }

    private var coursesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Courses")
                .font(.subheadline.bold())
            Text("Link a Canvas course to one of your courses to save its files in that course's materials folder. Files from courses that aren't linked go to your Downloads folder. Untick a course to hide it.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if canvas.courses.isEmpty {
                Text("No courses yet. Connect, or press refresh in the Canvas tool.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(canvas.courses.enumerated()), id: \.element.id) { index, course in
                            if index > 0 { Divider() }
                            courseRow(course)
                        }
                    }
                }
                .frame(maxHeight: 280)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            if let linkError {
                Text(linkError)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
    }

    private func courseRow(_ course: CanvasCourse) -> some View {
        let isShown = Binding(
            get: { !settings.canvasHiddenCourseIDs.contains(course.id) },
            set: { shown in
                settings.canvasHiddenCourseIDs.removeAll { $0 == course.id }
                if !shown { settings.canvasHiddenCourseIDs.append(course.id) }
            }
        )
        let destination = Binding<String?>(
            get: { storage.course(linkedToCanvas: course.id)?.id },
            set: { courseID in
                do {
                    try storage.linkCanvasCourse(course.id, toCourseID: courseID)
                    canvas.matchExistingFiles()
                    linkError = nil
                } catch {
                    linkError = "Couldn't link the course: \(error.localizedDescription)"
                }
            }
        )
        return VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: isShown) {
                Text(course.displayName)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(course.displayName)
            }
            .toggleStyle(.checkbox)

            Picker("Save to", selection: destination) {
                Text("Downloads folder").tag(String?.none)
                Divider()
                ForEach(storage.courses) { local in
                    Text("\(local.displayName) materials").tag(Optional(local.id))
                }
            }
            .font(.caption)
            .disabled(!isShown.wrappedValue)
            .padding(.leading, 20)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    private var syncSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Sync")
                .font(.subheadline.bold())
            Picker("Check for new files", selection: $settings.canvasSyncMinutes) {
                ForEach(AppSettings.canvasSyncChoices, id: \.self) { minutes in
                    Text(minutes == 0 ? "Only when the tool opens" : "Every \(minutes) minutes").tag(minutes)
                }
            }
            .fixedSize()
            .onChange(of: settings.canvasSyncMinutes) {
                canvas.startAutoSync()
            }
            Text("The app also syncs each time you open the Canvas tool.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

/// The Canvas address and access token, with a button that checks them.
struct CanvasConnectionForm: View {
    @ObservedObject private var canvas = CanvasSyncService.shared
    @ObservedObject private var settings = AppSettings.shared

    @State private var address = AppSettings.shared.canvasAddress
    @State private var token = ""
    @State private var status: String?
    @State private var isError = false
    @State private var isWorking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Canvas address, e.g. school.instructure.com", text: $address)
                .textFieldStyle(.roundedBorder)
            SecureField(canvas.hasToken ? "Access token (saved; leave empty to keep it)" : "Access token", text: $token)
                .textFieldStyle(.roundedBorder)
            Text("Create a token in Canvas under Account → Settings → New Access Token. It's kept in your keychain and only reads what you can see as a student.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button(canvas.isConfigured ? "Save and Test" : "Connect") { connect() }
                    .buttonStyle(.borderedProminent)
                    .disabled(isWorking || address.trimmingCharacters(in: .whitespaces).isEmpty || (token.isEmpty && !canvas.hasToken))
                if canvas.hasToken {
                    Button("Disconnect") {
                        canvas.disconnect()
                        status = "Disconnected. The token was removed from your keychain."
                        isError = false
                    }
                    .disabled(isWorking)
                }
                if isWorking {
                    ProgressView().controlSize(.small)
                }
            }

            if let status {
                Label(status, systemImage: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(isError ? .red : .green)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func connect() {
        isWorking = true
        status = nil
        Task {
            do {
                let name = try await canvas.connect(address: address, token: token)
                address = settings.canvasAddress
                token = ""
                status = "Connected as \(name)."
                isError = false
                isWorking = false
                canvas.startAutoSync()
                await canvas.sync()
            } catch {
                status = error.localizedDescription
                isError = true
                isWorking = false
            }
        }
    }
}
