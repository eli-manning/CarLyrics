import Foundation

enum Config {
    /// Spotify app from https://developer.spotify.com/dashboard (the same one the
    /// ~/Code/Projects/Spotify scripts use). Its settings must list the redirect URI below.
    static let spotifyClientID = "c74ded3599f44bdd9f7f187aab5a5beb"
    static let redirectScheme = "carlyrics"
    static let redirectURI = "carlyrics://callback"
    static let scopes = "user-read-currently-playing user-read-playback-state"
}
