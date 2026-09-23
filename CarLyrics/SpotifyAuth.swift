import Foundation
import SpotifyLogin

/// Spotify login (Authorization Code with PKCE, no client secret on the device). The tokens
/// themselves live in SpotifyTokenStore, which the widget shares.
@MainActor
final class SpotifyAuth: NSObject, ObservableObject {
    @Published private(set) var isLoggedIn: Bool

    override init() {
        SpotifyTokenStore.migrate(fromService: Config.bundleID + ".spotify")
        if let imported = Self.importFromMac() { SpotifyTokenStore.save(imported) }
        isLoggedIn = SpotifyTokenStore.load() != nil
        super.init()
    }

    /// `tools/login_on_mac.py` drops Documents/spotify_import.json into the app container
    /// when logging in on the phone isn't working. Consumed once, then deleted.
    private static func importFromMac() -> SpotifyTokens? {
        let url = URL.documentsDirectory.appending(path: "spotify_import.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        try? FileManager.default.removeItem(at: url)
        struct Import: Decodable { let refresh_token: String }
        guard let imported = try? JSONDecoder().decode(Import.self, from: data) else { return nil }
        // Expired on purpose: the first API call refreshes it into a real access token.
        return SpotifyTokens(accessToken: "", refreshToken: imported.refresh_token, expiresAt: .distantPast)
    }

    /// Logs in through the Spotify app when it's installed (you just tap Agree), and falls
    /// back to Spotify's web login otherwise. Spotify's SpotifyLogin package handles PKCE.
    func logIn() async throws {
        guard Config.isSpotifyConfigured else { throw SpotifyAuthError.notConfigured }
        let session: Session = try await withCheckedThrowingContinuation { cont in
            loginContinuation = cont
            sessionManager.initiateSession(with: [.userReadCurrentlyPlaying, .userReadPlaybackState])
        }
        SpotifyTokenStore.save(SpotifyTokens(accessToken: session.accessToken, refreshToken: session.refreshToken,
                                             expiresAt: session.expirationDate))
        isLoggedIn = true
    }

    /// The Spotify app sends the login back to carlyrics://callback.
    func handle(_ url: URL) {
        _ = sessionManager.openURL(url)
    }

    private lazy var sessionManager = SessionManager(
        configuration: SpotifyLogin.Configuration(clientID: Config.spotifyClientID,
                                                  redirectURL: URL(string: Config.redirectURI)!),
        delegate: self
    )
    private var loginContinuation: CheckedContinuation<Session, Error>?

    func logOut() {
        SpotifyTokenStore.save(nil)
        isLoggedIn = false
    }

    /// Returns a non-expired access token, refreshing if needed.
    func accessToken(forceRefresh: Bool = false) async throws -> String {
        do {
            return try await SpotifyTokenStore.accessToken(forceRefresh: forceRefresh, canLogOut: true)
        } catch SpotifyAuthError.notLoggedIn {
            isLoggedIn = false
            throw SpotifyAuthError.notLoggedIn
        }
    }
}

extension SpotifyAuth: SessionManagerDelegate {
    nonisolated func sessionManager(manager: SessionManager, didInitiate session: Session) {
        Task { @MainActor in
            self.loginContinuation?.resume(returning: session)
            self.loginContinuation = nil
        }
    }

    nonisolated func sessionManager(manager: SessionManager, didFailWith error: Error) {
        Task { @MainActor in
            self.loginContinuation?.resume(throwing: error)
            self.loginContinuation = nil
        }
    }
}
