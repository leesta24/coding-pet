# Session panel visual refresh

## Goal

Make the floating session panel feel like a compact native macOS popover rather
than a large settings card containing more cards. Preserve direct navigation,
four-row capacity, non-activating focus behavior, and the single settings
control.

## Visual hierarchy

- Use one material surface with a restrained state-tinted wash.
- Group rows in one subtle list container; rows have no permanent card fill.
- Show hover fill only as interaction feedback.
- Replace large tinted square icons with 22pt circular state marks.
- Render provider as small uppercase metadata and status as unboxed colored
  text. The task name remains the primary scan target.
- Keep the settings control as the only chrome above the list.
- When the Codex hook is installed and local account limits are available, use
  the otherwise empty header space for one quiet, text-only usage summary.
  The header has no loading placeholder, error state, card, or persistent data
  when the hook is missing or damaged.

Spacing follows an 8pt-oriented scale: 10pt surface inset, 6pt header-to-list
gap, 12pt outer shadow allowance, and 52pt rows. The panel uses native system
typography and semantic foreground styles in light and dark appearance.

## Adaptive layout

The AppKit panel and SwiftUI root share `SessionPanelLayout`. One through four
sessions produce content-driven heights; five or more retain four visible rows
and scroll. The empty state has its own compact guided height. The controller
observes active-session count and resizes/repositions an open panel without
changing keyboard focus. While visible, the panel remains spatially anchored
to the pet: pet move and resize events reposition both attached overlays, while
a hidden session panel does no frame work. Visible overlays are native AppKit
child windows, so WindowServer moves them atomically with the pet; Swift only
recomputes clamped placement after the drag ends or dimensions change.

## Verification

- Layout tests cover empty, one, two, four, and overflow counts.
- Controller tests verify live resizing when the active count changes.
- Render tests cover both the two-row state from the reported screenshot and
  the four-row capacity state.
- Existing tests continue to cover focus preservation, outside-click dismissal,
  navigation, and settings access.
- Usage tests cover hook-gated loading and version-matched app-server parsing;
  render coverage includes the compact two-window usage summary.
