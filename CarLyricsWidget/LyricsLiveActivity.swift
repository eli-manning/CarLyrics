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

/// The card's layout, matching the widget: title on top, the current line centered at the
/// largest size that fits, the next line when there's room, and a progress bar.
struct LyricsCard: View {
    enum Style { case lockScreen, carPlay, island }

    let state: LyricsActivityAttributes.ContentState
    let style: Style

    var body: some View {
        VStack(spacing: style == .carPlay ? 4 : 6) {
            header

            if style == .carPlay { Spacer(minLength: 0) }

            FittedLine(attributed: currentLine, sizes: sizes)
                .frame(maxWidth: .infinity)
                .frame(maxHeight: maxLineHeight)
                .contentTransition(.opacity)

            if style == .carPlay { Spacer(minLength: 0) }

            if !state.nextLine.isEmpty, state.currentLine.count <= nextLineCutoff {
                Text(state.nextLine)
                    .font(.system(size: style == .carPlay ? 11 : 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
            }

            LineProgress(state: state)
                .padding(.top, 2)
        }
        .padding(.horizontal, style == .lockScreen ? 20 : 8)
        .padding(.vertical, style == .lockScreen ? 14 : 6)
        .frame(maxWidth: .infinity, maxHeight: style == .carPlay ? .infinity : nil)
    }

    private var header: some View {
        HStack(spacing: 4) {
            if !state.isPlaying { Image(systemName: "pause.fill") }
            Text(style == .carPlay ? state.title : "\(state.title) · \(state.artist)")
                .lineLimit(1)
        }
        .font(.system(size: style == .carPlay ? 10 : 12, weight: .semibold))
        .foregroundStyle(.white.opacity(0.6))
    }

    private var sizes: [CGFloat] {
        switch style {
        case .lockScreen: [26, 23, 20, 17, 15]
        case .carPlay: [20, 17, 15, 13, 11]
        case .island: [20, 17, 15, 13]
        }
    }

    /// Caps the line's height so the fitting picks a size that keeps the card compact.
    private var maxLineHeight: CGFloat? {
        switch style {
        case .lockScreen: 78
        case .carPlay: nil
        case .island: 52
        }
    }

    private var nextLineCutoff: Int { style == .carPlay ? 40 : 60 }

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
