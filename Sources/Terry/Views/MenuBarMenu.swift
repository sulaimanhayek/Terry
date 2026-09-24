import SwiftUI

struct MenuBarMenu: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @AppStorage(Pref.showPill) private var showPill = false

    var body: some View {
        RecordMenuItem(opensWindow: true)
        Divider()
        Button("Open Terry") { openWindow(id: "main") }
        Toggle("Show Floating Pill", isOn: $showPill)
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
