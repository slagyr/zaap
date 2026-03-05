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

    // MARK: - Sonar ping characteristics

    func testUsesSonarPingFrequency() {
        let player = SystemThinkingSoundPlayer()
        XCTAssertEqual(player.pingFrequency, 900.0, accuracy: 0.01,
                       "Should use ~900 Hz sonar ping frequency")
    }

    func testUsesSonarPingDuration() {
        let player = SystemThinkingSoundPlayer()
        XCTAssertEqual(player.pingDuration, 0.15, accuracy: 0.001,
                       "Should use short 150ms ping burst")
    }

    func testUsesSonarDecayRate() {
        let player = SystemThinkingSoundPlayer()
        XCTAssertEqual(player.decayRate, 20.0, accuracy: 0.1,
                       "Should use fast exponential decay for sonar fade")
    }

    func testUsesSonarPingInterval() {
        // Ping repeats every ~2 seconds
        let player = SystemThinkingSoundPlayer()
        XCTAssertEqual(player.pingInterval, 2.0, accuracy: 0.001,
                       "Should repeat ping every 2 seconds")
    }

    func testUsesSubtleAmplitude() {
        let player = SystemThinkingSoundPlayer()
        XCTAssertEqual(player.amplitude, 0.08, accuracy: 0.001,
                       "Should use subtle amplitude for brief ping")
    }
}
