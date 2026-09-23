import SwiftUI

struct MenuBarMenu: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        RecordMenuItem(opensWindow: true)
        Divider()
        Button("Open Terry") { openWindow(id: "main") }
        Button("Settings…") { openSettings() }.keyboardShortcut(",")
        Divider()
        Button("Quit Terry") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}

struct MenuBarIcon: View {
    @Environment(Recorder.self) private var recorder

    var body: some View {
        Image(systemName: recorder.state == .idle ? "waveform" : "record.circle")
    }
}
