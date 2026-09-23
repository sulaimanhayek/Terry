import SwiftUI

@main
struct TerryApp: App {
    @NSApplicationDelegateAdaptor private var app: AppDelegate

    var body: some Scene {
        Window("Terry", id: "main") {
            ContentView()
                .showsInDock()
                .environment(app.store)
                .environment(app.recorder)
        }
        .defaultSize(width: 820, height: 560)
        .commands {
            CommandGroup(replacing: .newItem) { RecordMenuItem().environment(app.recorder) }
        }

        Settings {
            SettingsView()
                .showsInDock()
                .environment(app.store)
        }

        MenuBarExtra {
            MenuBarMenu().environment(app.recorder)
        } label: {
            MenuBarIcon().environment(app.recorder)
        }
    }
}
