import ActivityKit
import Foundation

/// Owns the single lyrics Live Activity (Lock Screen, Dynamic Island, CarPlay dashboard).
@MainActor
final class LiveActivityController {
    /// Picks up a card left over from a previous launch, so it can be updated or hidden.
    private var activity = Activity<LyricsActivityAttributes>.activities.first { $0.activityState == .active }
    private var lastState: LyricsActivityAttributes.ContentState?

    var isActive: Bool { activity?.activityState == .active }
    var areActivitiesEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    /// Must be called while the app is in the foreground (ActivityKit rule).
    func start(with state: LyricsActivityAttributes.ContentState) throws {
        // Adopt an activity left over from a previous launch instead of stacking a new one.
        if activity == nil {
            activity = Activity<LyricsActivityAttributes>.activities.first { $0.activityState == .active }
        }
        if activity != nil { update(state); return }
        activity = try Activity.request(
            attributes: LyricsActivityAttributes(),
            content: ActivityContent(state: state, staleDate: nil),
            pushType: nil
        )
        lastState = state
    }

    func update(_ state: LyricsActivityAttributes.ContentState) {
        guard let activity, state != lastState else { return }
        lastState = state
        Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
    }

    func end() {
        let all = Activity<LyricsActivityAttributes>.activities
        activity = nil
        lastState = nil
        Task { for a in all { await a.end(nil, dismissalPolicy: .immediate) } }
    }
}
