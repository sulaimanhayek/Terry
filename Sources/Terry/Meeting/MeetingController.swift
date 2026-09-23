import Foundation

/// Offers to transcribe when a meeting starts, and finishes that transcript when the meeting ends.
@MainActor @Observable
final class MeetingController {
    /// The meeting app being offered, while the prompt is showing.
    private(set) var prompt: String?

    private let recorder: Recorder
    private let promptTimeout: Duration
    private let endDelay: Duration
    @ObservationIgnored private var timer: Task<Void, Never>?

    init(recorder: Recorder, promptTimeout: Duration = .seconds(20), endDelay: Duration = .seconds(15)) {
        self.recorder = recorder
        self.promptTimeout = promptTimeout
        self.endDelay = endDelay
    }

    func meetingChanged(_ app: String?) {
        timer?.cancel()
        prompt = nil
        if let app {
            guard recorder.state == .idle, UserDefaults.standard.bool(forKey: Pref.meetingPrompt) else { return }
            prompt = app
            timer = after(promptTimeout) { $0.prompt = nil }
        } else if recorder.state == .recording, recorder.meetingApp != nil {
            // Grace period in case the app only briefly lets go of the mic.
            timer = after(endDelay) { await $0.recorder.stop() }
        }
    }

    func accept() {
        guard let app = prompt else { return }
        dismiss()
        Task { await recorder.start(app: app) }
    }

    func dismiss() {
        timer?.cancel()
        prompt = nil
    }

    private func after(_ delay: Duration, _ action: @escaping (MeetingController) async -> Void) -> Task<Void, Never> {
        Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            await action(self)
        }
    }
}
