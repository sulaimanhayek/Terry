import AVFoundation
import Speech

/// Streams one audio source into an on-device SpeechAnalyzer and reports recognized text.
/// `append` is called from the source's audio thread; everything else from the main actor.
final class LiveTranscriber: @unchecked Sendable {
    let speaker: Speaker
    /// Host time (seconds) the recording started. Result times are relative to it, which keeps
    /// separate sources on one timeline. Set before audio starts flowing.
    var origin: TimeInterval = 0
    private var analyzer: SpeechAnalyzer?
    private var input: AsyncStream<AnalyzerInput>.Continuation?
    private var format: AVAudioFormat?
    private var converter: AVAudioConverter?
    private var position: TimeInterval = 0
    private var results: Task<Void, Error>?

    init(speaker: Speaker) {
        self.speaker = speaker
    }

    func start(locale: Locale, onResult: @escaping @MainActor (Segment, _ isFinal: Bool) -> Void) async throws {
        let module = try await SpeechModel.module(for: locale)
        try await SpeechModel.install(module)
        format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module])
        let (stream, input) = AsyncStream<AnalyzerInput>.makeStream()
        let analyzer = SpeechAnalyzer(modules: [module])
        try await analyzer.prepareToAnalyze(in: format)
        try await analyzer.start(inputSequence: stream)
        self.analyzer = analyzer
        self.input = input

        let speaker = speaker
        results = Task { @MainActor in
            @MainActor func emit(_ text: AttributedString, _ range: CMTimeRange, _ isFinal: Bool) {
                let text = String(text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                onResult(Segment(speaker: speaker, start: range.start.seconds, end: range.end.seconds, text: text), isFinal)
            }
            switch module {
            case let m as SpeechTranscriber: for try await r in m.results { emit(r.text, r.range, r.isFinal) }
            case let m as DictationTranscriber: for try await r in m.results { emit(r.text, r.range, r.isFinal) }
            default: break
            }
        }
    }

    /// `hostTime` is when the buffer's first frame was captured, if the source knows it.
    func append(_ buffer: AVAudioPCMBuffer, hostTime: TimeInterval?) {
        guard let input, let format, buffer.frameLength > 0 else { return }
        if converter?.inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: format)
            converter?.downmix = true
        }
        let ratio = format.sampleRate / buffer.format.sampleRate
        guard let converter,
              let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64)
        else { return }
        var consumed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if consumed { status.pointee = .noDataNow; return nil }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, output.frameLength > 0 else { return }

        // The analyzer needs one contiguous stream, so bridge gaps (late start, device switch,
        // sleep) with silence to keep both speakers' timestamps aligned to the same clock.
        if let hostTime, case let gap = min(hostTime - origin - position, 60), gap > 0.5 {
            input.yield(AnalyzerInput(buffer: Self.silence(gap, format: format)))
            position += gap
        }
        position += Double(buffer.frameLength) / buffer.format.sampleRate
        input.yield(AnalyzerInput(buffer: output))
    }

    private static func silence(_ seconds: TimeInterval, format: AVAudioFormat) -> AVAudioPCMBuffer {
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(seconds * format.sampleRate))!
        buffer.frameLength = buffer.frameCapacity
        for b in UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList) { memset(b.mData, 0, Int(b.mDataByteSize)) }
        return buffer
    }

    /// Flushes buffered audio so the last words become final, then waits for their results.
    func finish() async {
        input?.finish()
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        _ = try? await results?.value
    }
}

enum SpeechModel {
    /// SpeechTranscriber is Apple's newer long-form model; DictationTranscriber covers more languages (e.g. Arabic).
    static func module(for locale: Locale) async throws -> any SpeechModule {
        if let match = await SpeechTranscriber.supportedLocale(equivalentTo: locale),
           await SpeechTranscriber.supportedLocales.contains(where: { $0.identifier == match.identifier }) {
            return SpeechTranscriber(locale: match, transcriptionOptions: [], reportingOptions: [.volatileResults],
                                     attributeOptions: [.audioTimeRange])
        }
        if let match = await DictationTranscriber.supportedLocale(equivalentTo: locale) {
            return DictationTranscriber(locale: match, contentHints: [], transcriptionOptions: [.punctuation],
                                        reportingOptions: [.volatileResults], attributeOptions: [.audioTimeRange])
        }
        throw TerryError.unsupportedLanguage(locale)
    }

    /// The model is downloaded once (needs internet) and reserved so macOS keeps it for offline use.
    static func install(_ module: any SpeechModule) async throws {
        do {
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
                try await request.downloadAndInstall()
            }
        } catch {
            throw TerryError.modelDownload(error)
        }
        if let locale = (module as? any LocaleDependentSpeechModule)?.selectedLocales.first {
            _ = try? await AssetInventory.reserve(locale: locale)
        }
    }

    /// Every language either model can transcribe, sorted by display name.
    static func languages() async -> [Locale] {
        var seen = Set<String>()
        let all = await SpeechTranscriber.supportedLocales + DictationTranscriber.supportedLocales
        return all.filter { seen.insert($0.identifier).inserted }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }
}

extension Locale {
    var displayName: String { Locale.current.localizedString(forIdentifier: identifier) ?? identifier }
}

enum TerryError: LocalizedError {
    case microphoneDenied
    case noMicrophone
    case unsupportedLanguage(Locale)
    case modelDownload(Error)

    var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            "Terry needs microphone access. Allow it in System Settings › Privacy & Security › Microphone."
        case .noMicrophone:
            "No microphone is available."
        case .unsupportedLanguage(let locale):
            "\(locale.displayName) can't be transcribed on this Mac. Choose another language in Settings."
        case .modelDownload:
            "The language model needs a one-time download. Connect to the internet and try again; after that Terry works offline."
        }
    }
}
