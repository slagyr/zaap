import AVFoundation

class AwakeSoundPlayer {

    private var engine: AVAudioEngine?

    private var sourceNode: AVAudioSourceNode?

    func play() {

        engine = AVAudioEngine()

        guard let engine = engine else { return }

        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!

        sourceNode = AVAudioSourceNode { _, _, frameCount, audioBufferList -> OSStatus in

            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let ptr = ablPointer[0].mData!.assumingMemoryBound(to: Float.self)
            let sampleRate: Double = 44100.0
            let frequency: Double = 1200.0
            let amplitude: Float = 0.3
            let twoPiF: Double = 2.0 * Double.pi * frequency

            for frame in 0..<Int(frameCount) {
                let phase: Double = twoPiF * Double(frame) / sampleRate
                ptr[frame] = amplitude * Float(sin(phase))
            }

            return noErr
        }

        engine.attach(sourceNode!)

        engine.connect(sourceNode!, to: engine.mainMixerNode, format: format)

        do {

            try engine.start()

            // Play for 0.2 seconds

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {

                engine.stop()

                self.engine = nil

                self.sourceNode = nil

            }

        } catch {

            print("Awake sound error: \(error)")

        }

    }

}