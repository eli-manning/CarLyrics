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
                  AVAudioSession.InterruptionType(rawValue: raw) == .ended else { return }
            try? self.startEngine()
        })
        observers.append(nc.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self, self.isRunning else { return }
            try? self.startEngine()
        })
        observers.append(nc.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            // Route changes (e.g. plugging into CarPlay) stop the engine.
            guard let self, self.isRunning else { return }
            try? self.startEngine()
        })
    }

    func start() {
        isRunning = true
        do { try startEngine() } catch { print("KeepAlive failed: \(error)") }
    }

    func stop() {
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
