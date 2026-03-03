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
}
