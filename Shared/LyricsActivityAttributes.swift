import ActivityKit
import SwiftUI

/// Shared between the app (which starts/updates the activity) and the widget
/// extension (which renders it on the Lock Screen, Dynamic Island and CarPlay).
struct LyricsActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var title: String
        var artist: String
        var previousLine: String
        var currentLine: String
        var nextLine: String
        var isPlaying: Bool
        var isSynced: Bool
        /// When the current line started/ends, so the widget can animate a
        /// progress bar through the line without extra updates.
        var lineStart: Date
        var lineEnd: Date
        var songStart: Date
        var songEnd: Date
        /// Background color pulled from the album art, as "RRGGBB".
        var tintHex: String

        static let idle = ContentState(
            title: "Nothing playing", artist: "Play something on Spotify",
            previousLine: "", currentLine: "Waiting for a song", nextLine: "",
            isPlaying: false, isSynced: true,
            lineStart: .now, lineEnd: .now.addingTimeInterval(1),
            songStart: .now, songEnd: .now.addingTimeInterval(1),
            tintHex: Color.defaultTintHex
        )
    }
}

extension Color {
    static let defaultTintHex = "26262B"

    init(hex: String) {
        let v = UInt64(hex, radix: 16) ?? 0x26262B
        self.init(red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255)
    }
}
