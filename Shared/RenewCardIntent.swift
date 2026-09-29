import AppIntents

/// Tapping the lyrics card runs this. iOS rations a card's updates, and after a while it
/// only redraws every ~10 seconds; a fresh card starts over. Like Start Lyrics, it's a
/// LiveActivityIntent, so it runs in the app and may start a card from the background.
/// It's compiled into the widget too (the card's button needs it), but only the app
/// sets `run`.
struct RenewCardIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Refresh Lyrics Card"
    static let isDiscoverable = false

    @MainActor static var run: (() -> Void)?

    @MainActor
    func perform() async throws -> some IntentResult {
        Self.run?()
        return .result()
    }
}
