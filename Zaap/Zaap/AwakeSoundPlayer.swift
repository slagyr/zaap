import AVFoundation

class AwakeSoundPlayer {

    private var engine: AVAudioEngine?

    private var sourceNode: AVAudioSourceNode?

    func play() {

        engine = AVAudioEngine()

        guard let engine = engine else { return }

        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!

        sourceNode = AVAudioSourceNode { _, _, frameCount, audioBufferList in

            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)

            let buffer = ablPointer[0]

            let ptr = buffer.mData!.assumingMemoryBound(to: Float.self)

            let sampleRate = 44100.0

            let frequency = 1200.0

            let amplitude: Float = 0.3

            for frame in 0..<Int(frameCount) {

                let time = Double(frame) / sampleRate

                ptr[frame] = amplitude * sin(2 * .pi * frequency * time)

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