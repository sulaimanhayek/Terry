import AppKit
import SwiftUI

/// A small floating pill: it offers to transcribe when a meeting starts, then shows a timer and a stop
/// button while recording (unless Terry is in front). It never activates Terry, so the meeting app
/// keeps focus. It starts in the top-right corner and stays wherever it's dragged.
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
        NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.savePosition() }
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
        let size = host.fittingSize
        guard let corner = topRight(for: size) else { return }
        panel.setFrame(NSRect(x: corner.x - size.width, y: corner.y - size.height,
                              width: size.width, height: size.height), display: true)
        panel.orderFrontRegardless()
    }

    /// Where the pill's top-right corner goes: where it was last dragged to, kept fully on screen.
    /// Anchoring that corner keeps the pill in place as it changes width.
    private func topRight(for size: NSSize) -> NSPoint? {
        let saved = UserDefaults.standard.string(forKey: Pref.pillPosition).map(NSPointFromString)
        let screen = NSScreen.screens.first { saved.map($0.frame.insetBy(dx: -1, dy: -1).contains) ?? false }
            ?? NSScreen.main ?? NSScreen.screens.first
        guard let area = screen?.visibleFrame else { return nil }
        let point = saved ?? NSPoint(x: area.maxX, y: area.maxY)
        return NSPoint(x: min(max(point.x, area.minX + size.width), area.maxX),
                       y: min(max(point.y, area.minY + size.height), area.maxY))
    }

    private func savePosition() {
        guard panel.isVisible, NSEvent.pressedMouseButtons & 1 != 0 else { return }  // dragged, not placed by show()
        UserDefaults.standard.set(NSStringFromPoint(NSPoint(x: panel.frame.maxX, y: panel.frame.maxY)), forKey: Pref.pillPosition)
    }
}

/// Buttons respond to the first click, even though the panel never becomes key.
private final class FirstClickHostingView: NSHostingView<MeetingBanner> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

struct MeetingBanner: View {
    let meeting: MeetingController
    let recorder: Recorder
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(spacing: 10) {
            if let app = meeting.prompt {
                Image(systemName: "waveform").foregroundStyle(.tint)
                Text("\(app) is using the mic")
                Button("Transcribe", action: meeting.accept).buttonStyle(.glassProminent)
                CloseButton(action: meeting.dismiss)
            } else if recorder.state == .idle, let error = recorder.error {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                Text("Couldn't transcribe. \(error.localizedDescription)")
                    .lineLimit(2).frame(maxWidth: 280, alignment: .leading)
                CloseButton { recorder.error = nil }
            } else if recorder.state != .idle {
                HStack(spacing: 8) {
                    Circle().fill(.red).frame(width: 8, height: 8)
                    if let start = recorder.startedAt {
                        Text(timerInterval: start...Date.distantFuture, countsDown: false).monospacedDigit()
                    }
                }
                .contentShape(.rect)
                .onTapGesture {
                    NSApp.activate()
                    openWindow(id: "main")
                }
                .help("Show the transcript")
                if recorder.state == .recording {
                    Button("Stop", systemImage: "stop.circle.fill", action: recorder.toggle)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.plain)
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .help("Stop transcribing")
                } else {
                    ProgressView().controlSize(.small)
                }
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .capsule)
        .gesture(WindowDragGesture())
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
