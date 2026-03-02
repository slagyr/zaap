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

    func testPlayStartsEngine() {
        player.play(text: "Hello world")
        XCTAssertTrue(mockEngine.startCalled)
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

    // MARK: - Finish fires after playback, not synthesis

    func testOnFinishNotCalledWhenSynthesisCompletesButBuffersPending() {
        var finishCalled = false
        player.onFinish = { finishCalled = true }
        let format = AVAudioFormat(standardFormatWithSampleRate: 22050, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024)!
        buffer.frameLength = 512
        mockSynthesizer.buffersToDeliver = [buffer]
        player.play(text: "Hello")
        // Synthesis is done (finishCallback fired), but buffer hasn't played yet
        mockSynthesizer.simulateFinish()
        XCTAssertFalse(finishCalled, "onFinish should not fire until buffers finish playing")
        XCTAssertTrue(player.isPlaying, "Should still be playing while buffers are pending")
    }

    func testOnFinishCalledAfterAllBuffersPlayed() {
        var finishCalled = false
        player.onFinish = { finishCalled = true }
        let format = AVAudioFormat(standardFormatWithSampleRate: 22050, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024)!
        buffer.frameLength = 512
        mockSynthesizer.buffersToDeliver = [buffer]
        player.play(text: "Hello")
        mockSynthesizer.simulateFinish()
        mockPlayerNode.simulateAllBuffersPlayed()
        XCTAssertTrue(finishCalled, "onFinish should fire after all buffers finish playing")
        XCTAssertFalse(player.isPlaying)
    }

    func testIsPlayingTrueWhileBuffersStillPending() {
        let format = AVAudioFormat(standardFormatWithSampleRate: 22050, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024)!
        buffer.frameLength = 512
        mockSynthesizer.buffersToDeliver = [buffer]
        player.play(text: "Hello")
        mockSynthesizer.simulateFinish()
        XCTAssertTrue(player.isPlaying, "Should remain playing until buffers finish")
    }

    // MARK: - Engine Start Failure

    func testPlayDoesNotStartPlayerNodeWhenEngineStartFails() {
        mockEngine.startError = NSError(domain: "AVAudioEngine", code: -1, userInfo: nil)
        player.play(text: "Hello")
        XCTAssertFalse(mockPlayerNode.playCalled)
    }

    func testPlayDoesNotSynthesizeWhenEngineStartFails() {
        mockEngine.startError = NSError(domain: "AVAudioEngine", code: -1, userInfo: nil)
        player.play(text: "Hello")
        XCTAssertFalse(mockSynthesizer.writeCalled)
    }

    func testPlayIsNotPlayingWhenEngineStartFails() {
        mockEngine.startError = NSError(domain: "AVAudioEngine", code: -1, userInfo: nil)
        player.play(text: "Hello")
        XCTAssertFalse(player.isPlaying)
    }

    func testPlayCallsOnErrorWhenEngineStartFails() {
        var receivedError: Error?
        player.onError = { error in receivedError = error }
        mockEngine.startError = NSError(domain: "AVAudioEngine", code: -1, userInfo: nil)
        player.play(text: "Hello")
        XCTAssertNotNil(receivedError)
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
    private var completionHandlers: [() -> Void] = []

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

    func scheduleBuffer(_ buffer: AVAudioPCMBuffer, completionHandler: @escaping () -> Void) {
        scheduledBuffers.append(buffer)
        completionHandlers.append(completionHandler)
    }

    func simulateAllBuffersPlayed() {
        let handlers = completionHandlers
        completionHandlers.removeAll()
        handlers.forEach { $0() }
    }

    func simulateBufferPlayed(at index: Int) {
        guard index < completionHandlers.count else { return }
        completionHandlers[index]()
    }
}

final class MockPlaybackEngine: PlaybackEngineProtocol {
    var startCalled = false
    var startError: Error?

    func start() throws {
        startCalled = true
        if let error = startError {
            throw error
        }
    }
}
