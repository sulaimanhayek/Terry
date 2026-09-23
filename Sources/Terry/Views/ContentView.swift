import SwiftUI

struct ContentView: View {
    @Environment(NoteStore.self) private var store
    @Environment(Recorder.self) private var recorder
    @State private var selection: URL?
    @State private var query = ""

    /// The note being recorded, shown live instead of from its file.
    private var liveURL: URL? { recorder.state == .idle ? nil : recorder.noteURL }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                if let liveURL {
                    LiveRow().tag(liveURL)
                }
                ForEach(store.search(query).filter { $0.url != liveURL }) { note in
                    NoteRow(note: note).tag(note.url)
                }
            }
            .searchable(text: $query, placement: .sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 400)
        } detail: {
            if let selection, selection == liveURL {
                LiveView()
            } else if let note = store.notes.first(where: { $0.url == selection }) {
                NoteView(note: note)
            } else if store.notes.isEmpty {
                ContentUnavailableView("No Transcripts", systemImage: "waveform",
                                       description: Text("Press ⌘R to start transcribing."))
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) { RecordButton() }
        }
        .onAppear { selection = selection ?? liveURL ?? store.notes.first?.url }
        .onChange(of: recorder.noteURL) { _, url in
            if let url { selection = url }
        }
        .alert("Couldn't Transcribe", isPresented: Binding { recorder.error != nil } set: { if !$0 { recorder.error = nil } },
               presenting: recorder.error) { _ in } message: { Text($0.localizedDescription) }
    }
}

private struct NoteRow: View {
    let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(note.title).lineLimit(1)
            if !note.preview.isEmpty {
                Text(note.preview).font(.callout).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.vertical, 2)
        .contextMenu { NoteActions(note: note) }
    }
}

private struct LiveRow: View {
    @Environment(Recorder.self) private var recorder

    var body: some View {
        HStack {
            Circle().fill(.red).frame(width: 8, height: 8)
            Text(recorder.meetingApp ?? "Recording").lineLimit(1)
            Spacer()
            if let start = recorder.startedAt {
                Text(timerInterval: start...Date.distantFuture, countsDown: false)
                    .monospacedDigit().foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct RecordButton: View {
    @Environment(Recorder.self) private var recorder

    var body: some View {
        switch recorder.state {
        case .idle:
            Button("Record", systemImage: "record.circle") { recorder.toggle() }
                .help("Start transcribing (⌘R)")
        case .starting, .stopping:
            ProgressView().controlSize(.small).padding(.horizontal, 8)
        case .recording:
            Button("Stop", systemImage: "stop.circle.fill") { recorder.toggle() }
                .foregroundStyle(.red)
                .help("Stop transcribing (⌘R)")
        }
    }
}

struct RecordMenuItem: View {
    @Environment(Recorder.self) private var recorder
    @Environment(\.openWindow) private var openWindow
    /// Show the live transcript when recording starts (used from the menu bar).
    var opensWindow = false

    var body: some View {
        Button(recorder.state == .idle ? "Start Transcribing" : "Stop Transcribing") {
            if opensWindow, recorder.state == .idle { openWindow(id: "main") }
            recorder.toggle()
        }
        .keyboardShortcut("r")
        .disabled(recorder.state == .starting || recorder.state == .stopping)
    }
}
