# Adjustable bot size design

## Goal

Let users resize the floating companion directly from the Appearance settings
page while preserving its position, click behavior, and attached session UI.

## Preference

`PetAppearanceStore` owns a locally persisted bot size. The supported range is
64 through 160 points, the default remains 84 points, and the settings slider
moves in four-point increments. Persisted values outside the supported range
are clamped during restoration.

## Window behavior

`BotView` renders the selected pet using the stored size. `BotWindowController`
observes the same preference and resizes the transparent AppKit panel around
the bot's current center instead of replacing or repositioning the window.
Intermediate slider values do not clamp the panel back into the visible screen,
because repeated clamping would turn size changes into cumulative position
drift near an edge.
After every size change, the mouse-through session-bubble overlay is anchored
again against the new bot frame. The compact session panel continues to use
the resized frame as its placement reference.

## Settings layout

Appearance keeps the two-column pet image library. A DISPLAY section below it
combines the size slider and status-animation switch in one card, avoiding a
taller settings window. The slider shows its current point value and quiet
small/large range labels beneath a container-width SwiftUI track. The labels
are tertiary metadata rather than decorative endpoint icons, so the control
has no ambiguous gap before its track. The row uses a fixed icon column and a
single content column: title, current value, track, and range labels all share
the same horizontal bounds. The icon aligns with the title rather than the
combined height of the control. The visible track itself reaches those content
bounds; only the thumb centers stay inset by their radius, avoiding a second
visual indentation beneath the title.

## Verification

Tests cover default size, persistence, invalid-value clamping, live AppKit
window resizing, center preservation, and repeated edge-adjacent resizing
without drift. The complete Appearance page is
rendered at 2x to check the slider, labels, and remaining content for clipping.
