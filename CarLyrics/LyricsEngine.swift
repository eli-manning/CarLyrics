import Foundation
import SwiftUI

enum LyricsStatus: Equatable {
    case idle, loading, found, notFound, instrumental
}

/// Polls Spotify for playback position, loads lyrics, tracks the current line,
/// and mirrors it into the Live Activity.
@MainActor
final class LyricsEngine: ObservableObject {
    @Published private(set) var track: SpotifyTrack?
    @Published private(set) var isPlaying = false
    @Published private(set) var lyrics: Lyrics?
    @Published private(set) var status: LyricsStatus = .idle
    @Published private(set) var currentIndex: Int?
    @Published private(set) var liveActivityOn = false
    @Published var errorMessage: String?

    /// Positive = show lyrics earlier. Persisted.
    @Published var offsetMs: Double = UserDefaults.standard.double(forKey: "offsetMs") {
        didSet { UserDefaults.standard.set(offsetMs, forKey: "offsetMs"); tick(force: true) }
    }
    @AppStorage("autoStartLiveActivity") var autoStartLiveActivity = true

    let auth: SpotifyAuth
    private let activity = LiveActivityController()
    private let keepAlive = BackgroundKeepAlive()
    private var snapshot: PlaybackSnapshot?
    private var loop: Task<Void, Never>?
    private var nextPoll = Date.distantPast
    private var lyricsTask: Task<Void, Never>?

    init(auth: SpotifyAuth) { self.auth = auth }

    /// Current song position in seconds, interpolated between polls.
    var position: TimeInterval {
        guard let s = snapshot else { return 0 }
        var p = Double(s.progressMs) / 1000
        if s.isPlaying { p += Date().timeIntervalSince(s.capturedAt) }
        return p + offsetMs / 1000
    }

    // MARK: Lifecycle

    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if Date() >= self.nextPoll { await self.poll() }
                self.tick()
                try? await Task.sleep(for: .milliseconds(150))
            }
        }
    }

    func stop() {
        loop?.cancel(); loop = nil
    }

    func appBecameActive() {
        start()
        nextPoll = .distantPast
        if autoStartLiveActivity, auth.isLoggedIn, !liveActivityOn { startLiveActivity() }
    }

    func appEnteredBackground() {
        // Without a Live Activity there's nothing to keep up to date — let iOS suspend us.
        if !liveActivityOn { stop() }
    }

    // MARK: Live Activity

    func startLiveActivity() {
        guard activity.areActivitiesEnabled else {
            errorMessage = "Live Activities are turned off for CarLyrics. You can turn them on in Settings > CarLyrics."
            return
        }
        do {
            try activity.start(with: activityState())
            keepAlive.start()
            liveActivityOn = true
            start()
        } catch {
            errorMessage = "Couldn't start the lyrics card. \(error.localizedDescription)"
        }
    }

    func stopLiveActivity() {
        activity.end()
        keepAlive.stop()
        liveActivityOn = false
    }

    // MARK: Polling

    private func poll() async {
        guard auth.isLoggedIn else { nextPoll = Date().addingTimeInterval(2); return }
        do {
            let snap = try await SpotifyAPI.currentlyPlaying(auth: auth)
            errorMessage = nil
            snapshot = snap
            isPlaying = snap.isPlaying
            if snap.track != track { trackChanged(to: snap.track) }
            // Poll faster while playing so seeks/skips are picked up quickly.
            nextPoll = Date().addingTimeInterval(snap.isPlaying ? 2 : 5)
        } catch SpotifyAPIError.rateLimited(let wait) {
            nextPoll = Date().addingTimeInterval(wait)
        } catch SpotifyAuthError.notLoggedIn {
            stopLiveActivity()
        } catch {
            errorMessage = error.localizedDescription
            nextPoll = Date().addingTimeInterval(5)
        }
    }

    private func trackChanged(to newTrack: SpotifyTrack?) {
        track = newTrack
        lyrics = nil
        currentIndex = nil
        lyricsTask?.cancel()
        guard let newTrack else { status = .idle; tick(force: true); return }
        status = .loading
        tick(force: true)
        lyricsTask = Task {
            let found = await LyricsService.lyrics(for: newTrack)
            guard !Task.isCancelled, newTrack == self.track else { return }
            self.lyrics = found
            self.status = found == nil ? .notFound : (found!.isInstrumental ? .instrumental : .found)
            self.tick(force: true)
        }
    }

    // MARK: Line tracking

    private func tick(force: Bool = false) {
        let idx = lyrics?.index(at: position)
        if idx != currentIndex || force {
            currentIndex = idx
            if liveActivityOn { activity.update(activityState()) }
        }
    }

    private func activityState() -> LyricsActivityAttributes.ContentState {
        guard let track else { return .idle }
        let now = Date()
        let pos = position
        let songStart = now.addingTimeInterval(-pos)
        let songEnd = songStart.addingTimeInterval(track.duration)

        func text(_ i: Int) -> String {
            guard let lines = lyrics?.lines, lines.indices.contains(i) else { return "" }
            return lines[i].text
        }

        let lines = lyrics?.lines ?? []
        var current: String, previous = "", next = ""
        var lineStart = now, lineEnd = now.addingTimeInterval(1)

        switch status {
        case .loading: current = "Looking up lyrics…"
        case .notFound: current = "Couldn't find lyrics for this one"
        case .instrumental: current = "Instrumental"
        case .idle: current = "Waiting for a song"
        case .found:
            if let i = currentIndex {
                current = text(i); previous = text(i - 1); next = text(i + 1)
                lineStart = songStart.addingTimeInterval(lines[i].time)
                lineEnd = i + 1 < lines.count ? songStart.addingTimeInterval(lines[i + 1].time) : songEnd
            } else {
                current = "♪"; next = text(0)
                lineEnd = lines.first.map { songStart.addingTimeInterval($0.time) } ?? songEnd
            }
        }

        return .init(
            title: track.title, artist: track.artistLine,
            previousLine: previous, currentLine: current, nextLine: next,
            isPlaying: isPlaying, isSynced: lyrics?.isSynced ?? true,
            lineStart: lineStart, lineEnd: max(lineEnd, lineStart.addingTimeInterval(0.5)),
            songStart: songStart, songEnd: songEnd
        )
    }
}
