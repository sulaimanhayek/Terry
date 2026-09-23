import AVFoundation
import Testing
@testable import Terry

/// Plays a file into the recorder as if it were a live source, faster than real time.
final class FileSource: AudioSource {
    let file: AVAudioFile
    init(_ file: AVAudioFile) { self.file = file }

    func start(_ onBuffer: @escaping (AVAudioPCMBuffer, TimeInterval?) -> Void) throws {
        try feed(file, from: AVAudioTime.seconds(forHostTime: mach_absolute_time()), to: onBuffer)
    }

    func stop() {}
}

final class FailingSource: AudioSource {
    func start(_ onBuffer: @escaping (AVAudioPCMBuffer, TimeInterval?) -> Void) throws { throw TerryError.noMicrophone }
    func stop() {}
}

@Suite(.enabled(if: speechModelAvailable), .serialized) @MainActor
struct RecorderTests {
    init() { UserDefaults.standard.register(defaults: [Pref.language: "en_US"]) }

    @Test func recordsBothSidesIntoOneNote() async throws {
        try await withTempFolder { folder in
            let me = try spokenAudio("Can everyone hear me okay?")
            let them = try spokenAudio("Yes, the quarterly numbers look great.", voice: "Daniel")
            let store = NoteStore(folder: folder)
            let recorder = Recorder(store: store) { [(.me, FileSource(me)), (.them, FileSource(them))] }

            await recorder.start(app: "Zoom")
            #expect(recorder.error == nil)
            #expect(recorder.isRecording)
            await recorder.stop()
            #expect(recorder.state == .idle)

            let note = try #require(store.notes.first)
            let text = store.text(of: note)
            #expect(note.title.hasPrefix("Zoom · "))
            #expect(text.contains("**Me** · "))
            #expect(text.contains("**Them** · "))
            #expect(text.lowercased().contains("hear me"))
            #expect(text.lowercased().contains("quarterly numbers"))
        }
    }

    @Test func carriesOnWithoutSystemAudio() async throws {
        try await withTempFolder { folder in
            let me = try spokenAudio("Just a quick voice memo.")
            let store = NoteStore(folder: folder)
            let recorder = Recorder(store: store) { [(.me, FileSource(me)), (.them, FailingSource())] }
            await recorder.start()
            #expect(recorder.isRecording)
            await recorder.stop()
            let note = try #require(store.notes.first)
            #expect(store.text(of: note).lowercased().contains("voice memo"))
            #expect(!store.text(of: note).contains("**Me**"))  // one speaker: no labels
        }
    }

    @Test func failsCleanlyWithoutMicrophone() async throws {
        try await withTempFolder { folder in
            let store = NoteStore(folder: folder)
            let recorder = Recorder(store: store) { [(.me, FailingSource())] }
            await recorder.start()
            #expect(recorder.state == .idle)
            #expect(recorder.error != nil)
            #expect(store.notes.isEmpty)
        }
    }

    @Test func emptyRecordingLeavesNoFile() async throws {
        try await withTempFolder { folder in
            let store = NoteStore(folder: folder)
            let recorder = Recorder(store: store) { [] }
            await recorder.start()
            await recorder.stop()
            #expect(store.notes.isEmpty)
        }
    }
}
