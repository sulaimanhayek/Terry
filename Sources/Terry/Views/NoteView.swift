import SwiftUI

struct NoteView: View {
    let note: Note
    @Environment(NoteStore.self) private var store

    var body: some View {
        let (title, paragraphs) = NoteFormat.parse(store.text(of: note))
        TranscriptView(title: title ?? note.title, paragraphs: paragraphs)
            .toolbar {
                ToolbarItemGroup { NoteActions(note: note) }
            }
    }
}

struct LiveView: View {
    @Environment(Recorder.self) private var recorder

    var body: some View {
        let paragraphs = recorder.transcript.paragraphs(includingVolatile: true)
        TranscriptView(title: nil, paragraphs: paragraphs)
            .defaultScrollAnchor(.bottom, for: .sizeChanges)
            .overlay {
                if paragraphs.isEmpty {
                    ContentUnavailableView("Listening…", systemImage: "waveform",
                                           description: Text("Text appears here as people speak."))
                }
            }
    }
}

private struct TranscriptView: View {
    let title: String?
    let paragraphs: [Paragraph]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                if let title {
                    Text(title).font(.title2.weight(.semibold)).padding(.bottom, 4)
                }
                ForEach(paragraphs.indices, id: \.self) { i in
                    ParagraphView(paragraph: paragraphs[i])
                }
            }
            .textSelection(.enabled)
            .frame(maxWidth: 680, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct ParagraphView: View {
    let paragraph: Paragraph

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if paragraph.speaker != nil || paragraph.start != nil {
                HStack(spacing: 6) {
                    if let speaker = paragraph.speaker {
                        Text(speaker).fontWeight(.semibold)
                            .foregroundStyle(speaker == Speaker.me.rawValue ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    }
                    if let start = paragraph.start { Text(start.timestamp).monospacedDigit() }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Text("\(paragraph.text)\(paragraph.text.isEmpty || paragraph.pending.isEmpty ? "" : " ")\(Text(paragraph.pending).foregroundStyle(.tertiary))")
                .font(.body)
                .lineSpacing(3)
        }
    }
}

struct NoteActions: View {
    let note: Note
    @Environment(NoteStore.self) private var store

    var body: some View {
        Button("Copy Text", systemImage: "doc.on.doc") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(store.text(of: note), forType: .string)
        }
        Button("Show in Finder", systemImage: "folder") {
            NSWorkspace.shared.activateFileViewerSelecting([note.url])
        }
        Button("Move to Trash", systemImage: "trash") {
            try? store.trash(note)
        }
    }
}
