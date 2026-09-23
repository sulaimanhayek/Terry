import AppKit
import SwiftUI

/// A small floating banner in the top-right corner: the meeting prompt, then a pill while recording
/// (unless Terry is in front). It never activates Terry, so the meeting app keeps focus.
@MainActor
final class MeetingPanel {
    private let meeting: MeetingController
    private let recorder: Recorder
    private let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
    private let host: NSHostingView<MeetingBanner>

    init(meeting: MeetingController, recorder: Recorder) {
        self.meeting = meeting
        self.recorder = recorder
        host = FirstClickHostingView(rootView: MeetingBanner(meeting: meeting, recorder: recorder))
        host.sizingOptions = .intrinsicContentSize
        panel.contentView = host
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        for name in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.update() }
            }
        }
        track()
    }

    var isVisible: Bool { panel.isVisible }
    var frame: NSRect { panel.frame }

    private var shouldShow: Bool {
        meeting.prompt != nil || (!NSApp.isActive && (recorder.state != .idle || recorder.error != nil))
    }

    /// Updates whenever the prompt or recording state changes. Window work stays outside the tracking.
    private func track() {
        withObservationTracking { _ = (recorder.state, shouldShow) } onChange: { [weak self] in
            Task { @MainActor in self?.track() }
        }
        update()
    }

    private func update() {
        if recorder.state != .idle { meeting.dismiss() }  // Recording started from the menu instead.
        shouldShow ? show() : panel.orderOut(nil)
    }

    private func show() {
        guard let screen = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame else { return }
        let size = host.fittingSize
        panel.setFrame(NSRect(x: screen.maxX - size.width, y: screen.maxY - size.height,
                              width: size.width, height: size.height), display: true)
        panel.orderFrontRegardless()
    }
}

/// Buttons respond to the first click, even though the panel never becomes key.
private final class FirstClickHostingView: NSHostingView<MeetingBanner> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

struct MeetingBanner: View {
    let meeting: MeetingController
    let recorder: Recorder

    var body: some View {
        HStack(spacing: 12) {
            if let app = meeting.prompt {
                Image(systemName: "waveform").font(.title2).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(app) is using the microphone").font(.headline)
                    Text("Transcribe this meeting?").foregroundStyle(.secondary)
                }
                Button("Transcribe", action: meeting.accept).buttonStyle(.glassProminent)
                CloseButton(action: meeting.dismiss)
            } else if recorder.state == .idle, let error = recorder.error {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                Text("Couldn't transcribe. \(error.localizedDescription)")
                    .lineLimit(2).frame(maxWidth: 280, alignment: .leading)
                CloseButton { recorder.error = nil }
            } else {
                Circle().fill(.red).frame(width: 8, height: 8)
                Text(recorder.meetingApp ?? "Transcribing")
                if let start = recorder.startedAt {
                    Text(timerInterval: start...Date.distantFuture, countsDown: false)
                        .monospacedDigit().foregroundStyle(.secondary)
                }
                if recorder.state == .recording {
                    Button("Stop", action: recorder.toggle).buttonStyle(.glass)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .padding(12)
        .fixedSize()
    }
}

private struct CloseButton: View {
    let action: () -> Void

    var body: some View {
        Button("Close", systemImage: "xmark", action: action)
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
    }
}
