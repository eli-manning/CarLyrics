import Foundation
import Security

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

/// The Spotify login, stored in the keychain group the app and the widget share, so the
/// widget can look up what's playing on its own when the app isn't running.
enum SpotifyTokenStore {
    static var clientID: String { Bundle.main.object(forInfoDictionaryKey: "SpotifyClientID") as? String ?? "" }

    private static let service = "carlyrics.spotify-tokens"
    private static var group: String { Bundle.main.object(forInfoDictionaryKey: "SharedKeychainGroup") as? String ?? "" }
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccessGroup as String: group]
    }

    static func load() -> SpotifyTokens? {
        var q = query
        q[kSecReturnData as String] = true
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return try? JSONDecoder().decode(SpotifyTokens.self, from: data)
    }

    static func save(_ tokens: SpotifyTokens?) {
        SecItemDelete(query as CFDictionary)
        guard let tokens, let data = try? JSONEncoder().encode(tokens) else { return }
        var add = query
        add[kSecValueData as String] = data
        // Readable while the phone is locked in the car, after the first unlock.
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    /// Moves a login saved by an older version (app-only keychain item) into the shared one.
    static func migrate(fromService oldService: String) {
        let old: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: oldService]
        var q = old
        q[kSecReturnData as String] = true
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data,
              let tokens = try? JSONDecoder().decode(SpotifyTokens.self, from: data) else { return }
        if load() == nil { save(tokens) }
        SecItemDelete(old as CFDictionary)
    }

    /// A valid access token, refreshed and saved if needed. Safe to call from the app and the
    /// widget at the same time. Only the app passes `canLogOut`, so a refresh race in the
    /// widget can never log you out.
    static func accessToken(forceRefresh: Bool = false, canLogOut: Bool) async throws -> String {
        try await refresher.token(forceRefresh: forceRefresh, canLogOut: canLogOut)
    }

    private static let refresher = Refresher()

    private actor Refresher {
        private var inFlight: Task<SpotifyTokens, Error>?

        func token(forceRefresh: Bool, canLogOut: Bool) async throws -> String {
            guard let current = SpotifyTokenStore.load() else { throw SpotifyAuthError.notLoggedIn }
            if !forceRefresh, current.expiresAt.timeIntervalSinceNow > 60 { return current.accessToken }
            if let inFlight { return try await inFlight.value.accessToken }

            let task = Task { try await Self.refresh(current) }
            inFlight = task
            defer { inFlight = nil }
            do {
                let fresh = try await task.value
                SpotifyTokenStore.save(fresh)
                return fresh.accessToken
            } catch SpotifyAuthError.tokenExchange(let msg) where msg.contains("invalid_grant") {
                // The app or the widget may have just swapped in a new refresh token.
                if let latest = SpotifyTokenStore.load(), latest.refreshToken != current.refreshToken {
                    if latest.expiresAt.timeIntervalSinceNow > 60 { return latest.accessToken }
                    let fresh = try await Self.refresh(latest)
                    SpotifyTokenStore.save(fresh)
                    return fresh.accessToken
                }
                if canLogOut { SpotifyTokenStore.save(nil) }
                throw SpotifyAuthError.notLoggedIn
            }
        }

        private static func refresh(_ tokens: SpotifyTokens) async throws -> SpotifyTokens {
            try await SpotifyTokenStore.requestTokens([
                "grant_type": "refresh_token",
                "refresh_token": tokens.refreshToken,
                "client_id": SpotifyTokenStore.clientID,
            ], previousRefresh: tokens.refreshToken)
        }
    }

    static func requestTokens(_ form: [String: String], previousRefresh: String?) async throws -> SpotifyTokens {
        var req = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = form.map { "\($0.key)=\(formEncode($0.value))" }.joined(separator: "&").data(using: .utf8)

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

    private static func formEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
