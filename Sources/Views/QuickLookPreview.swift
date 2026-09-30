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
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            QuickLookPreviewView(fileURL: fileURL)
                .frame(minWidth: 600, minHeight: 450)
        }
    }
}
