import ActivityKit
import SwiftUI
import WidgetKit

struct LyricsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LyricsActivityAttributes.self) { context in
            LyricsActivityView(state: context.state)
                .activityBackgroundTint(Color(hex: context.state.tintHex))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let s = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                    LyricsCard(state: s, style: .island)
                }
            } compactLeading: {
                Image(systemName: "quote.bubble.fill")
            } compactTrailing: {
                Text(s.currentLine).font(.caption2).lineLimit(1).frame(maxWidth: 64)
            } minimal: {
                Image(systemName: "quote.bubble.fill")
            }
        }
        // .small is the size CarPlay (and the Apple Watch Smart Stack) uses.
        .supplementalActivityFamilies([.small])
    }
}

struct LyricsActivityView: View {
    let state: LyricsActivityAttributes.ContentState
    @Environment(\.activityFamily) private var family

    var body: some View {
        LyricsCard(state: state, style: family == .small ? .carPlay : .lockScreen)
    }
}

/// The card's layout: the current line at the largest size that fits, never cut off, the
/// next line when there's room, and a progress bar. The Lock Screen adds a title row.
/// CarPlay's card is only 195×78 points, so there the lyric gets nearly all of it.
struct LyricsCard: View {
    enum Style { case lockScreen, carPlay, island }

    let state: LyricsActivityAttributes.ContentState
    let style: Style

    var body: some View {
        switch style {
        case .carPlay: carPlay
        case .lockScreen, .island: standard
        }
    }

    // MARK: CarPlay

    private var carPlay: some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                if !state.isPlaying { Image(systemName: "pause.fill") }
                Text(state.title).lineLimit(1)
            }
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.white.opacity(0.5))

            FittedLine(attributed: currentLine, sizes: [22, 19, 17, 15, 13, 12])
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentTransition(.opacity)

            // A preview of what's coming. Cutting it off is fine; it shows in full next.
            if !state.nextLine.isEmpty {
                Text(state.nextLine)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 5)
        .padding(.bottom, 9)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The progress bar hugs the bottom edge so it takes no room from the lyrics.
        .overlay(alignment: .bottom) {
            if state.isPlaying {
                LineProgress(state: state)
                    .scaleEffect(x: 1, y: 0.6)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 3)
            }
        }
    }

    // MARK: Lock Screen and Dynamic Island

    private var standard: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                if !state.isPlaying { Image(systemName: "pause.fill") }
                Text("\(state.title) · \(state.artist)").lineLimit(1)
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white.opacity(0.6))

            Group {
                if style == .lockScreen {
                    lyric(withNext: [26, 23, 20], alone: [26, 23, 20, 17, 15], nextSize: 13)
                        .frame(maxHeight: 110)
                } else {
                    lyric(withNext: [20, 17], alone: [20, 17, 15, 13], nextSize: 12)
                        .frame(maxHeight: 64)
                }
            }
            .frame(maxWidth: .infinity)

            LineProgress(state: state)
                .padding(.top, 2)
        }
        .padding(.horizontal, style == .lockScreen ? 20 : 8)
        .padding(.vertical, style == .lockScreen ? 14 : 6)
    }

    // MARK: Lyric

    /// Tries the current line with the next one under it, then the current line alone at
    /// shrinking sizes, and as a last resort scales the smallest size down to fit.
    private func lyric(withNext: [CGFloat], alone: [CGFloat], nextSize: CGFloat) -> some View {
        ViewThatFits(in: .vertical) {
            if !state.nextLine.isEmpty {
                ForEach(withNext, id: \.self) { size in
                    VStack(spacing: 3) {
                        current(size)
                        Text(state.nextLine)
                            .font(.system(size: nextSize, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.45))
                            .multilineTextAlignment(.center)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            FittedLine(attributed: currentLine, sizes: alone)
        }
        .contentTransition(.opacity)
    }

    private func current(_ size: CGFloat) -> some View {
        Text(currentLine)
            .font(.system(size: size, weight: .bold))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// In word-by-word mode the app sends how many words are lit.
    private var currentLine: AttributedString {
        if let lit = state.litWords {
            return WordTiming.highlighted(state.currentLine, dim: 0.4) { $0 < lit ? 1 : 0 }
        }
        var plain = AttributedString(state.currentLine)
        plain.foregroundColor = .white
        return plain
    }
}

/// A thin bar that fills across the current line on its own, without app updates.
struct LineProgress: View {
    let state: LyricsActivityAttributes.ContentState

    var body: some View {
        Group {
            if state.isPlaying, state.lineEnd > state.lineStart {
                ProgressView(timerInterval: state.lineStart...state.lineEnd, countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
            } else {
                ProgressView(value: 0)
            }
        }
        .progressViewStyle(.linear)
        .tint(.white.opacity(0.85))
        .labelsHidden()
    }
}
