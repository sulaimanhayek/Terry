import AVFoundation
import Foundation
import Testing
@testable import Terry

/// Renders speech to a file with `say` (nothing is played aloud).
func spokenAudio(_ text: String, voice: String = "Samantha") throws -> AVAudioFile {
    let url = FileManager.default.temporaryDirectory.appending(path: "terry-\(UUID().uuidString).aiff")
    let say = Process()
    say.executableURL = URL(filePath: "/usr/bin/say")
    say.arguments = ["-v", voice, "-o", url.path, text]
    try say.run()
    say.waitUntilExit()
    defer { try? FileManager.default.removeItem(at: url) }
    return try AVAudioFile(forReading: url)
}

/// Feeds a file in 100 ms buffers, stamping each with a host time as a live source would.
func feed(_ file: AVAudioFile, from hostTime: TimeInterval, to onBuffer: (AVAudioPCMBuffer, TimeInterval?) -> Void) throws {
    let format = file.processingFormat
    let chunk = AVAudioFrameCount(format.sampleRate / 10)
    while file.framePosition < file.length {
        let time = hostTime + Double(file.framePosition) / format.sampleRate
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk)!
        try file.read(into: buffer, frameCount: chunk)
        onBuffer(buffer, time)
    }
}

/// Needs the on-device model, which CI runners don't have (and would have to download).
let speechModelAvailable = ProcessInfo.processInfo.environment["CI"] == nil

@Suite(.enabled(if: speechModelAvailable), .serialized) @MainActor
struct LiveTranscriberTests {
    @Test func transcribesAndKeepsTimelineAcrossGaps() async throws {
        let locale = Locale(identifier: "en_US")
        let first = try spokenAudio("The quick brown fox jumps over the lazy dog.")
        let second = try spokenAudio("Please send the quarterly report by Friday.")
        let firstDuration = Double(first.length) / first.processingFormat.sampleRate

        var transcript = Transcript()
        let origin: TimeInterval = 1_000
        let transcriber = LiveTranscriber(speaker: .me)
        try await transcriber.start(locale: locale) { transcript.apply($0, isFinal: $1) }
        transcriber.origin = origin
        try feed(first, from: origin) { transcriber.append($0, hostTime: $1) }
        try feed(second, from: origin + firstDuration + 5) { transcriber.append($0, hostTime: $1) }  // 5 s gap, e.g. a device switch
        await transcriber.finish()

        let text = transcript.segments.map(\.text).joined(separator: " ").lowercased()
        #expect(text.contains("quick brown fox"))
        #expect(text.contains("quarterly report"))
        let report = try #require(transcript.segments.first { $0.text.lowercased().contains("quarterly") })
        #expect(report.start > firstDuration + 3)  // ranges can include ~1 s of lead-in silence
    }
}
