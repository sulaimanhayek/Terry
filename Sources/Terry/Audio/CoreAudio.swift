import CoreAudio
import Foundation

struct CoreAudioError: LocalizedError {
    let status: OSStatus
    var errorDescription: String? { "Core Audio error \(status)" }
}

func check(_ status: OSStatus) throws {
    guard status == noErr else { throw CoreAudioError(status: status) }
}

extension AudioObjectID {
    static let system = AudioObjectID(kAudioObjectSystemObject)

    func read<T: BitwiseCopyable>(_ selector: AudioObjectPropertySelector, default value: T) -> T {
        var address = Self.address(selector)
        var size = UInt32(MemoryLayout<T>.size)
        var result = value
        return AudioObjectGetPropertyData(self, &address, 0, nil, &size, &result) == noErr ? result : value
    }

    func readString(_ selector: AudioObjectPropertySelector) -> String? {
        var address = Self.address(selector)
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var value: Unmanaged<CFString>?
        guard AudioObjectGetPropertyData(self, &address, 0, nil, &size, &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    func readObjects(_ selector: AudioObjectPropertySelector) -> [AudioObjectID] {
        var address = Self.address(selector)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(self, &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(self, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    func write<T: BitwiseCopyable>(_ selector: AudioObjectPropertySelector, _ value: T) {
        var address = Self.address(selector)
        var value = value
        AudioObjectSetPropertyData(self, &address, 0, nil, UInt32(MemoryLayout<T>.size), &value)
    }

    /// Calls `handler` on `queue` whenever the property changes. Returns a token for `removeListener`.
    func listen(_ selector: AudioObjectPropertySelector, on queue: DispatchQueue,
                _ handler: @escaping () -> Void) -> AudioObjectPropertyListenerBlock {
        var address = Self.address(selector)
        let block: AudioObjectPropertyListenerBlock = { _, _ in handler() }
        AudioObjectAddPropertyListenerBlock(self, &address, queue, block)
        return block
    }

    func removeListener(_ selector: AudioObjectPropertySelector, on queue: DispatchQueue,
                        _ block: @escaping AudioObjectPropertyListenerBlock) {
        var address = Self.address(selector)
        AudioObjectRemovePropertyListenerBlock(self, &address, queue, block)
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }
}
