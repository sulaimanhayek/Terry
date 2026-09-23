import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = NoteStore()
    lazy var recorder = Recorder(store: store)
    private lazy var meeting = MeetingController(recorder: recorder)
    private let detector = MeetingDetector()
    private var panel: MeetingPanel?

    func applicationWillFinishLaunching(_ notification: Notification) {
        Pref.registerDefaults()
        Self.applyAppearance()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        panel = MeetingPanel(meeting: meeting, recorder: recorder)
        detector.onChange = { [meeting] in meeting.meetingChanged($0) }
        detector.start()

        // When opened at login, stay in the menu bar instead of showing the window.
        let event = NSAppleEventManager.shared().currentAppleEvent
        guard event?.eventID == kAEOpenApplication,
              event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem else { return }
        NSApp.windows.first { $0.identifier?.rawValue == "main" }?.close()
    }

    /// Finish recognizing and save before quitting.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard recorder.state == .recording else { return .terminateNow }
        Task {
            await recorder.stop()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    static func applyAppearance() {
        NSApp.appearance = switch UserDefaults.standard.string(forKey: Pref.appearance) {
        case "light": NSAppearance(named: .aqua)
        case "dark": NSAppearance(named: .darkAqua)
        default: nil
        }
    }
}

/// Terry lives in the menu bar; it appears in the Dock and app switcher only while a window is open.
@MainActor private var openWindows = 0

extension View {
    func showsInDock() -> some View {
        onAppear {
            openWindows += 1
            NSApp.setActivationPolicy(.regular)
            NSApp.activate()
        }
        .onDisappear {
            openWindows -= 1
            if openWindows == 0 { NSApp.setActivationPolicy(.accessory) }
        }
    }
}
