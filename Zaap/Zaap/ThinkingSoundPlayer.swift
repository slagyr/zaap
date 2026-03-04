import AVFoundation

/// Protocol for playing a thinking/processing sound while awaiting AI response.
protocol ThinkingSoundPlaying: AnyObject {
    var isPlaying: Bool { get }
    func startPlaying()
    func stopPlaying()
}

/// Plays a subtle looping tone using AVAudioEngine to indicate processing.
/// Generates a warm chord with gentle breathing pulsation — no bundled asset needed.
final class SystemThinkingSoundPlayer: ThinkingSoundPlaying {

    // MARK: - Sound characteristics (internal for testability)

    /// C major triad frequencies for warm, consonant timbre
    let frequencies: [Float] = [261.63, 329.63, 392.00]  // C4, E4, G4
    /// Overall amplitude — subtle background presence
    let amplitude: Float = 0.04
    /// Slow breathing-like pulsation rate in Hz (~6.7 second cycle)
    let pulseRate: Float = 0.15
    /// Loop duration in seconds
    let loopDuration: Double = 4.0

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
        let frameCount = AVAudioFrameCount(sampleRate * loopDuration)
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

        // Generate warm chord with breathing envelope
        let perToneAmp = amplitude / Float(frequencies.count)
        for i in 0..<Int(frameCount) {
            let t = Float(i) / Float(sampleRate)
            // Smooth breathing envelope: sine-based, never fully silent
            let envelope = 0.4 + 0.6 * (1.0 + sin(2.0 * .pi * pulseRate * t)) / 2.0
            // Sum chord tones with decreasing amplitude for higher partials
            var sample: Float = 0
            for (index, freq) in frequencies.enumerated() {
                let weight: Float = 1.0 - Float(index) * 0.15  // root loudest
                sample += weight * sin(2.0 * .pi * freq * t)
            }
            channelData[i] = perToneAmp * envelope * sample
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
