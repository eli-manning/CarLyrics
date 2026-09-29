import ActivityKit
import Foundation
import UIKit

/// Owns the single lyrics Live Activity (Lock Screen, Dynamic Island, CarPlay dashboard).
@MainActor
final class LiveActivityController {
    /// Picks up a card left over from a previous launch, so it can be updated or hidden.
    private var activity = Activity<LyricsActivityAttributes>.activities.first { $0.activityState == .active }
    private var lastState: LyricsActivityAttributes.ContentState?
    /// When the current card was started and how many updates it has had. iOS rations a
    /// card's updates, and once they run out it only redraws every ~10 seconds.
    private(set) var startedAt = Date()
    private var updateCount = 0

    var isActive: Bool { activity?.activityState == .active }
    var areActivitiesEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    /// Must be called while the app is in the foreground (ActivityKit rule).
    func start(with state: LyricsActivityAttributes.ContentState) throws {
        // Adopt an activity left over from a previous launch instead of stacking a new one.
        if activity == nil {
            activity = Activity<LyricsActivityAttributes>.activities.first { $0.activityState == .active }
        }
        if activity != nil { update(state); return }
        do {
            activity = try Activity.request(
                attributes: LyricsActivityAttributes(),
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil
            )
            startedAt = Date()
            updateCount = 0
            Diagnostics.log("card started (app state \(UIApplication.shared.applicationState.rawValue))")
        } catch {
            Diagnostics.log("card start failed (app state \(UIApplication.shared.applicationState.rawValue)): \(error.localizedDescription)")
            throw error
        }
        lastState = state
    }

    func update(_ state: LyricsActivityAttributes.ContentState) {
        guard let activity, state != lastState else { return }
        lastState = state
        updateCount += 1
        Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
    }

    /// Swaps in a fresh card so its updates aren't rationed. The old card is only ended
    /// once the new one is up, so if iOS refuses nothing changes. From the background this
    /// only works inside a LiveActivityIntent (tapping the card).
    @discardableResult
    func renew(with state: LyricsActivityAttributes.ContentState) -> Bool {
        guard let old = activity else { return false }
        let appState = UIApplication.shared.applicationState.rawValue
        let age = Int(Date().timeIntervalSince(startedAt) / 60)
        do {
            activity = try Activity.request(
                attributes: LyricsActivityAttributes(),
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil
            )
        } catch {
            Diagnostics.log("card renew failed after \(age) min, \(updateCount) updates (app state \(appState)): \(error.localizedDescription)")
            return false
        }
        Diagnostics.log("card renewed after \(age) min, \(updateCount) updates (app state \(appState))")
        lastState = state
        startedAt = Date()
        updateCount = 0
        Task { await old.end(nil, dismissalPolicy: .immediate) }
        return true
    }

    func end() {
        let all = Activity<LyricsActivityAttributes>.activities
        if !all.isEmpty { Diagnostics.log("card ended") }
        activity = nil
        lastState = nil
        Task { for a in all { await a.end(nil, dismissalPolicy: .immediate) } }
    }
}
