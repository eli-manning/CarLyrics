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
        let now = Date()
        guard let song = SharedStore.load() else {
            return completion(Timeline(entries: [LyricsEntry(date: now, song: nil, index: nil)], policy: .never))
        }
        var entries = [LyricsEntry(date: now, song: song, index: song.index(at: now))]
        guard song.isPlaying, !song.lines.isEmpty, song.songEnd > now else {
            // If the app's next update gets dropped, check again on our own once this song
            // should be over (not sooner: widget refreshes are rationed).
            let policy: TimelineReloadPolicy = song.isPlaying
                ? .after(max(song.songEnd, now.addingTimeInterval(15))) : .never
            return completion(Timeline(entries: entries, policy: policy))
        }
        for (i, line) in song.lines.enumerated() {
            let date = song.songStart.addingTimeInterval(line.time)
            if date > now, date < song.songEnd { entries.append(LyricsEntry(date: date, song: song, index: i)) }
        }
        // The app reloads this when the next song starts; this is only a fallback.
        completion(Timeline(entries: entries, policy: .after(song.songEnd)))
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
struct FittedLine: View {
    let text: String
    let sizes: [CGFloat]

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
            .foregroundStyle(.white)
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
