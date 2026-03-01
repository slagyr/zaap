import XCTest
@testable import Zaap

@MainActor
final class TTSDiagnosticsViewModelTests: XCTestCase {

    var viewModel: TTSDiagnosticsViewModel!

    override func setUp() {
        super.setUp()
        viewModel = TTSDiagnosticsViewModel()
    }

    // MARK: - Initial State

    func testInitialStateIsInactive() {
        XCTAssertFalse(viewModel.isActive)
    }

    func testInitialStateIsNotPlaying() {
        XCTAssertFalse(viewModel.isPlaying)
    }

    func testInitialHighlightRangeIsNil() {
        XCTAssertNil(viewModel.highlightRange)
    }

    func testInitialAudioLevelIsZero() {
        XCTAssertEqual(viewModel.audioLevel, 0.0)
    }

    func testTextContainsTheRaven() {
        XCTAssertTrue(viewModel.text.contains("Once upon a midnight dreary"))
    }

    func testTextContainsThreeVerses() {
        // The Raven's first three stanzas each end with a distinct line
        XCTAssertTrue(viewModel.text.contains("nothing more"))
        XCTAssertTrue(viewModel.text.contains("Nameless here for evermore"))
    }

    // MARK: - Activation

    func testActivateSetsIsActiveTrue() {
        viewModel.activate()
        XCTAssertTrue(viewModel.isActive)
    }

    func testDeactivateSetsIsActiveFalse() {
        viewModel.activate()
        viewModel.deactivate()
        XCTAssertFalse(viewModel.isActive)
    }

    func testDeactivateClearsPlayingState() {
        viewModel.activate()
        viewModel.setPlaying(true)
        viewModel.deactivate()
        XCTAssertFalse(viewModel.isPlaying)
    }

    func testDeactivateClearsHighlightRange() {
        viewModel.activate()
        viewModel.updateHighlightRange(NSRange(location: 0, length: 4))
        viewModel.deactivate()
        XCTAssertNil(viewModel.highlightRange)
    }

    func testDeactivateResetsAudioLevel() {
        viewModel.activate()
        viewModel.updateAudioLevel(0.8)
        viewModel.deactivate()
        XCTAssertEqual(viewModel.audioLevel, 0.0)
    }

    // MARK: - Playing State

    func testSetPlayingTrue() {
        viewModel.setPlaying(true)
        XCTAssertTrue(viewModel.isPlaying)
    }

    func testSetPlayingFalse() {
        viewModel.setPlaying(true)
        viewModel.setPlaying(false)
        XCTAssertFalse(viewModel.isPlaying)
    }

    func testSetPlayingFalseClearsHighlightRange() {
        viewModel.setPlaying(true)
        viewModel.updateHighlightRange(NSRange(location: 0, length: 4))
        viewModel.setPlaying(false)
        XCTAssertNil(viewModel.highlightRange)
    }

    // MARK: - Highlight Range

    func testUpdateHighlightRange() {
        let range = NSRange(location: 5, length: 4)
        viewModel.updateHighlightRange(range)
        XCTAssertEqual(viewModel.highlightRange, range)
    }

    func testClearHighlightRange() {
        viewModel.updateHighlightRange(NSRange(location: 0, length: 3))
        viewModel.clearHighlightRange()
        XCTAssertNil(viewModel.highlightRange)
    }

    // MARK: - Audio Level

    func testUpdateAudioLevel() {
        viewModel.updateAudioLevel(0.75)
        XCTAssertEqual(viewModel.audioLevel, 0.75)
    }

    func testAudioLevelClampedToZero() {
        viewModel.updateAudioLevel(-0.5)
        XCTAssertEqual(viewModel.audioLevel, 0.0)
    }

    func testAudioLevelClampedToOne() {
        viewModel.updateAudioLevel(1.5)
        XCTAssertEqual(viewModel.audioLevel, 1.0)
    }
}
