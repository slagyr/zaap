import XCTest
import AVFoundation
@testable import Zaap

@MainActor
final class TTSAudioPlayerTests: XCTestCase {

    var player: TTSAudioPlayer!
    var mockSynthesizer: MockBufferSynthesizer!
    var mockPlayerNode: MockAudioPlayerNode!
    var mockEngine: MockPlaybackEngine!

    override func setUp() {
        super.setUp()
        mockSynthesizer = MockBufferSynthesizer()
        mockPlayerNode = MockAudioPlayerNode()
        mockEngine = MockPlaybackEngine()
        player = TTSAudioPlayer(
            synthesizer: mockSynthesizer,
            playerNode: mockPlayerNode,
            engine: mockEngine
        )
    }

    // MARK: - Play

    func testPlayCallsWriteOnSynthesizer() {
        player.play(text: "Hello world")
        XCTAssertTrue(mockSynthesizer.writeCalled)
    }

    func testPlaySetsUtteranceText() {
        player.play(text: "Hello world")
        XCTAssertEqual(mockSynthesizer.lastUtteranceText, "Hello world")
    }

    func testPlayAttachesPlayerNodeToEngine() {
        player.play(text: "Hello world")
        XCTAssertTrue(mockEngine.attachCalled)
    }

    func testPlayConnectsPlayerNodeToMixer() {
        player.play(text: "Hello world")
        XCTAssertTrue(mockEngine.connectCalled)
    }

    func testPlayStartsPlayerNode() {
        player.play(text: "Hello world")
        XCTAssertTrue(mockPlayerNode.playCalled)
    }

    func testPlaySchedulesBuffersFromSynthesizer() {
        let format = AVAudioFormat(standardFormatWithSampleRate: 22050, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024)!
        buffer.frameLength = 512
        mockSynthesizer.buffersToDeliver = [buffer]
        player.play(text: "Test")
        XCTAssertEqual(mockPlayerNode.scheduledBuffers.count, 1)
    }

    // MARK: - Pause

    func testPausePausesPlayerNode() {
        player.play(text: "Hello")
        player.pause()
        XCTAssertTrue(mockPlayerNode.pauseCalled)
    }

    // MARK: - Resume

    func testResumeAfterPausePlaysPlayerNode() {
        player.play(text: "Hello")
        player.pause()
        mockPlayerNode.playCalled = false
        player.resume()
        XCTAssertTrue(mockPlayerNode.playCalled)
    }

    // MARK: - Stop

    func testStopStopsPlayerNode() {
        player.play(text: "Hello")
        player.stop()
        XCTAssertTrue(mockPlayerNode.stopCalled)
    }

    func testStopDetachesPlayerNode() {
        player.play(text: "Hello")
        player.stop()
        XCTAssertTrue(mockEngine.detachCalled)
    }

    // MARK: - State

    func testIsPlayingAfterPlay() {
        player.play(text: "Hello")
        XCTAssertTrue(player.isPlaying)
    }

    func testIsNotPlayingAfterPause() {
        player.play(text: "Hello")
        player.pause()
        XCTAssertFalse(player.isPlaying)
    }

    func testIsPausedAfterPause() {
        player.play(text: "Hello")
        player.pause()
        XCTAssertTrue(player.isPaused)
    }

    func testIsNotPlayingAfterStop() {
        player.play(text: "Hello")
        player.stop()
        XCTAssertFalse(player.isPlaying)
    }

    // MARK: - Callbacks

    func testOnWordBoundaryCalledWithRange() {
        var receivedRange: NSRange?
        player.onWordBoundary = { range in receivedRange = range }
        player.play(text: "Hello world")
        mockSynthesizer.simulateMarker(at: NSRange(location: 0, length: 5))
        XCTAssertEqual(receivedRange, NSRange(location: 0, length: 5))
    }

    func testOnFinishCalledWhenComplete() {
        var finishCalled = false
        player.onFinish = { finishCalled = true }
        player.play(text: "Hello")
        mockSynthesizer.simulateFinish()
        XCTAssertTrue(finishCalled)
    }
}

// MARK: - Test Doubles

final class MockBufferSynthesizer: TTSBufferSynthesizing {
    var writeCalled = false
    var lastUtteranceText: String?
    var buffersToDeliver: [AVAudioPCMBuffer] = []
    private var bufferCallback: ((AVAudioBuffer) -> Void)?
    private var markerCallback: ((NSRange) -> Void)?
    private var finishCallback: (() -> Void)?

    func synthesize(utterance: AVSpeechUtterance,
                    bufferCallback: @escaping (AVAudioBuffer) -> Void,
                    markerCallback: @escaping (NSRange) -> Void,
                    finishCallback: @escaping () -> Void) {
        writeCalled = true
        lastUtteranceText = utterance.speechString
        self.bufferCallback = bufferCallback
        self.markerCallback = markerCallback
        self.finishCallback = finishCallback
        for buffer in buffersToDeliver {
            bufferCallback(buffer)
        }
    }

    func cancelSynthesis() {}

    func simulateMarker(at range: NSRange) {
        markerCallback?(range)
    }

    func simulateFinish() {
        finishCallback?()
    }
}

final class MockAudioPlayerNode: AudioPlayerNodeProtocol {
    var playCalled = false
    var pauseCalled = false
    var stopCalled = false
    var scheduledBuffers: [AVAudioPCMBuffer] = []

    func play() {
        playCalled = true
    }

    func pause() {
        pauseCalled = true
    }

    func stop() {
        stopCalled = true
    }

    func scheduleBuffer(_ buffer: AVAudioPCMBuffer) {
        scheduledBuffers.append(buffer)
    }
}

final class MockPlaybackEngine: PlaybackEngineProtocol {
    var attachCalled = false
    var connectCalled = false
    var detachCalled = false

    func attachPlayerNode(_ node: AudioPlayerNodeProtocol) {
        attachCalled = true
    }

    func connectPlayerNode(_ node: AudioPlayerNodeProtocol, format: AVAudioFormat?) {
        connectCalled = true
    }

    func detachPlayerNode(_ node: AudioPlayerNodeProtocol) {
        detachCalled = true
    }
}
