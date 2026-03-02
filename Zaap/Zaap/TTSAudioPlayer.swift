import AVFoundation

// MARK: - Protocols

protocol TTSBufferSynthesizing {
    func synthesize(utterance: AVSpeechUtterance,
                    bufferCallback: @escaping (AVAudioBuffer) -> Void,
                    markerCallback: @escaping (NSRange) -> Void,
                    finishCallback: @escaping () -> Void)
    func cancelSynthesis()
}

protocol AudioPlayerNodeProtocol {
    func play()
    func pause()
    func stop()
    func scheduleBuffer(_ buffer: AVAudioPCMBuffer)
    func scheduleBuffer(_ buffer: AVAudioPCMBuffer, completionHandler: @escaping () -> Void)
}

protocol PlaybackEngineProtocol {
    func start() throws
}

// MARK: - TTSAudioPlayer

class TTSAudioPlayer {

    private let synthesizer: TTSBufferSynthesizing
    private let playerNode: AudioPlayerNodeProtocol
    private let engine: PlaybackEngineProtocol

    private(set) var isPlaying = false
    private(set) var isPaused = false
    private var pendingBufferCount = 0
    private var synthesisComplete = false

    var onWordBoundary: ((NSRange) -> Void)?
    var onFinish: (() -> Void)?
    var onError: ((Error) -> Void)?

    init(synthesizer: TTSBufferSynthesizing,
         playerNode: AudioPlayerNodeProtocol,
         engine: PlaybackEngineProtocol) {
        self.synthesizer = synthesizer
        self.playerNode = playerNode
        self.engine = engine
    }

    func play(text: String) {
        let utterance = AVSpeechUtterance(string: text)

        do {
            try engine.start()
        } catch {
            onError?(error)
            return
        }

        playerNode.play()
        isPlaying = true
        isPaused = false
        pendingBufferCount = 0
        synthesisComplete = false

        synthesizer.synthesize(
            utterance: utterance,
            bufferCallback: { [weak self] buffer in
                guard let pcmBuffer = buffer as? AVAudioPCMBuffer else { return }
                self?.pendingBufferCount += 1
                self?.playerNode.scheduleBuffer(pcmBuffer) { [weak self] in
                    self?.bufferCompleted()
                }
            },
            markerCallback: { [weak self] range in
                self?.onWordBoundary?(range)
            },
            finishCallback: { [weak self] in
                self?.synthesisComplete = true
                self?.checkFinished()
            }
        )
    }

    func pause() {
        playerNode.pause()
        isPlaying = false
        isPaused = true
    }

    func resume() {
        playerNode.play()
        isPlaying = true
        isPaused = false
    }

    func stop() {
        playerNode.stop()
        synthesizer.cancelSynthesis()
        isPlaying = false
        isPaused = false
        pendingBufferCount = 0
        synthesisComplete = false
    }

    // MARK: - Buffer Completion Tracking

    private func bufferCompleted() {
        pendingBufferCount -= 1
        checkFinished()
    }

    private func checkFinished() {
        guard synthesisComplete, pendingBufferCount <= 0 else { return }
        isPlaying = false
        onFinish?()
    }
}
