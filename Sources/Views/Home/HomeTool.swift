import SwiftUI

/// A feature launched from the Tools section of the home screen.
///
/// To add a tool, write its view and append an entry to `HomeTool.all`. The home screen shows a card for it,
/// and opening the card shows the view under a header with a way back home.
///
/// A tool with settings gives a `makeSettings` view. It opens from the gear in the tool's header and is also
/// listed under Settings → Tools, so tool options never go into the general settings. A `makeBadge` view is
/// shown on the tool's home-screen card, e.g. a count of new items.
struct HomeTool: Identifiable {
    let id: String
    let title: String
    let summary: String
    let systemImage: String
    let tint: Color
    let makeView: @MainActor () -> AnyView
    var makeSettings: (@MainActor () -> AnyView)? = nil
    var makeBadge: (@MainActor () -> AnyView)? = nil

    /// Every tool, in the order the home screen shows them.
    static var all: [HomeTool] {
        [.canvas, .markdownLibrary, .phoneNotepad]
    }

    static func tool(id: String) -> HomeTool? {
        all.first { $0.id == id }
    }
}

extension HomeTool {
    static var canvas: HomeTool {
        HomeTool(
            id: "canvas",
            title: "Canvas",
            summary: "See what's new in your Canvas courses and download files into their materials.",
            systemImage: "graduationcap.fill",
            tint: .red,
            makeView: { AnyView(CanvasView()) },
            makeSettings: { AnyView(CanvasSettingsView()) },
            makeBadge: { AnyView(CanvasToolBadge()) }
        )
    }

    static var markdownLibrary: HomeTool {
        HomeTool(
            id: "markdown-library",
            title: "Markdown Library",
            summary: "Add folders of Markdown files, then read and edit them with the note editor.",
            systemImage: "books.vertical.fill",
            tint: .purple,
            makeView: { AnyView(MarkdownLibraryView()) },
            makeSettings: { AnyView(MarkdownLibrarySettingsView()) }
        )
    }
}

extension HomeTool {
    static var phoneNotepad: HomeTool {
        HomeTool(
            id: "phone-notepad",
            title: "Phone Notepad",
            summary: "Scan a QR code to jot notes, actions and photos into a meeting from your phone.",
            systemImage: "iphone.radiowaves.left.and.right",
            tint: .green,
            makeView: { AnyView(PhoneNotepadView()) },
            makeSettings: { AnyView(PhoneNotepadSettingsView()) },
            makeBadge: { AnyView(PhoneNotepadBadge()) }
        )
    }
}

/// An open tool: a header with the way back home, then the tool's own view.
struct HomeToolPage: View {
    let tool: HomeTool
    let onHome: () -> Void

    @State private var isShowingSettings = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button(action: onHome) {
                    Label("Home", systemImage: "chevron.left")
                        .font(.caption)
                }
                .buttonStyle(.borderless)

                Divider().frame(height: 14)

                Image(systemName: tool.systemImage)
                    .foregroundColor(tool.tint)
                Text(tool.title)
                    .font(.headline)
                Spacer()
                if let makeSettings = tool.makeSettings {
                    Button {
                        isShowingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .buttonStyle(.borderless)
                    .help("\(tool.title) settings")
                    .popover(isPresented: $isShowingSettings, arrowEdge: .bottom) {
                        makeSettings()
                            .padding(16)
                            .frame(width: 420)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            tool.makeView()
        }
    }
}

/// Settings → Tools: every tool's settings, one section per tool.
struct ToolSettingsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                ForEach(Array(HomeTool.all.enumerated()), id: \.element.id) { index, tool in
                    if index > 0 { Divider() }
                    VStack(alignment: .leading, spacing: 12) {
                        Label(tool.title, systemImage: tool.systemImage)
                            .font(.headline)
                            .foregroundStyle(tool.tint, .primary)
                        if let makeSettings = tool.makeSettings {
                            makeSettings()
                        } else {
                            Text("This tool has no settings.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
