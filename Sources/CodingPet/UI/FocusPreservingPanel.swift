import AppKit

/// A floating panel that can receive mouse clicks without taking keyboard
/// focus away from the user's terminal or editor.
final class FocusPreservingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
