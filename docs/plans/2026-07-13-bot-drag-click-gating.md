# Bot drag/click gating

## Goal

Dragging the floating bot must only reposition its panel. Releasing the mouse
after a drag must not toggle the session panel, while an ordinary click and
minor pointer jitter must continue to work.

## Design

Keep AppKit's `isMovableByWindowBackground` behavior and observe local bot-panel
mouse events without consuming them. Record `NSEvent.mouseLocation` on mouse
down and compare subsequent drag/up positions in screen coordinates. Movement
of at least four points marks the interaction as a drag. The next SwiftUI
button activation is suppressed once, after which normal activation resumes.

Screen coordinates are intentional: moving the window can keep the pointer at
the same local coordinate, which makes a SwiftUI-only drag gesture unreliable
for distinguishing this interaction. The monitor is removed with the window
controller and never changes application activation or keyboard focus.

## Verification

Pure gate tests cover normal clicks, drag suppression, one-shot reset, and the
case where AppKit reports only down/up positions. Existing floating-window and
session-panel tests remain unchanged, followed by the full `swift test` suite.
