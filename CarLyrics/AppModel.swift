import Foundation

/// One shared auth + engine, used by the app's UI and by the Shortcuts actions
/// (which can run while the app is in the background).
@MainActor
enum AppModel {
    static let auth = SpotifyAuth()
    static let engine = LyricsEngine(auth: auth)
}
