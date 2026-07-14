# Clickable and dismissible session bubbles

## Goal

Let a user select a floating session bubble to return directly to that
session, without making CodingPet steal keyboard focus or placing a large
invisible click-blocking region over the originating app.

## Interaction

- A full conversation bubble selects its represented `AgentSession`.
- Codex uses the existing exact `codex://threads/<thread-id>` navigation path;
  Claude Code keeps the existing terminal/app/folder fallbacks.
- Selecting an unread Ready bubble acknowledges that exact version after the
  navigation request, matching selection from the session panel.
- A compact numeric bubble represents multiple possible sessions, so selecting
  it opens the session panel instead of guessing a destination.
- Every full session bubble has its own close control, revealed only while that
  card is hovered. Closing hides only that exact `status + updatedAt`
  presentation; it does not navigate, acknowledge, stop, archive, or remove the
  session from the main panel.
- A later status or timestamp for the same session is a new notification and
  makes its bubble eligible to appear again.

## Window behavior

The bubble overlay remains a non-activating `NSPanel`, but it now accepts mouse
events. Its frame is derived from `BotBubblePresentation`: no content hides the
panel, a compact-only presentation uses a narrow frame, and full bubbles use a
two-row 328pt-wide viewport. This prevents a large transparent area from
intercepting clicks outside visible bubbles.

The presentation retains every eligible session instead of truncating at two.
One or two rows use a static stack; three or more use a vertical `ScrollView`
with the highest-priority and newest sessions first. The system scrollbar is
disabled at the underlying `NSScrollView`, even when macOS is configured to
show scrollbars permanently. There is no redundant custom scroll rail; trackpad
or mouse-wheel motion moves the cards directly within the two-row viewport.

## Visual system

Conversation cards use a 64pt height, 17pt continuous radius, system typography,
a restrained solid surface, and a low-contrast border/shadow. A 3pt state rail
and compact trailing indicator carry status: red for input, green for unread
Ready, and blue with an animated arc for running. Translucent AppKit materials
are intentionally avoided inside the transparent panel after render testing
showed unstable black compositing regions.

## Verification

- Controller tests cover empty, compact-only, one-row, mixed window sizes, and
  capped multi-row viewport sizes, plus close-without-navigation behavior.
- Activation tests verify navigation and Ready acknowledgement use the same
  selected session.
- Store tests verify dismissal keeps the active session and a newer version
  becomes visible again.
- Existing focus tests verify that the interactive bubble panel still cannot
  become the key or main window.
- Render tests cover the normal two-card composition and a four-Ready-session
  hosted scroll viewport.
- AppKit policy coverage verifies that the scroll viewport removes both legacy
  and overlay system scrollers while retaining scroll behavior.
