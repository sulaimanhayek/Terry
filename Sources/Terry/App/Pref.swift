import Foundation

/// UserDefaults keys, shared by @AppStorage in views and by model code.
enum Pref {
    static let folder = "notesFolder"
    static let language = "language"           // locale identifier; empty = system language
    static let systemAudio = "captureSystemAudio"
    static let meetingPrompt = "meetingPrompt"
    static let appearance = "appearance"       // "system", "light" or "dark"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [systemAudio: true, meetingPrompt: true, appearance: "system"])
    }

    static var locale: Locale {
        let id = UserDefaults.standard.string(forKey: language) ?? ""
        return id.isEmpty ? .current : Locale(identifier: id)
    }
}
