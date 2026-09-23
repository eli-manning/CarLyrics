import Foundation
import Security

/// What the app hands the home screen / CarPlay widget: the song, its lyric timings, and
/// when it started. The widget turns that into one timeline entry per line, so iOS can
/// move through the song on schedule even while the app is suspended.
struct WidgetSong: Codable, Equatable {
    struct Line: Codable, Equatable {
        var time: TimeInterval
        var text: String
    }

    var title: String
    var artist: String
    var tintHex: String
    /// Wall-clock time at song position 0 (includes the user's timing offset).
    var songStart: Date
    var duration: TimeInterval
    var isPlaying: Bool
    var lines: [Line]
    /// Shown instead of lyrics when there aren't any ("Couldn't find lyrics…").
    var message: String?
    /// The user's timing offset, so the widget can apply it when it looks songs up itself.
    var offsetMs: Double = 0

    var songEnd: Date { songStart.addingTimeInterval(duration) }

    func index(at date: Date) -> Int? {
        let pos = date.timeIntervalSince(songStart)
        return lines.lastIndex { $0.time <= pos }
    }

    /// Same song and lyrics, and the start time moved less than `tolerance` seconds.
    func matches(_ other: WidgetSong, tolerance: TimeInterval = 1.5) -> Bool {
        var a = self, b = other
        a.songStart = .distantPast; b.songStart = .distantPast
        return a == b && abs(songStart.timeIntervalSince(other.songStart)) < tolerance
    }
}

/// Passes the current song from the app to the widget through a keychain item both can
/// read (the team's wildcard provisioning profile allows a shared keychain group, while
/// an App Group would need a new capability registered with Apple).
enum SharedStore {
    static let widgetKind = "LyricsWidget"

    private static var baseQuery: [String: Any] {
        let group = Bundle.main.object(forInfoDictionaryKey: "SharedKeychainGroup") as? String ?? ""
        return [kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "carlyrics.widget",
                kSecAttrAccount as String: "now-playing",
                kSecAttrAccessGroup as String: group]
    }

    static func save(_ song: WidgetSong?) {
        SecItemDelete(baseQuery as CFDictionary)
        guard let song, let data = try? JSONEncoder().encode(song) else { return }
        var add = baseQuery
        add[kSecValueData as String] = data
        // The widget has to read it while the phone is locked in the car.
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func load() -> WidgetSong? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return try? JSONDecoder().decode(WidgetSong.self, from: data)
    }
}
