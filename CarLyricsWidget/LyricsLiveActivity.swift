import ActivityKit
import SwiftUI
import WidgetKit

private let accent = Color(red: 1.0, green: 0.82, blue: 0.25)

struct LyricsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LyricsActivityAttributes.self) { context in
            LyricsActivityView(state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.85))
                .activitySystemActionForegroundColor(accent)
        } dynamicIsland: { context in
            let s = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "music.mic").foregroundStyle(accent).padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(s.title).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(s.currentLine).font(.headline).foregroundStyle(accent).lineLimit(2)
                        Text(s.nextLine).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                        LineProgress(state: s)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Image(systemName: "music.mic").foregroundStyle(accent)
            } compactTrailing: {
                Text(s.currentLine).font(.caption2).lineLimit(1).frame(maxWidth: 64)
            } minimal: {
                Image(systemName: "music.mic").foregroundStyle(accent)
            }
        }
        // .small is the size CarPlay (and Apple Watch Smart Stack) renders.
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

    /// CarPlay dashboard / Watch: big current line + the next one.
    private var carPlay: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: state.isPlaying ? "music.mic" : "pause.fill")
                Text(state.title).lineLimit(1)
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)

            Text(state.currentLine)
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(accent)
                .lineLimit(3)
                .minimumScaleFactor(0.6)
                .contentTransition(.opacity)

            if !state.nextLine.isEmpty {
                Text(state.nextLine)
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            LineProgress(state: state)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Lock Screen / banner: previous, current, next lines karaoke-style.
    private var lockScreen: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "music.mic").foregroundStyle(accent)
                Text("\(state.title) · \(state.artist)").lineLimit(1)
                Spacer()
                if !state.isSynced { Image(systemName: "clock.badge.questionmark") }
                if !state.isPlaying { Image(systemName: "pause.fill") }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)

            if !state.previousLine.isEmpty {
                Text(state.previousLine).font(.subheadline).foregroundStyle(.white.opacity(0.35)).lineLimit(1)
            }
            Text(state.currentLine)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(accent)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .contentTransition(.opacity)
            if !state.nextLine.isEmpty {
                Text(state.nextLine).font(.subheadline.weight(.medium)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
            }
            LineProgress(state: state)
        }
        .padding(16)
    }
}

/// Animates on-device across the current line without needing updates.
struct LineProgress: View {
    let state: LyricsActivityAttributes.ContentState

    var body: some View {
        if state.isPlaying, state.lineEnd > state.lineStart {
            ProgressView(timerInterval: state.lineStart...state.lineEnd, countsDown: false) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .progressViewStyle(.linear)
            .tint(accent)
            .labelsHidden()
        } else {
            ProgressView(value: 0).progressViewStyle(.linear).tint(accent).opacity(0.3)
        }
    }
}
