import AVFoundation
import Testing
@testable import Terry

/// Plays a file in real time, 100 ms at a time, like a microphone.
final class RealtimeSource: AudioSource {
    let file: AVAudioFile
    private let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "terry.bench"))

    init(_ file: AVAudioFile) { self.file = file }

    func start(_ onBuffer: @escaping (AVAudioPCMBuffer, TimeInterval?) -> Void) throws {
        let file = file, timer = timer
        let format = file.processingFormat
        let chunk = AVAudioFrameCount(format.sampleRate / 10)
        let start = AVAudioTime.seconds(forHostTime: mach_absolute_time())
        timer.schedule(deadline: .now(), repeating: .milliseconds(100))
        timer.setEventHandler {
            guard file.framePosition < file.length else { return timer.cancel() }
            let time = start + Double(file.framePosition) / format.sampleRate
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk)!
            try? file.read(into: buffer, frameCount: chunk)
            onBuffer(buffer, time)
        }
        timer.resume()
    }

    func stop() { timer.cancel() }
}

/// CPU cost of transcribing a two-sided conversation in real time. Run with `make bench`.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["TERRY_BENCH"] != nil)) @MainActor
struct PerformanceTests {
    @Test func transcribingAMeetingInRealTime() async throws {
        UserDefaults.standard.register(defaults: [Pref.language: "en_US"])
        // Different lines per side: identical ones would be dropped as echo.
        let mine = """
            Thanks everyone for joining. Let's start with a quick update on the launch. The build is \
            in good shape, and we fixed the last two crashes on Friday.
            """
        let theirs = """
            Marketing needs final screenshots by Wednesday, so please send anything you have. After \
            that we'll review the budget for next quarter and pick one of the three proposals.
            """
        let me = try spokenAudio(String(repeating: mine + " ", count: 4))
        let them = try spokenAudio(String(repeating: theirs + " ", count: 4), voice: "Daniel")
        let seconds = Double(min(me.length, them.length)) / me.processingFormat.sampleRate

        try await withTempFolder { folder in
            let store = NoteStore(folder: folder)
            let recorder = Recorder(store: store) { [(.me, RealtimeSource(me)), (.them, RealtimeSource(them))] }
            await recorder.start()
            let cpuBefore = cpuTime(), daemonBefore = speechDaemonCPUTime(), wallBefore = ContinuousClock.now
            try await Task.sleep(for: .seconds(seconds))
            let cpu = cpuTime() - cpuBefore, daemon = speechDaemonCPUTime() - daemonBefore
            let wall = (ContinuousClock.now - wallBefore) / .seconds(1)
            let stopping = ContinuousClock.now
            await recorder.stop()
            let text = store.text(of: try #require(store.notes.first))
            #expect(text.contains("crashes") && text.contains("Wednesday"))
            let words = text.split(separator: " ").count
            print(String(format: "bench: %.0f s of two-sided speech, CPU (one core = 100%%): Terry %.1f%%, speech service %.1f%%. %d words, saved %.1f s after stop",
                         wall, cpu / wall * 100, daemon / wall * 100, words, (ContinuousClock.now - stopping) / .seconds(1)))
        }
    }

    private func cpuTime() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1e6
    }

    /// Recognition itself runs in a system process, so count its CPU too.
    private func speechDaemonCPUTime() -> Double {
        var pids = [pid_t](repeating: 0, count: 8192)
        let count = Int(proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size)))
        var timebase = mach_timebase_info()
        mach_timebase_info(&timebase)
        return pids.prefix(max(count, 0)).reduce(0) { total, pid in
            var name = [CChar](repeating: 0, count: 64)
            proc_name(pid, &name, UInt32(name.count))
            guard String(cString: name).hasPrefix("localspeechrec") else { return total }
            var info = rusage_info_v2()
            let ok = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V2, $0) }
            } == 0
            guard ok else { return total }
            let ticks = Double(info.ri_user_time + info.ri_system_time)
            return total + ticks * Double(timebase.numer) / Double(timebase.denom) / 1e9
        }
    }
}
