# Appearance gallery design

## Goal

Keep Appearance as its own settings destination and make the pet artwork the
primary selection affordance. Each bundled pet should have one large visual
preview instead of sharing a compressed horizontal selector.

## Layout

The Appearance destination uses a two-column gallery. Each card contains one
large, state-aware pet portrait and a compact name row. The current pet is
identified with the session-state accent, a stronger outline, and a checkmark;
unselected cards remain visually quiet. The animation preference stays below
the gallery on the same page.

The gallery remains in the existing sidebar shell. The settings window grows
to 760 by 700 points so the gallery has useful image area and the Motion
section remains visible without introducing a nested scrolling surface.

## Behavior and accessibility

The entire portrait card is clickable. Selecting it writes through the shared
`PetAppearanceStore`, so the floating bot updates immediately and the choice
persists as before. Every card exposes its pet name and whether it is current
to accessibility clients; the visual checkmark is decorative.

## Verification

Render the complete settings window at 2x, inspect all four portraits and the
selected state for clipping or contrast issues, then run the complete Swift
test suite.
