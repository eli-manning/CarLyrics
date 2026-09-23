import SwiftUI
import WidgetKit

struct LyricsEntry: TimelineEntry {
    let date: Date
    let song: WidgetSong?
    let index: Int?
}

/// Builds one entry per upcoming lyric line from what the app last shared.
struct LyricsProvider: TimelineProvider {
    func placeholder(in context: Context) -> LyricsEntry {
        LyricsEntry(date: .now, song: .preview, index: 1)
    }

    func getSnapshot(in context: Context, completion: @escaping (LyricsEntry) -> Void) {
        let song = SharedStore.load() ?? (context.isPreview ? .preview : nil)
        completion(LyricsEntry(date: .now, song: song, index: song?.index(at: .now)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LyricsEntry>) -> Void) {
        Task {
            let now = Date()
            var song = SharedStore.load()
            var lookedUp = false
            // Use what the app shared while it still describes a song that's playing now.
            // Otherwise (the app isn't running, or the song ended) look it up ourselves.
            if song == nil || !song!.isPlaying || song!.songEnd <= now {
                if let fetched = await WidgetLookup.currentSong(previous: song) {
                    song = fetched.song
                    SharedStore.save(fetched.song)
                    lookedUp = true
                }
            }
            completion(Self.timeline(for: song, now: now, lookedUp: lookedUp))
        }
    }

    /// Widget refreshes are rationed (roughly 40 to 70 a day), so the widget only checks on
    /// its own when a song should be over, or every few minutes while nothing plays. While
    /// the app runs, it refreshes the widget right away on skips and pauses.
    private static func timeline(for song: WidgetSong?, now: Date, lookedUp: Bool) -> Timeline<LyricsEntry> {
        guard let song else {
            return Timeline(entries: [LyricsEntry(date: now, song: nil, index: nil)],
                            policy: .after(now.addingTimeInterval(lookedUp ? 300 : 120)))
        }
        var entries = [LyricsEntry(date: now, song: song, index: song.index(at: now))]
        guard song.isPlaying, song.songEnd > now else {
            return Timeline(entries: entries, policy: .after(now.addingTimeInterval(300)))
        }
        for (i, line) in song.lines.enumerated() {
            let date = song.songStart.addingTimeInterval(line.time)
            if date > now, date < song.songEnd { entries.append(LyricsEntry(date: date, song: song, index: i)) }
        }
        return Timeline(entries: entries, policy: .after(song.songEnd.addingTimeInterval(2)))
    }
}

/// Looks up what's playing and its lyrics directly, for when the app isn't running.
enum WidgetLookup {
    struct Result { let song: WidgetSong? }

    /// nil means the lookup failed (no login, no network); `Result(song: nil)` means
    /// nothing is playing.
    static func currentSong(previous: WidgetSong?) async -> Result? {
        guard let snap = try? await SpotifyAPI.currentlyPlaying(token: { force in
            try await SpotifyTokenStore.accessToken(forceRefresh: force, canLogOut: false)
        }) else { return nil }
        guard let track = snap.track else { return Result(song: nil) }

        let lyrics = await LyricsService.lyrics(for: track)
        var tint = Color.defaultTintHex
        if previous?.title == track.title, let old = previous?.tintHex {
            tint = old
        } else if let url = track.artworkURL, let art = await ArtworkPalette.load(url) {
            tint = art.hex
        }
        let offset = previous?.offsetMs ?? 0
        let position = Double(snap.progressMs) / 1000
            + (snap.isPlaying ? Date().timeIntervalSince(snap.capturedAt) : 0) + offset / 1000
        let message: String? = if lyrics == nil { "Couldn't find lyrics for this one" }
            else if lyrics!.isInstrumental { "Instrumental" } else { nil }

        return Result(song: WidgetSong(
            title: track.title, artist: track.artistLine, tintHex: tint,
            songStart: Date().addingTimeInterval(-position), duration: track.duration,
            isPlaying: snap.isPlaying,
            lines: (lyrics?.lines ?? []).map { .init(time: $0.time, text: $0.text) },
            message: message, offsetMs: offset
        ))
    }
}

struct LyricsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SharedStore.widgetKind, provider: LyricsProvider()) { entry in
            LyricsWidgetView(entry: entry)
        }
        .configurationDisplayName("Lyrics")
        .description("The line being sung in the song playing on Spotify. Works in CarPlay too.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct LyricsWidgetView: View {
    let entry: LyricsEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .containerBackground(for: .widget) {
                Color(hex: entry.song?.tintHex ?? Color.defaultTintHex)
            }
    }

    private var isSmall: Bool { family == .systemSmall }

    @ViewBuilder private var content: some View {
        if let song = entry.song {
            let line = current(in: song)
            VStack(spacing: 6) {
                HStack(spacing: 4) {
                    if !song.isPlaying { Image(systemName: "pause.fill") }
                    Text(song.title).lineLimit(1)
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.6))

                Spacer(minLength: 0)

                FittedLine(text: line, sizes: isSmall ? [24, 21, 18, 16, 14, 12] : [28, 24, 21, 18, 16, 14])
                    .layoutPriority(1)

                Spacer(minLength: 0)

                // Only show what's next when the current line leaves room for it.
                if let next = next(in: song), line.count <= (isSmall ? 48 : 90) {
                    Text(next)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.45))
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        } else {
            VStack(spacing: 6) {
                Text("CarLyrics").font(.caption2.weight(.semibold)).foregroundStyle(.white.opacity(0.6))
                Spacer(minLength: 0)
                Text("Play something on Spotify")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Spacer(minLength: 0)
            }
        }
    }

    private func current(in song: WidgetSong) -> String {
        if let message = song.message { return message }
        guard let i = entry.index else { return "♪" }
        return song.lines[i].text
    }

    private func next(in song: WidgetSong) -> String? {
        guard song.message == nil else { return nil }
        let i = (entry.index ?? -1) + 1
        return song.lines.indices.contains(i) ? song.lines[i].text : nil
    }
}

/// Shows the whole line at the largest size that fits, instead of cutting it off.
/// Used by the widget and the Live Activity.
struct FittedLine: View {
    let text: AttributedString
    let sizes: [CGFloat]

    init(text: String, sizes: [CGFloat]) {
        var plain = AttributedString(text)
        plain.foregroundColor = .white
        self.init(attributed: plain, sizes: sizes)
    }

    init(attributed: AttributedString, sizes: [CGFloat]) {
        self.text = attributed
        self.sizes = sizes
    }

    var body: some View {
        ViewThatFits(in: .vertical) {
            ForEach(sizes, id: \.self) { size in
                label(size).fixedSize(horizontal: false, vertical: true)
            }
            // Nothing fit completely: use the smallest size and let it trail off.
            label(sizes.last ?? 12)
        }
    }

    private func label(_ size: CGFloat) -> some View {
        Text(text)
            .font(.system(size: size, weight: .bold))
            .multilineTextAlignment(.center)
    }
}

extension WidgetSong {
    static let preview = WidgetSong(
        title: "Song title", artist: "Artist", tintHex: Color.defaultTintHex,
        songStart: .now.addingTimeInterval(-10), duration: 200, isPlaying: true,
        lines: [.init(time: 0, text: "Lyrics show up here"),
                .init(time: 5, text: "one line at a time"),
                .init(time: 10, text: "while the song plays")],
        message: nil
    )
}
