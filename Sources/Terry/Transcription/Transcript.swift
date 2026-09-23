import Foundation

enum Speaker: String, Sendable {
    case me = "Me"
    case them = "Them"
}

/// One recognized utterance. Times are seconds from the start of the recording.
struct Segment: Equatable, Sendable {
    var speaker: Speaker
    var start: TimeInterval
    var end: TimeInterval
    var text: String
}

/// A display/save unit: consecutive segments from one speaker. `pending` holds not-yet-final text.
/// `start` is nil for text without a timestamp (e.g. typed into a saved note by hand).
struct Paragraph: Equatable {
    var speaker: String?
    var start: TimeInterval?
    var text: String
    var pending = ""
}

/// Live transcript merged from two independent streams: the mic (me) and system audio (them).
struct Transcript {
    private(set) var segments: [Segment] = []
    private(set) var volatile: [Speaker: Segment] = [:]

    var isEmpty: Bool { segments.isEmpty }

    mutating func apply(_ segment: Segment, isFinal: Bool) {
        guard isFinal else {
            volatile[segment.speaker] = segment.text.isEmpty ? nil : segment
            return
        }
        volatile[segment.speaker] = nil
        guard !segment.text.isEmpty, !isEcho(segment) else { return }
        segments.insert(segment, at: segments.firstIndex { $0.start > segment.start } ?? segments.endIndex)
        if segment.speaker == .them {
            segments = segments.filter { !($0.speaker == .me && Self.near($0, segment) && isEcho($0)) }
        }
    }

    /// Paragraph breaks on a speaker change, a pause, or after a minute of continuous speech.
    func paragraphs(includingVolatile: Bool = false) -> [Paragraph] {
        let labeled = Set(segments.map(\.speaker)).count > 1
        var items = segments.map { ($0, false) }
        if includingVolatile {
            items += volatile.values.sorted { $0.start < $1.start }.map { ($0, true) }
        }
        var result: [Paragraph] = []
        var last: Segment?
        for (segment, isPending) in items {
            if let last, let paragraph = result.last, last.speaker == segment.speaker,
               segment.start - last.end < 3, segment.start - (paragraph.start ?? 0) < 60 {
                if isPending {
                    result[result.count - 1].pending = segment.text
                } else {
                    result[result.count - 1].text += " " + segment.text
                }
            } else {
                result.append(Paragraph(speaker: labeled ? segment.speaker.rawValue : nil, start: segment.start,
                                        text: isPending ? "" : segment.text, pending: isPending ? segment.text : ""))
            }
            last = segment
        }
        return result
    }

    /// Without headphones the mic also hears the other side. Mic text whose words mostly
    /// appear in nearby system-audio text is treated as that echo and dropped.
    private func isEcho(_ segment: Segment) -> Bool {
        guard segment.speaker == .me else { return false }
        let mine = Self.words(segment.text)
        guard !mine.isEmpty else { return false }
        let theirs = segments.lazy.filter { $0.speaker == .them && Self.near($0, segment) }
            .reduce(into: Set<String>()) { $0.formUnion(Self.words($1.text)) }
        return Double(mine.intersection(theirs).count) / Double(mine.count) >= 0.6
    }

    private static func near(_ a: Segment, _ b: Segment) -> Bool {
        a.start < b.end + 3 && b.start < a.end + 3
    }

    private static func words(_ text: String) -> Set<String> {
        Set(text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
    }
}

extension TimeInterval {
    /// "04:07", or "1:04:07" past an hour.
    var timestamp: String {
        let s = Int(self)
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
                         : String(format: "%02d:%02d", s / 60, s % 60)
    }
}
