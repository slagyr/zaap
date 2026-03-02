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
}

protocol PlaybackEngineProtocol {
    func attachPlayerNode(_ node: AudioPlayerNodeProtocol)
    func connectPlayerNode(_ node: AudioPlayerNodeProtocol, format: AVAudioFormat?)
    func start() throws
    func detachPlayerNode(_ node: AudioPlayerNodeProtocol)
}

// MARK: - TTSAudioPlayer

class TTSAudioPlayer {

    private let synthesizer: TTSBufferSynthesizing
    private let playerNode: AudioPlayerNodeProtocol
    private let engine: PlaybackEngineProtocol

    private(set) var isPlaying = false
    private(set) var isPaused = false

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
        engine.attachPlayerNode(playerNode)
        engine.connectPlayerNode(playerNode, format: nil)

        do {
            try engine.start()
        } catch {
            engine.detachPlayerNode(playerNode)
            onError?(error)
            return
        }

        playerNode.play()
        isPlaying = true
        isPaused = false

        synthesizer.synthesize(
            utterance: utterance,
            bufferCallback: { [weak self] buffer in
                guard let pcmBuffer = buffer as? AVAudioPCMBuffer else { return }
                self?.playerNode.scheduleBuffer(pcmBuffer)
            },
            markerCallback: { [weak self] range in
                self?.onWordBoundary?(range)
            },
            finishCallback: { [weak self] in
                self?.isPlaying = false
                self?.onFinish?()
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
        engine.detachPlayerNode(playerNode)
        synthesizer.cancelSynthesis()
        isPlaying = false
        isPaused = false
    }
}
