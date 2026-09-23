import Foundation

struct Note: Identifiable, Hashable {
    let url: URL
    var title: String
    var date: Date
    var preview: String
    var id: URL { url }
}

/// The notes folder is the source of truth: every `.md` file in it is a note, so files synced or
/// edited elsewhere (iCloud Drive, Google Drive, any editor) show up here as they change.
@MainActor @Observable
final class NoteStore {
    private(set) var folder: URL
    private(set) var notes: [Note] = []
    private var cache: [URL: (modified: Date, note: Note, text: String)] = [:]
    private var watcher: DispatchSourceFileSystemObject?

    static var defaultFolder: URL { .documentsDirectory.appending(path: "Terry", directoryHint: .isDirectory) }

    init(folder: URL? = nil) {
        self.folder = folder
            ?? UserDefaults.standard.string(forKey: Pref.folder).map { URL(filePath: $0, directoryHint: .isDirectory) }
            ?? Self.defaultFolder
        reload()
        watch()
    }

    func setFolder(_ url: URL) {
        UserDefaults.standard.set(url.path, forKey: Pref.folder)
        folder = url
        cache = [:]
        reload()
        watch()
    }

    /// Re-reads only files whose modification date changed.
    func reload() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey], options: .skipsHiddenFiles
        )) ?? []
        var fresh: [URL: (modified: Date, note: Note, text: String)] = [:]
        for url in urls where url.pathExtension == "md" {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
            let modified = values?.contentModificationDate ?? .distantPast
            if let cached = cache[url], cached.modified == modified {
                fresh[url] = cached
            } else if let text = try? String(contentsOf: url, encoding: .utf8) {
                let (title, paragraphs) = NoteFormat.parse(text)
                let date = Self.date(fromFilename: url) ?? values?.creationDate ?? modified
                let preview = String(paragraphs.first?.text.prefix(120) ?? "")
                fresh[url] = (modified, Note(url: url, title: title ?? url.deletingPathExtension().lastPathComponent,
                                             date: date, preview: preview), text)
            }
        }
        cache = fresh
        let notes = fresh.values.map(\.note).sorted { $0.date > $1.date }
        if notes != self.notes { self.notes = notes }
    }

    func text(of note: Note) -> String { cache[note.url]?.text ?? "" }

    func search(_ query: String) -> [Note] {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return notes }
        return notes.filter { $0.title.localizedStandardContains(query) || text(of: $0).localizedStandardContains(query) }
    }

    /// `2026-09-23 22.10.md`, then `2026-09-23 22.10 2.md` if taken.
    func newNoteURL(for date: Date) -> URL {
        let base = Self.filenameFormat.string(from: date)
        var url = folder.appending(path: base + ".md")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appending(path: "\(base) \(n).md")
            n += 1
        }
        return url
    }

    func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
        reload()
    }

    /// Moves to the Trash, so it can be restored from Finder.
    func trash(_ note: Note) throws {
        try FileManager.default.trashItem(at: note.url, resultingItemURL: nil)
        reload()
    }

    private func watch() {
        watcher?.cancel()
        let fd = open(folder.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.reload() } }
        source.setCancelHandler { close(fd) }
        source.resume()
        watcher = source
    }

    private static let filenameFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH.mm"
        return f
    }()

    private static func date(fromFilename url: URL) -> Date? {
        filenameFormat.date(from: String(url.deletingPathExtension().lastPathComponent.prefix(16)))
    }
}
