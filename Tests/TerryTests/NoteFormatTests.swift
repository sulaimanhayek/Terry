import Foundation
import Testing
@testable import Terry

@Suite struct NoteFormatTests {
    @Test func roundTripsSpeakers() {
        let paragraphs = [
            Paragraph(speaker: "Me", start: 0, text: "Shall we start?"),
            Paragraph(speaker: "Them", start: 4, text: "Yes, let's go."),
            Paragraph(speaker: "Me", start: 3725, text: "Wrapping up."),
        ]
        let markdown = NoteFormat.markdown(title: "Zoom · 23 Sep 2026 at 22:10", paragraphs: paragraphs)
        #expect(markdown == """
            # Zoom · 23 Sep 2026 at 22:10

            **Me** · 00:00
            Shall we start?

            **Them** · 00:04
            Yes, let's go.

            **Me** · 1:02:05
            Wrapping up.

            """)
        let parsed = NoteFormat.parse(markdown)
        #expect(parsed.title == "Zoom · 23 Sep 2026 at 22:10")
        #expect(parsed.paragraphs == paragraphs)
    }

    @Test func roundTripsSingleSpeaker() {
        let paragraphs = [Paragraph(speaker: nil, start: 0, text: "One."), Paragraph(speaker: nil, start: 75, text: "Two.")]
        let markdown = NoteFormat.markdown(title: "Note", paragraphs: paragraphs)
        #expect(markdown.contains("**01:15**\nTwo."))
        #expect(NoteFormat.parse(markdown).paragraphs == paragraphs)
    }

    @Test func parsesHandEditedNotes() {
        let parsed = NoteFormat.parse("""
            Some text typed before any heading.

            **Me** · 00:10

            First line.
            Second line.

            **Them** · 00:20
            **Me** · 00:30
            Last.
            """)
        #expect(parsed.title == nil)
        #expect(parsed.paragraphs == [
            Paragraph(speaker: nil, start: nil, text: "Some text typed before any heading."),
            Paragraph(speaker: "Me", start: 10, text: "First line.\nSecond line."),
            Paragraph(speaker: "Me", start: 30, text: "Last."),
        ])
    }

    @Test func boldTextIsNotAHeading() {
        let parsed = NoteFormat.parse("# T\n\n**Important** point")
        #expect(parsed.paragraphs.map(\.text) == ["**Important** point"])
    }

    @Test func titles() {
        let date = Date(timeIntervalSince1970: 0)
        #expect(NoteFormat.title(date: date, app: "Zoom").hasPrefix("Zoom · "))
        #expect(!NoteFormat.title(date: date, app: nil).contains("·"))
    }
}
