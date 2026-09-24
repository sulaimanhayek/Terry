import AppKit
import Testing
@testable import Terry

struct MeetingDetectorTests {
    @Test(arguments: [
        ("us.zoom.xos", "/Applications/zoom.us.app/Contents/MacOS/zoom.us", "Zoom"),
        ("com.google.Chrome.helper", "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Versions/140.0/Helpers/Google Chrome Helper.app/Contents/MacOS/Google Chrome Helper", "Google Chrome"),
        ("com.microsoft.teams2", "/Applications/Microsoft Teams.app/Contents/MacOS/MSTeams", "Microsoft Teams"),
        ("com.apple.avconferenced", "/usr/libexec/avconferenced", "FaceTime"),
        ("com.apple.WebKit.GPU", "/System/Library/Frameworks/WebKit.framework/Versions/A/XPCServices/com.apple.WebKit.GPU.xpc/Contents/MacOS/com.apple.WebKit.GPU", "Safari"),
    ])
    func namesTheApp(bundleID: String, path: String, name: String) {
        #expect(MeetingDetector.appName(bundleID: bundleID, path: path) == name)
    }

    @Test func ignoresSystemServicesAndTools() {
        #expect(MeetingDetector.appName(bundleID: "com.apple.corespeechd", path: "/System/Library/PrivateFrameworks/CoreSpeech.framework/corespeechd") == nil)
        #expect(MeetingDetector.appName(bundleID: "com.apple.VoiceMemos", path: "/System/Applications/VoiceMemos.app/Contents/MacOS/VoiceMemos") == nil)
        #expect(MeetingDetector.appName(bundleID: "", path: "/opt/homebrew/bin/sox") == nil)
    }
}

@Suite(.serialized) @MainActor
struct MeetingControllerTests {
    init() {
        UserDefaults.standard.register(defaults: [Pref.language: "en_US", Pref.meetingPrompt: true])
    }

    @Test func offersToTranscribeAndTimesOut() async throws {
        try await withTempFolder { folder in
            let meeting = MeetingController(recorder: Recorder(store: NoteStore(folder: folder)) { [] },
                                            promptTimeout: .milliseconds(100))
            meeting.meetingChanged("Zoom")
            #expect(meeting.prompt == "Zoom")
            #expect(await eventually { meeting.prompt == nil })
        }
    }

    @Test func promptEndsWithTheMeeting() async throws {
        try await withTempFolder { folder in
            let meeting = MeetingController(recorder: Recorder(store: NoteStore(folder: folder)) { [] })
            meeting.meetingChanged("Zoom")
            meeting.meetingChanged(nil)
            #expect(meeting.prompt == nil)
        }
    }

    @Test func respectsTheSetting() async throws {
        UserDefaults.standard.set(false, forKey: Pref.meetingPrompt)
        defer { UserDefaults.standard.removeObject(forKey: Pref.meetingPrompt) }
        try await withTempFolder { folder in
            let meeting = MeetingController(recorder: Recorder(store: NoteStore(folder: folder)) { [] })
            meeting.meetingChanged("Zoom")
            #expect(meeting.prompt == nil)
        }
    }

    @Test(.enabled(if: speechModelAvailable))
    func transcribesTheMeetingAndStopsWhenItEnds() async throws {
        try await withTempFolder { folder in
            let audio = try spokenAudio("Let's get started with the weekly sync.")
            let store = NoteStore(folder: folder)
            let recorder = Recorder(store: store) { [(.me, FileSource(audio))] }
            let meeting = MeetingController(recorder: recorder, endDelay: .milliseconds(100))

            meeting.meetingChanged("Zoom")
            meeting.accept()
            #expect(meeting.prompt == nil)
            #expect(await eventually { recorder.isRecording })
            #expect(recorder.meetingApp == "Zoom")

            meeting.meetingChanged(nil)
            #expect(await eventually(timeout: .seconds(20)) { recorder.state == .idle })
            let note = try #require(store.notes.first)
            #expect(note.title.hasPrefix("Zoom · "))
            #expect(store.text(of: note).lowercased().contains("weekly sync"))
        }
    }
}

@Suite(.serialized) @MainActor
struct MeetingPanelTests {
    init() {
        _ = NSApplication.shared
        UserDefaults.standard.register(defaults: [Pref.meetingPrompt: true])
        UserDefaults.standard.removeObject(forKey: Pref.pillPosition)
    }

    @Test func showsThePromptThenARecordingPill() async throws {
        try await withTempFolder { folder in
            let recorder = Recorder(store: NoteStore(folder: folder)) { [] }
            let meeting = MeetingController(recorder: recorder)
            let panel = MeetingPanel(meeting: meeting, recorder: recorder)
            #expect(!panel.isVisible)

            meeting.meetingChanged("Zoom")
            #expect(await eventually { panel.isVisible })
            let screen = try #require(NSScreen.main ?? NSScreen.screens.first).visibleFrame
            #expect(panel.frame.maxX == screen.maxX && panel.frame.maxY == screen.maxY)
            let promptWidth = panel.frame.width

            meeting.accept()
            #expect(await eventually { recorder.isRecording && panel.isVisible && panel.frame.width < promptWidth })
            #expect(panel.frame.maxX == screen.maxX && panel.frame.maxY == screen.maxY)
            await recorder.stop()
            #expect(await eventually { !panel.isVisible })
        }
    }

    @Test func recordingFromTheMenuReplacesThePrompt() async throws {
        try await withTempFolder { folder in
            let recorder = Recorder(store: NoteStore(folder: folder)) { [] }
            let meeting = MeetingController(recorder: recorder)
            let panel = MeetingPanel(meeting: meeting, recorder: recorder)
            meeting.meetingChanged("Zoom")
            #expect(await eventually { panel.isVisible })

            await recorder.start()
            #expect(await eventually { meeting.prompt == nil })
            await recorder.stop()
            #expect(await eventually { !panel.isVisible })
        }
    }

    @Test func staysWhereItWasDraggedButOnScreen() async throws {
        let screen = try #require(NSScreen.main ?? NSScreen.screens.first).visibleFrame
        try await withTempFolder { folder in
            let recorder = Recorder(store: NoteStore(folder: folder)) { [] }
            let meeting = MeetingController(recorder: recorder)
            let panel = MeetingPanel(meeting: meeting, recorder: recorder)

            UserDefaults.standard.set(NSStringFromPoint(NSPoint(x: screen.midX, y: screen.midY)), forKey: Pref.pillPosition)
            meeting.meetingChanged("Zoom")
            #expect(await eventually { panel.isVisible })
            #expect(panel.frame.maxX == screen.midX && panel.frame.maxY == screen.midY)

            // Dragged mostly off the left edge, or saved on a display that's gone.
            meeting.dismiss()
            UserDefaults.standard.set(NSStringFromPoint(NSPoint(x: screen.minX + 5, y: -5000)), forKey: Pref.pillPosition)
            meeting.meetingChanged("Zoom")
            #expect(await eventually { panel.frame.minX == screen.minX && panel.frame.minY == screen.minY })
        }
    }
}
