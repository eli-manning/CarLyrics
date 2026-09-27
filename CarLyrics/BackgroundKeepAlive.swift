import AVFoundation
import UIKit

/// iOS suspends apps shortly after they leave the foreground, which would freeze
/// the lyrics Live Activity. Running a near-silent audio engine (mixed with Spotify,
/// never interrupting it) keeps the process alive so it can keep syncing lyrics.
///
/// If the engine ever stops (a phone call, Siri, a CarPlay route change) iOS suspends us
/// a few seconds later, so `check()` is called from the engine's loop to restart it
/// right away instead of waiting for a notification that may never arrive.
final class BackgroundKeepAlive {
    private let engine = AVAudioEngine()
    private var observers: [NSObjectProtocol] = []
    private(set) var isRunning = false
    private var interrupted = false
    private var nextRetry = Date.distantPast
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    init() {
        // Inaudible noise (about -100 dB) rather than exact zeros, so nothing along the way
        // can treat the stream as idle and stop pulling it.
        let silence = AVAudioSourceNode { _, _, frameCount, bufferList in
            for buffer in UnsafeMutableAudioBufferListPointer(bufferList) {
                guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
                for i in 0..<min(count, Int(frameCount) * Int(buffer.mNumberChannels)) {
                    data[i] = Float.random(in: -0.00001...0.00001)
                }
            }
            return noErr
        }
        engine.attach(silence)
        engine.connect(silence, to: engine.mainMixerNode, format: nil)

        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            // Phone calls / Siri interrupt us; resume afterwards.
            guard let self, self.isRunning,
                  let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            Diagnostics.log("audio interruption \(type == .began ? "began" : "ended")")
            if type == .began {
                self.interrupted = true
                // Keep running through the interruption so we're still here when it ends.
                self.holdBackgroundTime()
            } else {
                self.interrupted = false
                self.restart()
            }
        })
        observers.append(nc.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self, self.isRunning else { return }
            Diagnostics.log("audio media services reset")
            self.restart()
        })
        observers.append(nc.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            // Route changes (e.g. plugging into CarPlay) stop the engine.
            guard let self, self.isRunning else { return }
            Diagnostics.log("audio route/config changed, engine running: \(self.engine.isRunning)")
            self.restart()
        })
    }

    func start() {
        isRunning = true
        restart()
    }

    /// Restarts the engine if it stopped. Cheap; call it often.
    func check() {
        guard isRunning, !engine.isRunning, Date() >= nextRetry else { return }
        Diagnostics.log("keep-alive audio found stopped\(interrupted ? " (interrupted)" : ""), restarting")
        restart()
    }

    private func restart() {
        do {
            try startEngine()
            Diagnostics.log("keep-alive audio running")
            releaseBackgroundTime()
        } catch {
            // During a call the session can't be reactivated; keep trying, and ask for
            // background time so we aren't suspended in the meantime.
            Diagnostics.log("keep-alive audio failed: \(error.localizedDescription)")
            nextRetry = Date().addingTimeInterval(2)
            holdBackgroundTime()
        }
    }

    var engineRunning: Bool { engine.isRunning }

    func stop() {
        Diagnostics.log("keep-alive audio stopped")
        isRunning = false
        interrupted = false
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        releaseBackgroundTime()
    }

    private func startEngine() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try session.setActive(true)
        if !engine.isRunning {
            engine.prepare()
            try engine.start()
        }
    }

    private func holdBackgroundTime() {
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "keep-alive") { [weak self] in
            self?.releaseBackgroundTime()
        }
    }

    private func releaseBackgroundTime() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }
}
