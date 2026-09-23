import Foundation

/// Transcripts are plain Markdown, so they open in any editor and sync with any cloud folder:
///
///     # Zoom · 23 Sep 2026 at 22:10
///
///     **Me** · 00:00
///     Shall we start?
///
///     **Them** · 00:04
///     Yes, let's go.
///
/// Single-speaker transcripts use `**00:00**` headings. Parsing is lenient so edits made
/// elsewhere survive: text between headings belongs to the heading above it.
enum NoteFormat {
    static func title(date: Date, app: String?) -> String {
        let when = date.formatted(date: .abbreviated, time: .shortened)
        return app.map { "\($0) · \(when)" } ?? when
    }

    static func markdown(title: String, paragraphs: [Paragraph]) -> String {
        var text = "# \(title)\n"
        for p in paragraphs {
            let time = (p.start ?? 0).timestamp
            text += "\n" + (p.speaker.map { "**\($0)** · \(time)" } ?? "**\(time)**") + "\n" + p.text + "\n"
        }
        return text
    }

    static func parse(_ markdown: String) -> (title: String?, paragraphs: [Paragraph]) {
        var title: String?
        var paragraphs: [Paragraph] = []
        var body: [Substring] = []

        func flush() {
            let text = body.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            body = []
            if paragraphs.isEmpty || !paragraphs[paragraphs.count - 1].text.isEmpty {
                if !text.isEmpty { paragraphs.append(Paragraph(speaker: nil, start: nil, text: text)) }
            } else {
                paragraphs[paragraphs.count - 1].text = text
            }
        }

        for line in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            if title == nil, paragraphs.isEmpty, body.allSatisfy(\.isEmpty), line.hasPrefix("# ") {
                title = line.dropFirst(2).trimmingCharacters(in: .whitespaces)
            } else if let (speaker, start) = heading(line) {
                flush()
                paragraphs.append(Paragraph(speaker: speaker, start: start, text: ""))
            } else {
                body.append(line)
            }
        }
        flush()
        return (title, paragraphs.filter { !$0.text.isEmpty })
    }

    /// `**Me** · 01:23` or `**01:23**`.
    private static func heading(_ line: Substring) -> (String?, TimeInterval)? {
        let line = line.trimmingCharacters(in: .whitespaces)
        guard let match = line.wholeMatch(of: #/\*\*([^*]+)\*\*(?: · ([\d:]+))?/#) else { return nil }
        if let time = match.2.flatMap(seconds) { return (String(match.1), time) }
        if match.2 == nil, let time = seconds(match.1) { return (nil, time) }
        return nil
    }

    private static func seconds(_ text: Substring) -> TimeInterval? {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false).map { Int($0) }
        guard (2...3).contains(parts.count), !parts.contains(nil) else { return nil }
        return TimeInterval(parts.reduce(0) { $0 * 60 + $1! })
    }
}
