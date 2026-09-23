import Foundation
import Testing
@testable import Terry

private func seg(_ speaker: Speaker, _ start: Double, _ end: Double, _ text: String) -> Segment {
    Segment(speaker: speaker, start: start, end: end, text: text)
}

@Suite struct TranscriptTests {
    @Test func finalReplacesVolatile() {
        var t = Transcript()
        t.apply(seg(.me, 0, 1, "hello wor"), isFinal: false)
        #expect(t.volatile[.me]?.text == "hello wor")
        t.apply(seg(.me, 0, 1.2, "Hello world."), isFinal: true)
        #expect(t.volatile[.me] == nil)
        #expect(t.segments.map(\.text) == ["Hello world."])
    }

    @Test func segmentsStaySortedAcrossSpeakers() {
        var t = Transcript()
        t.apply(seg(.them, 5, 6, "Second."), isFinal: true)
        t.apply(seg(.me, 1, 2, "First."), isFinal: true)
        t.apply(seg(.me, 9, 10, "Third."), isFinal: true)
        #expect(t.segments.map(\.text) == ["First.", "Second.", "Third."])
    }

    @Test func dropsEchoOfOtherSideEitherOrder() {
        var a = Transcript()
        a.apply(seg(.them, 10, 14, "Let's review the budget for next quarter."), isFinal: true)
        a.apply(seg(.me, 10.2, 14.1, "let's review the budget for next"), isFinal: true)
        #expect(a.segments.map(\.speaker) == [.them])

        var b = Transcript()
        b.apply(seg(.me, 10.2, 14.1, "let's review the budget for next"), isFinal: true)
        b.apply(seg(.them, 10, 14, "Let's review the budget for next quarter."), isFinal: true)
        #expect(b.segments.map(\.speaker) == [.them])
    }

    @Test func keepsGenuineReplies() {
        var t = Transcript()
        t.apply(seg(.them, 10, 14, "Let's review the budget for next quarter."), isFinal: true)
        t.apply(seg(.me, 14.5, 16, "Sounds good, I'll share my screen."), isFinal: true)
        #expect(t.segments.count == 2)
    }

    @Test func paragraphsBreakOnSpeakerPauseAndLength() {
        var t = Transcript()
        t.apply(seg(.me, 0, 2, "One."), isFinal: true)
        t.apply(seg(.me, 2.5, 4, "Two."), isFinal: true)
        t.apply(seg(.them, 4.5, 6, "Three."), isFinal: true)
        t.apply(seg(.them, 12, 13, "After a pause."), isFinal: true)
        let p = t.paragraphs()
        #expect(p.map(\.text) == ["One. Two.", "Three.", "After a pause."])
        #expect(p.map(\.speaker) == ["Me", "Them", "Them"])

        var long = Transcript()
        for i in 0..<40 { long.apply(seg(.me, Double(i * 2), Double(i * 2 + 2), "word"), isFinal: true) }
        #expect(long.paragraphs().count == 2)
    }

    @Test func singleSpeakerIsUnlabeled() {
        var t = Transcript()
        t.apply(seg(.me, 0, 1, "Just me."), isFinal: true)
        #expect(t.paragraphs().first?.speaker == nil)
    }

    @Test func pendingTextJoinsItsParagraph() {
        var t = Transcript()
        t.apply(seg(.me, 0, 2, "Hello there."), isFinal: true)
        t.apply(seg(.me, 2.2, 3, "how are"), isFinal: false)
        let p = t.paragraphs(includingVolatile: true)
        #expect(p.count == 1)
        #expect(p[0].text == "Hello there.")
        #expect(p[0].pending == "how are")
    }

    @Test func timestamps() {
        #expect(TimeInterval(0).timestamp == "00:00")
        #expect(TimeInterval(247.9).timestamp == "04:07")
        #expect(TimeInterval(3847).timestamp == "1:04:07")
    }
}
