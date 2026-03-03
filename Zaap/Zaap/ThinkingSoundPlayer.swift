import AVFoundation

/// Protocol for playing a thinking/processing sound while awaiting AI response.
protocol ThinkingSoundPlaying: AnyObject {
    var isPlaying: Bool { get }
    func startPlaying()
    func stopPlaying()
}

/// Plays a subtle looping tone using AVAudioEngine to indicate processing.
/// Generates a soft sine-wave chime programmatically — no bundled asset needed.
final class SystemThinkingSoundPlayer: ThinkingSoundPlaying {

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
        let duration: Double = 2.0
        let frameCount = AVAudioFrameCount(sampleRate * duration)
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

        // Generate a soft pulsing tone (gentle sine wave with amplitude envelope)
        let baseFreq: Float = 440.0  // A4
        let amplitude: Float = 0.08  // Very subtle
        for i in 0..<Int(frameCount) {
            let t = Float(i) / Float(sampleRate)
            // Gentle sine with slow amplitude modulation
            let envelope = (1.0 + sin(2.0 * .pi * 0.5 * t)) / 2.0 // Pulse at 0.5 Hz
            let sample = amplitude * envelope * sin(2.0 * .pi * baseFreq * t)
            channelData[i] = sample
        }

        engine.connect(player, to: engine.mainMixerNode, format: format)

        do {
            try engine.start()
            // Loop the buffer
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
