import AVFoundation

/// Something that produces live audio. Buffers arrive on a background thread and are only
/// valid for the duration of the callback; `hostTime` is when the first frame was captured.
protocol AudioSource: AnyObject {
    /// Called before `start`, e.g. to ask for permission.
    func prepare() async throws
    func start(_ onBuffer: @escaping (_ buffer: AVAudioPCMBuffer, _ hostTime: TimeInterval?) -> Void) throws
    func stop()
}

extension AudioSource {
    func prepare() async throws {}
}

/// The default input device, via AVAudioEngine. Survives device switches (e.g. AirPods connecting).
final class MicrophoneCapture: AudioSource {
    private let engine = AVAudioEngine()
    private var onBuffer: ((AVAudioPCMBuffer, TimeInterval?) -> Void)?
    private var observer: NSObjectProtocol?

    func prepare() async throws {
        guard await AVAudioApplication.requestRecordPermission() else { throw TerryError.microphoneDenied }
    }

    func start(_ onBuffer: @escaping (AVAudioPCMBuffer, TimeInterval?) -> Void) throws {
        self.onBuffer = onBuffer
        try run()
        observer = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in try? self?.run() }
    }

    func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    private func run() throws {
        engine.stop()
        let input = engine.inputNode
        input.removeTap(onBus: 0)
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw TerryError.noMicrophone }
        let onBuffer = onBuffer
        // ~100 ms buffers: fewer wake-ups than the default, still responsive.
        input.installTap(onBus: 0, bufferSize: AVAudioFrameCount(format.sampleRate / 10), format: format) { buffer, time in
            onBuffer?(buffer, time.isHostTimeValid ? AVAudioTime.seconds(forHostTime: time.hostTime) : nil)
        }
        engine.prepare()
        try engine.start()
    }
}
