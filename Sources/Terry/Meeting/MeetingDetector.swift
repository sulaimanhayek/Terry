import CoreAudio
import Foundation

/// Notices when another app starts or stops using the microphone, i.e. a call or meeting.
/// Watches Core Audio's per-process input state: no permission needed, and it's event-driven,
/// so it costs nothing while idle.
@MainActor
final class MeetingDetector {
    /// Called with the app's name when a meeting starts, and with nil when it ends.
    var onChange: (String?) -> Void = { _ in }
    private(set) var app: String?

    private var listeners: [AudioObjectID: AudioObjectPropertyListenerBlock] = [:]
    private var pending: Task<Void, Never>?

    func start() {
        _ = AudioObjectID.system.listen(kAudioHardwarePropertyProcessObjectList, on: .main) { [weak self] in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refresh()
    }

    /// Keeps one input listener per audio process.
    private func refresh() {
        let processes = Set(AudioObjectID.system.readObjects(kAudioHardwarePropertyProcessObjectList))
        for process in processes where listeners[process] == nil {
            listeners[process] = process.listen(kAudioProcessPropertyIsRunningInput, on: .main) { [weak self] in
                MainActor.assumeIsolated { self?.update() }
            }
        }
        for (process, block) in listeners where !processes.contains(process) {
            process.removeListener(kAudioProcessPropertyIsRunningInput, on: .main, block)
            listeners[process] = nil
        }
        update()
    }

    private func update() {
        let current = listeners.keys.lazy
            .filter { $0.read(kAudioProcessPropertyIsRunningInput, default: UInt32(0)) != 0 }
            .compactMap(Self.appName)
            .first
        pending?.cancel()
        pending = Task {
            // Ignore brief mic use, like dictation or switching devices.
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, current != app else { return }
            app = current
            onChange(current)
        }
    }

    private nonisolated static func appName(_ process: AudioObjectID) -> String? {
        let pid = process.read(kAudioProcessPropertyPID, default: pid_t(-1))
        guard pid > 0, pid != getpid() else { return nil }
        var path = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let found = proc_pidpath(pid, &path, UInt32(path.count)) > 0
        return appName(bundleID: process.readString(kAudioProcessPropertyBundleID) ?? "",
                       path: found ? String(cString: path) : "")
    }

    /// Names the app a process belongs to. Helper processes live inside their app's bundle,
    /// so the outermost `.app` in the path is the one the user knows.
    nonisolated static func appName(bundleID: String, path: String) -> String? {
        if bundleID == "com.apple.FaceTime" || bundleID == "com.apple.avconferenced" { return "FaceTime" }
        if bundleID.hasPrefix("com.apple.WebKit") { return "Safari" }
        if bundleID.hasPrefix("com.apple.") { return nil }  // Siri, dictation, Voice Memos…
        guard let app = path.firstRange(of: ".app/") else { return nil }
        let name = URL(filePath: String(path[..<app.lowerBound])).lastPathComponent
        return name == "zoom.us" ? "Zoom" : name
    }
}
