import ActivityKit
import Foundation

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
        /// When the current line started/ends — lets the widget animate a
        /// karaoke progress bar on its own without extra updates.
        var lineStart: Date
        var lineEnd: Date
        var songStart: Date
        var songEnd: Date

        static let idle = ContentState(
            title: "Nothing playing", artist: "Start a song in Spotify",
            previousLine: "", currentLine: "♪", nextLine: "",
            isPlaying: false, isSynced: true,
            lineStart: .now, lineEnd: .now.addingTimeInterval(1),
            songStart: .now, songEnd: .now.addingTimeInterval(1)
        )
    }
}
