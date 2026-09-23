import AppIntents

/// iOS won't let an app start a Live Activity from the background, except from an
/// intent like this one. Run it from a Shortcuts automation such as "When CarPlay
/// connects" and the card appears even if CarLyrics isn't open.
struct StartLyricsIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Start Lyrics"
    static let description = IntentDescription(
        "Shows the CarLyrics card on the Lock Screen and in CarPlay. It stays up, even while music is paused, until you run Stop Lyrics."
    )

    @MainActor
    func perform() async throws -> some IntentResult {
        let engine = AppModel.engine
        guard engine.auth.isLoggedIn else {
            throw IntentError.notLoggedIn
        }
        engine.startLiveActivity(keepUp: true)
        return .result()
    }
}

struct StopLyricsIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop Lyrics"
    static let description = IntentDescription("Removes the CarLyrics card and stops syncing in the background.")

    @MainActor
    func perform() async throws -> some IntentResult {
        AppModel.engine.stopLiveActivity()
        return .result()
    }
}

enum IntentError: Error, CustomLocalizedStringResourceConvertible {
    case notLoggedIn
    var localizedStringResource: LocalizedStringResource {
        "Open CarLyrics and connect Spotify first."
    }
}

struct CarLyricsShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartLyricsIntent(), phrases: ["Start lyrics in \(.applicationName)"],
                    shortTitle: "Start Lyrics", systemImageName: "quote.bubble")
        AppShortcut(intent: StopLyricsIntent(), phrases: ["Stop lyrics in \(.applicationName)"],
                    shortTitle: "Stop Lyrics", systemImageName: "xmark.circle")
    }
}
