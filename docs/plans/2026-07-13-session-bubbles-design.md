# Session bubble design

## Goal

Replace the oversized attention badge with a compact speech bubble and let the
user independently choose whether Running, Pending input, and Ready sessions
appear as conversation-style bubbles beside the floating pet.

## Presentation rules

`needsInput` is the pending state. When pending bubbles are enabled, pending
sessions appear as full bubbles. When disabled, their full bubbles disappear
and one compact bubble includes their count. Ready sessions have an independent
preference: enabled Ready sessions appear as full unread-completion bubbles;
disabled Ready sessions join the same compact attention count. Running sessions
appear only when running bubbles are enabled and disappear completely when it
is disabled. Blocked and idle sessions do not produce a session bubble.

The full presentation shows two sessions at a time, with Pending before Ready
before Running and the most recently updated session first within each state.
Each bubble contains the resolved session name and the metadata-only
status summary already held by `AgentSession`; CodingPet does not read provider
transcripts to fill the bubble.

Closing a Running bubble silences later Running updates for that session ID,
including message and tool activity. The bubble becomes eligible again when
the session escalates to `needsInput` or unread `ready`. Removing the session at
an inactive lifecycle boundary also clears the dismissal for its next run.

## Window behavior

The pet keeps its small interactive window. A second transparent,
non-activating panel renders the bubbles immediately above it and follows the
pet whenever it moves. While visible, the bubble panel is attached as a native
AppKit child window, so WindowServer moves it atomically with the pet rather
than Swift repositioning it after every move notification. The panel remains
non-activating, and its frame is tightly fitted to visible interactive content
so it does not steal keyboard focus or cover unrelated editor space.

AppKit exclusively owns the floating panel frame. The embedded `NSHostingView`
has automatic min/intrinsic/max window sizing disabled, so removing a bubble
cannot make SwiftUI restore a stale taller height and expand the panel down
over the pet.

## Settings and persistence

A dedicated Session Bubbles destination contains separate toggles for Running,
Pending input, and Ready sessions. All three preferences are stored locally in
`UserDefaults` and apply immediately to the shared overlay.

## Verification

Unit tests cover default values, persistence, independent status filtering,
ordering, the two-session viewport, and compact attention counts. Visual tests render full and
compact presentations. AppKit tests verify that both floating windows preserve
keyboard focus and that the overlay follows the pet.
