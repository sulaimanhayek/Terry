import Foundation
import Testing
@testable import Terry

/// A fresh, empty notes folder that is deleted afterwards.
func withTempFolder(_ body: (URL) async throws -> Void) async throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: "terry-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: folder) }
    try await body(folder)
}

/// Polls until `condition` holds, for things that happen asynchronously (e.g. file events).
@MainActor func eventually(timeout: Duration = .seconds(3), _ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while !condition(), ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(50)) }
    return condition()
}

@Suite @MainActor struct NoteStoreTests {
    @Test func namesNotesByDateWithoutClobbering() async throws {
        try await withTempFolder { folder in
            let store = NoteStore(folder: folder)
            let date = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 22, minute: 10)))
            let first = store.newNoteURL(for: date)
            #expect(first.lastPathComponent == "2026-09-23 22.10.md")
            try store.write("# A\n\n**00:00**\nHello.\n", to: first)
            #expect(store.newNoteURL(for: date).lastPathComponent == "2026-09-23 22.10 2.md")

            let note = try #require(store.notes.first)
            #expect(note.title == "A")
            #expect(note.preview == "Hello.")
            #expect(note.date == date)
        }
    }

    @Test func listsNewestFirstAndSearchesText() async throws {
        try await withTempFolder { folder in
            let store = NoteStore(folder: folder)
            try store.write("# Old\n\n**00:00**\nBudget review.\n", to: folder.appending(path: "2026-01-01 09.00.md"))
            try store.write("# New\n\n**00:00**\nRoadmap.\n", to: folder.appending(path: "2026-02-01 09.00.md"))
            try store.write("Plain text, no heading.", to: folder.appending(path: "Ideas.md"))
            try store.write("ignored", to: folder.appending(path: "notes.txt"))
            // Files not named by date fall back to their creation date (just now).
            #expect(store.notes.map(\.title) == ["Ideas", "New", "Old"])
            #expect(store.notes.first?.preview == "Plain text, no heading.")
            #expect(store.search("budget").map(\.title) == ["Old"])
            #expect(store.search(" ").count == 3)
        }
    }

    @Test func picksUpFilesChangedElsewhere() async throws {
        try await withTempFolder { folder in
            let store = NoteStore(folder: folder)
            let url = folder.appending(path: "Synced.md")
            try "# From another Mac".write(to: url, atomically: true, encoding: .utf8)
            #expect(await eventually { store.notes.first?.title == "From another Mac" })
            try FileManager.default.removeItem(at: url)
            #expect(await eventually { store.notes.isEmpty })
        }
    }
}
