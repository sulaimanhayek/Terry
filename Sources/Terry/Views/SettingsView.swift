import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Environment(NoteStore.self) private var store
    @AppStorage(Pref.language) private var language = ""
    @AppStorage(Pref.systemAudio) private var systemAudio = true
    @AppStorage(Pref.meetingPrompt) private var meetingPrompt = true
    @AppStorage(Pref.appearance) private var appearance = "system"
    @State private var languages: [Locale] = []
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section {
                LabeledContent("Notes folder") {
                    HStack {
                        Text(store.folder.path(percentEncoded: false).replacing(NSHomeDirectory(), with: "~"))
                            .lineLimit(1).truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Button("Choose…", action: chooseFolder)
                    }
                }
            } footer: {
                Text("Notes are Markdown files. Pick a folder in iCloud Drive or Google Drive to sync them.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section {
                Picker("Language", selection: $language) {
                    Text("System (\(Locale.current.displayName))").tag("")
                    Divider()
                    ForEach(languages, id: \.identifier) { Text($0.displayName).tag($0.identifier) }
                }
                Toggle("Transcribe other participants", isOn: $systemAudio)
                Toggle("Offer to transcribe when a meeting starts", isOn: $meetingPrompt)
            } footer: {
                Text("Everything is transcribed on this Mac. Other participants are captured from your Mac's sound output.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section {
                Picker("Appearance", selection: $appearance) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                Toggle("Open at login", isOn: $openAtLogin)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize()
        .task { languages = await SpeechModel.languages() }
        .onChange(of: appearance) { AppDelegate.applyAppearance() }
        .onChange(of: openAtLogin) { _, on in
            try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
            openAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = store.folder
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url { store.setFolder(url) }
    }
}
