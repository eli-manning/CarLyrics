import AVFoundation

/// iOS suspends apps shortly after they leave the foreground, which would freeze
/// the lyrics Live Activity. Running a silent audio engine (mixed with Spotify,
/// never interrupting it) keeps the process alive so it can keep syncing lyrics.
final class BackgroundKeepAlive {
    private let engine = AVAudioEngine()
    private var observers: [NSObjectProtocol] = []
    private(set) var isRunning = false

    init() {
        let silence = AVAudioSourceNode { _, _, _, bufferList in
            for buffer in UnsafeMutableAudioBufferListPointer(bufferList) {
                if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) }
            }
            return noErr
        }
        engine.attach(silence)
        engine.connect(silence, to: engine.mainMixerNode, format: nil)
        engine.mainMixerNode.outputVolume = 0

        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            // Phone calls / Siri interrupt us; resume afterwards.
            guard let self, self.isRunning,
                  let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            Diagnostics.log("audio interruption \(type == .began ? "began" : "ended")")
            if type == .ended { self.restart() }
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

    private func restart() {
        do {
            try startEngine()
            Diagnostics.log("keep-alive audio running")
        } catch {
            Diagnostics.log("keep-alive audio failed: \(error.localizedDescription)")
        }
    }

    var engineRunning: Bool { engine.isRunning }

    func stop() {
        Diagnostics.log("keep-alive audio stopped")
        isRunning = false
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func startEngine() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try session.setActive(true)
        if !engine.isRunning { try engine.start() }
    }
}
