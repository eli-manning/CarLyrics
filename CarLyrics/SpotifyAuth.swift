import Foundation
import Security
import SpotifyLogin

struct SpotifyTokens: Codable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
}

enum SpotifyAuthError: LocalizedError {
    case notLoggedIn, notConfigured, badCallback, tokenExchange(String)
    var errorDescription: String? {
        switch self {
        case .notLoggedIn: "Not logged in to Spotify."
        case .notConfigured: "No Spotify client ID set. Add yours to Config.xcconfig and rebuild."
        case .badCallback: "Spotify login was canceled."
        case .tokenExchange(let msg): "Spotify didn't accept the login. \(msg)"
        }
    }
}

/// Spotify login (Authorization Code with PKCE, no client secret on the device) and token refresh.
@MainActor
final class SpotifyAuth: NSObject, ObservableObject {
    @Published private(set) var isLoggedIn: Bool

    private var tokens: SpotifyTokens? {
        didSet { isLoggedIn = tokens != nil; Keychain.save(tokens) }
    }
    private var refreshTask: Task<SpotifyTokens, Error>?

    override init() {
        let stored = Self.importFromMac() ?? Keychain.load()
        tokens = stored
        isLoggedIn = stored != nil
        super.init()
        Keychain.save(stored)
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
        tokens = SpotifyTokens(accessToken: session.accessToken, refreshToken: session.refreshToken,
                               expiresAt: session.expirationDate)
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

    func logOut() { tokens = nil }

    /// Returns a non-expired access token, refreshing if needed.
    func accessToken(forceRefresh: Bool = false) async throws -> String {
        guard let current = tokens else { throw SpotifyAuthError.notLoggedIn }
        if !forceRefresh, current.expiresAt.timeIntervalSinceNow > 60 { return current.accessToken }

        if let refreshTask { return try await refreshTask.value.accessToken }
        let task = Task {
            try await requestTokens([
                "grant_type": "refresh_token",
                "refresh_token": current.refreshToken,
                "client_id": Config.spotifyClientID,
            ], previousRefresh: current.refreshToken)
        }
        refreshTask = task
        defer { refreshTask = nil }
        do {
            let fresh = try await task.value
            tokens = fresh
            return fresh.accessToken
        } catch SpotifyAuthError.tokenExchange(let msg) where msg.contains("invalid_grant") {
            tokens = nil
            throw SpotifyAuthError.notLoggedIn
        }
    }

    private func requestTokens(_ form: [String: String], previousRefresh: String?) async throws -> SpotifyTokens {
        var req = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = form.map { "\($0.key)=\($0.value.formEncoded)" }.joined(separator: "&").data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw SpotifyAuthError.tokenExchange(String(decoding: data, as: UTF8.self))
        }
        struct Resp: Decodable { let access_token: String; let refresh_token: String?; let expires_in: Double }
        let r = try JSONDecoder().decode(Resp.self, from: data)
        guard let refresh = r.refresh_token ?? previousRefresh else {
            throw SpotifyAuthError.tokenExchange("no refresh token returned")
        }
        return SpotifyTokens(accessToken: r.access_token, refreshToken: refresh,
                             expiresAt: Date().addingTimeInterval(r.expires_in))
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

private extension String {
    var formEncoded: String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }
}

private enum Keychain {
    static let service = Config.bundleID + ".spotify"

    static func save(_ tokens: SpotifyTokens?) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service]
        SecItemDelete(query as CFDictionary)
        guard let tokens, let data = try? JSONEncoder().encode(tokens) else { return }
        var add = query
        add[kSecValueData as String] = data
        // Readable while the phone is locked in the car after first unlock.
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func load() -> SpotifyTokens? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecReturnData as String: true]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return try? JSONDecoder().decode(SpotifyTokens.self, from: data)
    }
}
