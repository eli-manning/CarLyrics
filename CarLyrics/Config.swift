import Foundation

/// Per-person values come from Config.xcconfig through Info.plist, so nobody has to edit code.
enum Config {
    static let spotifyClientID = Bundle.main.object(forInfoDictionaryKey: "SpotifyClientID") as? String ?? ""
    static let bundleID = Bundle.main.bundleIdentifier ?? "carlyrics"
    static let redirectScheme = "carlyrics"
    static let redirectURI = "carlyrics://callback"
    static let scopes = "user-read-currently-playing user-read-playback-state"

    static var isSpotifyConfigured: Bool { !spotifyClientID.isEmpty && spotifyClientID != "your_spotify_client_id" }
}
