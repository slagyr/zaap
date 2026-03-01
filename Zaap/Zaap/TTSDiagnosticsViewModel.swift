import Foundation

@MainActor
final class TTSDiagnosticsViewModel: ObservableObject {
    @Published private(set) var isActive = false
    @Published private(set) var isPlaying = false
    @Published private(set) var highlightRange: NSRange?
    @Published private(set) var audioLevel: Float = 0.0

    let text: String = """
        Once upon a midnight dreary, while I pondered, weak and weary,
        Over many a quaint and curious volume of forgotten lore—
        While I nodded, nearly napping, suddenly there came a tapping,
        As of some one gently rapping, rapping at my chamber door.
        "'Tis some visitor," I muttered, "tapping at my chamber door—
        Only this and nothing more."

        Ah, distinctly I remember it was in the bleak December;
        And each separate dying ember wrought its ghost upon the floor.
        Eagerly I wished the morrow;—vainly I had sought to borrow
        From my books surcease of sorrow—sorrow for the lost Lenore—
        For the rare and radiant maiden whom the angels name Lenore—
        Nameless here for evermore.

        And the silken, sad, uncertain rustling of each purple curtain
        Thrilled me—filled me with fantastic terrors never felt before;
        So that now, to still the beating of my heart, I stood repeating
        "'Tis some visitor entreating entrance at my chamber door—
        Some late visitor entreating entrance at my chamber door;—
        This it is and nothing more."
        """

    func activate() {
        isActive = true
    }

    func deactivate() {
        isActive = false
        isPlaying = false
        highlightRange = nil
        audioLevel = 0.0
    }

    func setPlaying(_ playing: Bool) {
        isPlaying = playing
        if !playing {
            highlightRange = nil
        }
    }

    func updateHighlightRange(_ range: NSRange) {
        highlightRange = range
    }

    func clearHighlightRange() {
        highlightRange = nil
    }

    func updateAudioLevel(_ level: Float) {
        audioLevel = min(max(level, 0.0), 1.0)
    }
}
