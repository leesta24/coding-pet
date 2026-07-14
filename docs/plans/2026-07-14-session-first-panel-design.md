# Session-first panel design

## Goal

Turn the floating panel into a compact session switcher. Remove decorative or
duplicated status chrome and use the existing window area to expose about four
session rows at once.

## Chosen layout

- Keep the existing 436x308pt panel window so opening the pet does not create a
  larger obstruction.
- Remove the CodingPet icon/title/subtitle, aggregate state capsule, section
  label, and session-count capsule. Those values are already represented by the
  pet, badges, and individual session rows.
- Keep one 32pt settings button at the top-right with its existing tooltip and
  accessibility label.
- Use a 46pt session row with 6pt gaps. Four rows occupy 202pt and fit beneath
  the settings button inside the existing surface.
- Preserve scrolling when more than four sessions exist and preserve the
  current priority ordering.

## Row information

Each row keeps only actionable context: session name, provider, lifecycle
summary, relative update time, status, and navigation affordance. The icon and
status use the normalized session color. Hover feedback and the combined
accessibility label remain intact.

## Empty state

When there are no active sessions, keep the settings button available and use
the remaining space for the existing empty-state guidance.

## Verification

- Render the panel with at least five sessions and visually confirm that four
  complete rows are visible without clipping.
- Confirm additional rows scroll.
- Confirm the settings button and session selection still invoke their
  existing callbacks.
- Run the complete Swift test suite.
