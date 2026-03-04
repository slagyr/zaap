import XCTest
@testable import Zaap

@MainActor
final class ThinkingSoundPlayerTests: XCTestCase {

    func testStartPlayingSetsIsPlayingTrue() {
        let player = MockThinkingSoundPlayer()
        XCTAssertFalse(player.isPlaying)
        player.startPlaying()
        XCTAssertTrue(player.isPlaying)
    }

    func testStopPlayingSetsIsPlayingFalse() {
        let player = MockThinkingSoundPlayer()
        player.startPlaying()
        player.stopPlaying()
        XCTAssertFalse(player.isPlaying)
    }

    func testStopWithoutStartIsNoOp() {
        let player = MockThinkingSoundPlayer()
        player.stopPlaying()
        XCTAssertFalse(player.isPlaying)
    }

    func testStartWhileAlreadyPlayingDoesNotRestart() {
        let player = MockThinkingSoundPlayer()
        player.startPlaying()
        player.startPlaying()
        XCTAssertEqual(player.startCount, 2)
        XCTAssertTrue(player.isPlaying)
    }

    func testSystemPlayerNotPlayingInitially() {
        let player = SystemThinkingSoundPlayer()
        XCTAssertFalse(player.isPlaying)
    }

    func testSystemPlayerStartStop() {
        let player = SystemThinkingSoundPlayer()
        player.startPlaying()
        XCTAssertTrue(player.isPlaying)
        player.stopPlaying()
        XCTAssertFalse(player.isPlaying)
    }

    // MARK: - Sound characteristics

    func testUsesWarmChordFrequenciesNotHarshSineWave() {
        // A warm major triad (C4, E4, G4) instead of a harsh 440 Hz pure sine
        let player = SystemThinkingSoundPlayer()
        XCTAssertEqual(player.frequencies, [261.63, 329.63, 392.00],
                       "Should use C major triad for warm timbre")
    }

    func testUsesSubtleAmplitude() {
        let player = SystemThinkingSoundPlayer()
        XCTAssertEqual(player.amplitude, 0.04, accuracy: 0.001,
                       "Should use subtle amplitude")
    }

    func testUsesSlowBreathingPulsation() {
        // 0.15 Hz = ~6.7 second breathing cycle, much gentler than 0.5 Hz
        let player = SystemThinkingSoundPlayer()
        XCTAssertEqual(player.pulseRate, 0.15, accuracy: 0.001,
                       "Should pulse slowly like breathing")
    }

    func testUsesLongerLoopDuration() {
        let player = SystemThinkingSoundPlayer()
        XCTAssertEqual(player.loopDuration, 4.0, accuracy: 0.001,
                       "Should use 4-second loop for smoother cycling")
    }
}
