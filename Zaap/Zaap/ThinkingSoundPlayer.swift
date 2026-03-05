import AVFoundation

/// Protocol for playing a thinking/processing sound while awaiting AI response.
protocol ThinkingSoundPlaying: AnyObject {
    var isPlaying: Bool { get }
    func startPlaying()
    func stopPlaying()
}

/// Plays a sonar-style ping using AVAudioEngine to indicate processing.
/// Generates a short sine burst at ~900 Hz with fast exponential decay,
/// repeating every 2 seconds — no bundled asset needed.
final class SystemThinkingSoundPlayer: ThinkingSoundPlaying {

    // MARK: - Sound characteristics (internal for testability)

    /// Sonar ping frequency in Hz
    let pingFrequency: Float = 900.0
    /// Duration of each ping burst in seconds
    let pingDuration: Float = 0.15
    /// Exponential decay rate — higher = faster fade
    let decayRate: Float = 20.0
    /// Time between pings in seconds (also the loop duration)
    let pingInterval: Double = 2.0
    /// Peak amplitude of the ping
    let amplitude: Float = 0.08

    private(set) var isPlaying = false
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var buffer: AVAudioPCMBuffer?

    func startPlaying() {
        guard !isPlaying else { return }
        isPlaying = true

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)

        let sampleRate: Double = 44100
        let frameCount = AVAudioFrameCount(sampleRate * pingInterval)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            isPlaying = false
            return
        }

        pcmBuffer.frameLength = frameCount
        guard let channelData = pcmBuffer.floatChannelData?[0] else {
            isPlaying = false
            return
        }

        // Generate sonar ping with exponential decay, then silence
        let pingSamples = Int(Float(sampleRate) * pingDuration)
        for i in 0..<Int(frameCount) {
            if i < pingSamples {
                let t = Float(i) / Float(sampleRate)
                let sine = sin(2.0 * .pi * pingFrequency * t)
                let envelope = exp(-decayRate * t)
                channelData[i] = amplitude * envelope * sine
            } else {
                channelData[i] = 0
            }
        }

        engine.connect(player, to: engine.mainMixerNode, format: format)

        do {
            try engine.start()
            player.scheduleBuffer(pcmBuffer, at: nil, options: .loops)
            player.play()
            self.audioEngine = engine
            self.playerNode = player
            self.buffer = pcmBuffer
        } catch {
            isPlaying = false
        }
    }

    func stopPlaying() {
        playerNode?.stop()
        audioEngine?.stop()
        audioEngine = nil
        playerNode = nil
        buffer = nil
        isPlaying = false
    }
}
