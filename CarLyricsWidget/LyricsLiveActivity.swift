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
                    VStack(alignment: .leading, spacing: 4) {
                        Text(s.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        Text(s.currentLine).font(.headline).lineLimit(2)
                        if !s.nextLine.isEmpty {
                            Text(s.nextLine).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                        }
                        LineProgress(state: s).padding(.top, 2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
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
        switch family {
        case .small: carPlay
        default: lockScreen
        }
    }

    /// CarPlay dashboard: the line being sung, big, with the next one under it.
    private var carPlay: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(state.title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)

            CurrentLine(state: state)
                .font(.system(.title3, weight: .bold))
                .lineLimit(3)
                .minimumScaleFactor(0.6)
                .contentTransition(.opacity)

            if !state.nextLine.isEmpty {
                Text(state.nextLine)
                    .font(.system(.footnote, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            LineProgress(state: state)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Lock Screen: previous, current and next lines.
    private var lockScreen: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("\(state.title) · \(state.artist)").lineLimit(1)
                Spacer()
                if !state.isPlaying { Image(systemName: "pause.fill") }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.6))

            if !state.previousLine.isEmpty {
                Text(state.previousLine)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.3))
                    .lineLimit(1)
            }
            CurrentLine(state: state)
                .font(.system(.title2, weight: .bold))
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .contentTransition(.opacity)
            if !state.nextLine.isEmpty {
                Text(state.nextLine)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
            }
            LineProgress(state: state).padding(.top, 2)
        }
        .padding(16)
    }
}

/// The line being sung. In word-by-word mode the app sends how many words are lit.
struct CurrentLine: View {
    let state: LyricsActivityAttributes.ContentState

    var body: some View {
        if let lit = state.litWords {
            Text(WordTiming.highlighted(state.currentLine, dim: 0.4) { $0 < lit ? 1 : 0 })
        } else {
            Text(state.currentLine).foregroundStyle(.white)
        }
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
