import Foundation

struct LyricLine: Identifiable, Hashable {
    let id: Int
    let time: TimeInterval
    let text: String
}

struct Lyrics {
    let lines: [LyricLine]
    /// false = plain lyrics with evenly estimated timings.
    let isSynced: Bool
    let isInstrumental: Bool

    /// Index of the line being sung at `position`, or nil before the first line.
    func index(at position: TimeInterval) -> Int? {
        guard let first = lines.first, position >= first.time else { return nil }
        var lo = 0, hi = lines.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if lines[mid].time <= position { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }
}

/// Lyrics from LRCLIB (https://lrclib.net) — free, open, no API key.
enum LyricsService {
    private struct Record: Decodable {
        let duration: Double?
        let instrumental: Bool?
        let plainLyrics: String?
        let syncedLyrics: String?
    }

    private static var cache: [String: Lyrics] = [:]

    static func lyrics(for track: SpotifyTrack) async -> Lyrics? {
        if let hit = cache[track.id] { return hit }
        let result = await lookup(track)
        if let result { cache[track.id] = result }
        return result
    }

    private static func lookup(_ track: SpotifyTrack) async -> Lyrics? {
        let artist = track.artists.first ?? ""
        let seconds = Int(track.duration.rounded())

        // 1. Exact signature match.
        if let rec: Record = await get("get", [
            "track_name": track.title, "artist_name": artist,
            "album_name": track.album, "duration": "\(seconds)",
        ]), let lyrics = build(rec, duration: track.duration) {
            return lyrics
        }

        // 2. Search with a cleaned-up title, prefer synced + closest duration.
        let cleaned = cleanTitle(track.title)
        for query in [["track_name": cleaned, "artist_name": artist], ["q": "\(cleaned) \(artist)"]] {
            guard let results: [Record] = await get("search", query), !results.isEmpty else { continue }
            let ranked = results
                .filter { abs(($0.duration ?? track.duration) - track.duration) < 8 }
                .sorted { a, b in
                    let aSynced = a.syncedLyrics?.isEmpty == false, bSynced = b.syncedLyrics?.isEmpty == false
                    if aSynced != bSynced { return aSynced }
                    return abs((a.duration ?? 0) - track.duration) < abs((b.duration ?? 0) - track.duration)
                }
            for rec in ranked { if let lyrics = build(rec, duration: track.duration) { return lyrics } }
        }
        return nil
    }

    private static func build(_ rec: Record, duration: TimeInterval) -> Lyrics? {
        if rec.instrumental == true { return Lyrics(lines: [], isSynced: true, isInstrumental: true) }
        if let synced = rec.syncedLyrics, !synced.isEmpty {
            let lines = parseLRC(synced)
            if !lines.isEmpty { return Lyrics(lines: lines, isSynced: true, isInstrumental: false) }
        }
        if let plain = rec.plainLyrics, !plain.isEmpty {
            return Lyrics(lines: estimate(plain, duration: duration), isSynced: false, isInstrumental: false)
        }
        return nil
    }

    /// Parses "[mm:ss.xx] text" lines; supports multiple timestamps per line.
    static func parseLRC(_ lrc: String) -> [LyricLine] {
        let stamp = /\[(\d+):(\d+(?:\.\d+)?)\]/
        var entries: [(TimeInterval, String)] = []
        for raw in lrc.split(whereSeparator: \.isNewline) {
            let line = String(raw)
            let stamps = line.matches(of: stamp)
            guard !stamps.isEmpty else { continue }
            let text = line.replacing(stamp, with: "").trimmingCharacters(in: .whitespaces)
            for m in stamps {
                let t = (Double(m.output.1) ?? 0) * 60 + (Double(m.output.2) ?? 0)
                entries.append((t, text.isEmpty ? "♪" : text))
            }
        }
        return entries.sorted { $0.0 < $1.0 }.enumerated().map { LyricLine(id: $0, time: $1.0, text: $1.1) }
    }

    /// No timestamps available: spread lines across the song so the display still moves.
    private static func estimate(_ plain: String, duration: TimeInterval) -> [LyricLine] {
        let texts = plain.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !texts.isEmpty else { return [] }
        let start = duration * 0.06, span = duration * 0.88
        return texts.enumerated().map { i, text in
            LyricLine(id: i, time: start + span * Double(i) / Double(texts.count), text: text)
        }
    }

    private static func cleanTitle(_ title: String) -> String {
        var t = title
        // "Song - Remastered 2011", "Song - Live", "Song (feat. X)", "Song [Deluxe]"
        if let dash = t.range(of: " - ") { t = String(t[..<dash.lowerBound]) }
        t = t.replacing(/\s*[\(\[][^\)\]]*(feat|with|remaster|version|edit|live|mono|stereo)[^\)\]]*[\)\]]/.ignoresCase(), with: "")
        return t.trimmingCharacters(in: .whitespaces)
    }

    private static func get<T: Decodable>(_ path: String, _ params: [String: String]) async -> T? {
        var comps = URLComponents(string: "https://lrclib.net/api/\(path)")!
        comps.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        var req = URLRequest(url: comps.url!)
        req.setValue("CarLyrics/1.0 (personal iOS app)", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 10
        guard let (data, response) = try? await URLSession.shared.data(for: req),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
