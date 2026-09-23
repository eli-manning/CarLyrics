import Foundation

struct SpotifyTrack: Equatable {
    let id: String
    let title: String
    let artists: [String]
    let album: String
    let durationMs: Int
    let artworkURL: URL?

    var artistLine: String { artists.joined(separator: ", ") }
    var duration: TimeInterval { Double(durationMs) / 1000 }
}

struct PlaybackSnapshot {
    let track: SpotifyTrack?
    let isPlaying: Bool
    let progressMs: Int
    /// Local time the progress value corresponds to (request midpoint).
    let capturedAt: Date
}

enum SpotifyAPIError: LocalizedError {
    case rateLimited(retryAfter: TimeInterval), http(Int)
    var errorDescription: String? {
        switch self {
        case .rateLimited(let s): "Spotify is limiting requests. Trying again in \(Int(s)) seconds."
        case .http(let code): "Spotify returned an error (HTTP \(code))."
        }
    }
}

enum SpotifyAPI {
    static func currentlyPlaying(auth: SpotifyAuth) async throws -> PlaybackSnapshot {
        do {
            return try await fetch(token: try await auth.accessToken())
        } catch SpotifyAPIError.http(401) {
            return try await fetch(token: try await auth.accessToken(forceRefresh: true))
        }
    }

    private static func fetch(token: String) async throws -> PlaybackSnapshot {
        var req = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/player/currently-playing?additional_types=track")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.timeoutInterval = 8

        let sent = Date()
        let (data, response) = try await URLSession.shared.data(for: req)
        let received = Date()
        let capturedAt = sent.addingTimeInterval(received.timeIntervalSince(sent) / 2)

        let http = response as! HTTPURLResponse
        switch http.statusCode {
        case 200: break
        case 204: return PlaybackSnapshot(track: nil, isPlaying: false, progressMs: 0, capturedAt: capturedAt)
        case 429:
            let wait = Double(http.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 10
            throw SpotifyAPIError.rateLimited(retryAfter: wait)
        default: throw SpotifyAPIError.http(http.statusCode)
        }

        struct Resp: Decodable {
            struct Item: Decodable {
                struct Artist: Decodable { let name: String }
                struct Album: Decodable {
                    struct Image: Decodable { let url: String; let width: Int? }
                    let name: String; let images: [Image]
                }
                let id: String?; let name: String; let duration_ms: Int
                let artists: [Artist]; let album: Album
            }
            let is_playing: Bool; let progress_ms: Int?; let item: Item?
        }
        let r = try JSONDecoder().decode(Resp.self, from: data)
        let track = r.item.map { item in
            SpotifyTrack(
                id: item.id ?? "\(item.name)-\(item.duration_ms)",
                title: item.name,
                artists: item.artists.map(\.name),
                album: item.album.name,
                durationMs: item.duration_ms,
                artworkURL: item.album.images.first.flatMap { URL(string: $0.url) }
            )
        }
        return PlaybackSnapshot(track: track, isPlaying: r.is_playing,
                                progressMs: r.progress_ms ?? 0, capturedAt: capturedAt)
    }
}
