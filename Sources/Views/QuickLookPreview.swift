import SwiftUI
import QuickLookUI

public struct QuickLookPreviewView: NSViewRepresentable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func makeNSView(context: Context) -> QLPreviewView {
        let previewView = QLPreviewView(frame: .zero, style: .normal) ?? QLPreviewView()
        previewView.previewItem = fileURL as QLPreviewItem
        return previewView
    }

    public func updateNSView(_ nsView: QLPreviewView, context: Context) {
        nsView.previewItem = fileURL as QLPreviewItem
        nsView.refreshPreviewItem()
    }
}

public struct QuickLookModal: View {
    public let fileURL: URL
    public var onDismiss: () -> Void

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(fileURL.lastPathComponent)
                    .font(.headline)

                Spacer()

                Button {
                    NSWorkspace.shared.open(fileURL)
                } label: {
                    Label("Open", systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Reveal in Finder")

                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            QuickLookPreviewView(fileURL: fileURL)
                .frame(minWidth: 520, idealWidth: 720, minHeight: 360, idealHeight: 520)
        }
        // Allow pressing Space to toggle/close Quick Look, just like Finder
        .background(
            Button("") {
                onDismiss()
            }
            .keyboardShortcut(.space, modifiers: [])
            .opacity(0)
            .frame(width: 0, height: 0)
        )
    }
}
