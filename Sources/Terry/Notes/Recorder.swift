import AVFoundation

/// Runs one recording: audio sources → transcribers → transcript → note file.
@MainActor @Observable
final class Recorder {
    enum State { case idle, starting, recording, stopping }

    private(set) var state = State.idle
    private(set) var transcript = Transcript()
    private(set) var startedAt: Date?
    private(set) var noteURL: URL?
    /// The meeting app that prompted this recording, if any.
    private(set) var meetingApp: String?
    var error: Error?

    private let store: NoteStore
    private let sources: () -> [(Speaker, AudioSource)]
    private var active: [(source: AudioSource, transcriber: LiveTranscriber)] = []
    private var activity: NSObjectProtocol?
    private var pendingSave: Task<Void, Never>?

    init(store: NoteStore, sources: @escaping () -> [(Speaker, AudioSource)] = Recorder.liveSources) {
        self.store = store
        self.sources = sources
    }

    nonisolated static func liveSources() -> [(Speaker, AudioSource)] {
        var sources: [(Speaker, AudioSource)] = [(.me, MicrophoneCapture())]
        if UserDefaults.standard.bool(forKey: Pref.systemAudio) { sources.append((.them, SystemAudioCapture())) }
        return sources
    }

    var isRecording: Bool { state == .recording }

    func toggle() {
        Task { state == .idle ? await start() : await stop() }
    }

    func start(app: String? = nil) async {
        guard state == .idle else { return }
        state = .starting
        error = nil
        transcript = Transcript()
        meetingApp = app
        // Transcribers first: the model may need a one-time download before any audio flows.
        var ready: [(source: AudioSource, transcriber: LiveTranscriber)] = []
        do {
            for (speaker, source) in sources() {
                try await source.prepare()
                let transcriber = LiveTranscriber(speaker: speaker)
                try await transcriber.start(locale: Pref.locale) { [weak self] in self?.received($0, isFinal: $1) }
                ready.append((source, transcriber))
            }
            let origin = AVAudioTime.seconds(forHostTime: mach_absolute_time())
            startedAt = .now
            noteURL = store.newNoteURL(for: .now)
            for pair in ready {
                let transcriber = pair.transcriber
                transcriber.origin = origin
                do {
                    try pair.source.start { transcriber.append($0, hostTime: $1) }
                    active.append(pair)
                } catch where transcriber.speaker == .them {
                    await transcriber.finish()  // System audio is optional; carry on with the mic.
                }
            }
            activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep, reason: "Recording")
            state = .recording
        } catch {
            for pair in active { pair.source.stop() }
            for pair in ready { await pair.transcriber.finish() }
            active = []
            self.error = error
            state = .idle
        }
    }

    /// Stops capture, waits for the last words to be recognized and saves the note.
    func stop() async {
        guard state == .recording else { return }
        state = .stopping
        for pair in active { pair.source.stop() }
        for pair in active { await pair.transcriber.finish() }
        active = []
        pendingSave?.cancel()
        pendingSave = nil
        save()
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
        state = .idle
    }

    private func received(_ segment: Segment, isFinal: Bool) {
        transcript.apply(segment, isFinal: isFinal)
        // Save at most every 2 s, so a crash or power loss costs a few seconds of text at most.
        guard isFinal, state == .recording, pendingSave == nil else { return }
        pendingSave = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            pendingSave = nil
            save()
        }
    }

    private func save() {
        guard let noteURL, let startedAt, !transcript.isEmpty else { return }
        let title = NoteFormat.title(date: startedAt, app: meetingApp)
        do {
            try store.write(NoteFormat.markdown(title: title, paragraphs: transcript.paragraphs()), to: noteURL)
        } catch {
            self.error = error
        }
    }
}
