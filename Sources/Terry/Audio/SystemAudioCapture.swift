import AVFoundation
import CoreAudio

/// Everything the Mac plays (i.e. the other meeting participants), via a Core Audio process tap
/// wrapped in a private aggregate device. macOS asks for "System Audio Recording" permission
/// on first use; if it's denied the tap just delivers silence.
final class SystemAudioCapture: AudioSource {
    private var tap = AudioObjectID(kAudioObjectUnknown)
    private var device = AudioObjectID(kAudioObjectUnknown)
    private var proc: AudioDeviceIOProcID?
    private var outputListener: AudioObjectPropertyListenerBlock?
    private let queue = DispatchQueue(label: "terry.system-audio", qos: .userInitiated)

    func start(_ onBuffer: @escaping (AVAudioPCMBuffer, TimeInterval?) -> Void) throws {
        try run(onBuffer)
        // The aggregate is clocked by the output device, so rebuild it when the output changes.
        outputListener = AudioObjectID.system.listen(kAudioHardwarePropertyDefaultSystemOutputDevice, on: .main) { [weak self] in
            try? self?.run(onBuffer)
        }
    }

    func stop() {
        if let outputListener {
            AudioObjectID.system.removeListener(kAudioHardwarePropertyDefaultSystemOutputDevice, on: .main, outputListener)
        }
        outputListener = nil
        teardown()
    }

    private func run(_ onBuffer: @escaping (AVAudioPCMBuffer, TimeInterval?) -> Void) throws {
        teardown()
        do { try create(onBuffer) } catch { teardown(); throw error }
    }

    private func create(_ onBuffer: @escaping (AVAudioPCMBuffer, TimeInterval?) -> Void) throws {
        let description = CATapDescription(monoGlobalTapButExcludeProcesses: [])
        description.uuid = UUID()
        description.isPrivate = true
        description.muteBehavior = .unmuted
        try check(AudioHardwareCreateProcessTap(description, &tap))

        let output = AudioObjectID.system.read(kAudioHardwarePropertyDefaultSystemOutputDevice, default: AudioObjectID(0))
        guard let outputUID = output.readString(kAudioDevicePropertyDeviceUID) else { throw CoreAudioError(status: kAudioHardwareBadDeviceError) }
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Terry System Audio",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString, kAudioSubTapDriftCompensationKey: true]],
        ]
        try check(AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &device))

        var stream = tap.read(kAudioTapPropertyFormat, default: AudioStreamBasicDescription())
        guard let format = AVAudioFormat(streamDescription: &stream) else { throw CoreAudioError(status: kAudioHardwareUnsupportedOperationError) }
        // Larger IO buffers mean fewer wake-ups; transcription doesn't need low latency.
        device.write(kAudioDevicePropertyBufferFrameSize, UInt32(4096))

        try check(AudioDeviceCreateIOProcIDWithBlock(&proc, device, queue) { _, input, time, _, _ in
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: input) else { return }
            onBuffer(buffer, AVAudioTime.seconds(forHostTime: time.pointee.mHostTime))
        })
        try check(AudioDeviceStart(device, proc))
    }

    private func teardown() {
        if let proc {
            AudioDeviceStop(device, proc)
            AudioDeviceDestroyIOProcID(device, proc)
        }
        if device != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(device) }
        if tap != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tap) }
        proc = nil
        device = AudioObjectID(kAudioObjectUnknown)
        tap = AudioObjectID(kAudioObjectUnknown)
    }
}
