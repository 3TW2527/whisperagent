import SwiftUI
import CoreImage.CIFilterBuiltins

/// The Phone Notepad tool: turn the server on, scan the QR code with the phone, and see what arrives.
struct PhoneNotepadView: View {
    @ObservedObject private var server = PhoneNotepadServer.shared
    @ObservedObject private var settings = AppSettings.shared
    @State private var isCopied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                switchCard

                if server.isRunning {
                    HStack(alignment: .top, spacing: 24) {
                        qrCard
                        VStack(alignment: .leading, spacing: 16) {
                            howTo
                            activity
                        }
                    }
                } else {
                    about
                }
            }
            .padding(24)
            .frame(maxWidth: 880, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private var switchCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "iphone.radiowaves.left.and.right")
                .font(.system(size: 30))
                .foregroundColor(server.isRunning ? .green : .secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(server.isRunning ? "Phone notepad is on" : "Phone notepad is off")
                    .font(.title3.bold())
                Text(statusLine)
                    .font(.caption)
                    .foregroundColor(.secondary)
                if let error = server.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { server.isRunning || server.isStarting },
                set: { $0 ? server.start() : server.stop() }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.large)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.08)))
    }

    private var statusLine: String {
        if server.isStarting { return "Starting..." }
        guard server.isRunning else {
            return "Turn it on to jot notes, actions and photos from your phone into a meeting while you walk around."
        }
        let minutes = settings.phoneNotepadAutoOffMinutes
        let autoOff = minutes > 0 ? "Turns off after \(Self.duration(minutes)) without the phone." : "Stays on until you turn it off or quit."
        let awake = settings.phoneNotepadKeepsMacAwake ? " Keeps the Mac awake (closing the lid still sleeps it)." : ""
        return autoOff + awake
    }

    // MARK: - QR Code

    private var qrCard: some View {
        VStack(spacing: 12) {
            if let url = server.pageURL, let image = Self.qrImage(for: url.absoluteString) {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 220, height: 220)
                    .padding(10)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                Text(url.absoluteString)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .frame(width: 240)

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.absoluteString, forType: .string)
                    isCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { isCopied = false }
                } label: {
                    Label(isCopied ? "Copied" : "Copy Link", systemImage: isCopied ? "checkmark" : "doc.on.doc")
                }
                .controlSize(.small)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 36))
                        .foregroundColor(.orange)
                    Text("No network")
                        .font(.headline)
                    Text("Connect this Mac to Wi-Fi or your phone's Personal Hotspot.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(width: 240, height: 240)
            }

            if server.addresses.count > 1 {
                Picker("Network", selection: $server.selectedAddressID) {
                    ForEach(server.addresses) { address in
                        Text("\(address.interfaceDescription) · \(address.ip)").tag(Optional(address.id))
                    }
                }
                .frame(width: 240)
            }
            Button {
                server.refreshAddresses()
            } label: {
                Label("Changed Network?", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.controlBackgroundColor)))
    }

    static func qrImage(for text: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let rep = NSCIImageRep(ciImage: scaled)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }

    // MARK: - Help and Activity

    private var howTo: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Scan with your phone's camera")
                .font(.headline)
            step("1", "Your phone must be on the same network as this Mac.")
            step("2", "Pick the meeting (it starts on the one happening now) or tap ＋ to start one.")
            step("3", "Type a note and tap Add. Turn on ☐ Action to add a to-do instead. Photo sends a picture into the meeting's files.")
            step("4", "Everything goes into the meeting's \"phone\" note, with the time. If the connection drops, the phone keeps your notes and sends them when it's back.")
            Text("On campus networks such as eduroam, devices usually can't reach each other, so you'll need a workaround: for example a VPN that both the phone and this Mac are on (e.g. Tailscale; pick its VPN address above), or the phone's Personal Hotspot with this Mac joined to it. After switching networks, press Changed Network?.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func step(_ number: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(number)
                .font(.caption.bold())
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.accentColor.opacity(0.18)))
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var activity: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("From the phone")
                .font(.headline)
            if server.events.isEmpty {
                Text("Nothing yet.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            ForEach(Array(server.events.enumerated()), id: \.offset) { _, event in
                Text(event)
                    .font(.system(.caption, design: .monospaced))
            }
        }
    }

    private var about: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How it works")
                .font(.headline)
            Text("The Mac serves a small notepad page on your local network. Scan the QR code with your phone to open it: no app to install, nothing goes through the internet. A new link is made each time you turn it on, so an old QR code stops working.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Text("It works with projects and courses. Notes go into the chosen meeting's or lecture's phone note, photos into the meeting's files (a course's materials), and in a project you can tick off actions.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Text("The phone can't record audio through this page (browsers only allow the microphone on secure sites). Keep recording with Voice Memos and transcribe on the Mac.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    static func duration(_ minutes: Int) -> String {
        minutes < 60 ? "\(minutes) minutes" : (minutes == 60 ? "1 hour" : "\(minutes / 60) hours")
    }
}

/// The Phone Notepad's settings: when it turns itself off, and whether it keeps the Mac awake.
struct PhoneNotepadSettingsView: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Turn off after", selection: $settings.phoneNotepadAutoOffMinutes) {
                ForEach(AppSettings.phoneNotepadAutoOffChoices, id: \.self) { minutes in
                    Text(minutes == 0 ? "Never" : "\(PhoneNotepadView.duration(minutes)) without the phone").tag(minutes)
                }
            }
            Text("So the notepad doesn't stay open on the network when you forget it. It also turns off when the app quits.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle("Keep the Mac awake while it's on", isOn: $settings.phoneNotepadKeepsMacAwake)
            Text("Stops the Mac from going to sleep on its own while you're away from it. Closing the lid still puts it to sleep. Applies the next time you turn the notepad on.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// "On" on the tool's home-screen card while the server is running.
struct PhoneNotepadBadge: View {
    @ObservedObject private var server = PhoneNotepadServer.shared

    var body: some View {
        if server.isRunning {
            Text("On")
                .font(.caption2.bold())
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.green.opacity(0.2)))
                .foregroundColor(.green)
        }
    }
}
