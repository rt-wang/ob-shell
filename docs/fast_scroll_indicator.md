# Feature: Fast-Scroll Indicator on Home

## Summary

When the Home screen's note list grows long (deep Recent Notes, Edited Today,
Edited This Week, and Daily Notes sections stacked together), reaching content
far down the page requires many small swipes. This feature adds a draggable
fast-scroll indicator on the right edge of the Home `ScrollView`. The user can
grab it and drag vertically to move through the full list quickly, then release
to settle. It behaves like the familiar iOS "scrubber" grabber: quiet and hidden
most of the time, revealed during interaction.

This is a navigation affordance only. It does not change list contents, ordering,
or any file behavior.

## Problem

The Home list is a single vertical `ScrollView` (`HomeView.homeContent`) holding
multiple `NoteSection`s. On a vault with many recent notes this becomes long, and
normal flick-scrolling is slow to traverse top-to-bottom. There is currently no
way to jump or fast-scroll. The default system scroll indicator is hidden
(`.scrollIndicators(.hidden)`), so there is not even a visual sense of position.

## Goals

* Let the user travel the full Home list with one continuous drag.
* Show current scroll position while scrolling so depth is legible.
* Stay out of the way: hidden at rest, appears on scroll or touch, fades out
  after inactivity.
* Never interfere with normal vertical swipe scrolling or with tapping note rows
  to open them. (See the related fix that moved the greeting-dismiss tap to a
  background layer so it stops competing with row taps and the scroll pan.)

## Non-Goals

* No alphabetical / A–Z section index scrubber.
* No section-title "fast jump" labels next to the thumb in this pass.
* No change to the Markdown editor scroll view or the directory drawer scroll.
* No persistence of scroll position across launches.
* No custom physics — rely on the system `ScrollView` for momentum and bounce.

## Behavior

### Visibility

* Hidden when the list is at rest and untouched.
* Appears when the user begins scrolling or touches the right-edge region.
* Tracks the current scroll offset as a thin vertical thumb on the right margin.
* Fades out after a short inactivity delay (about 1.2s) once scrolling stops.
* Only shown when the content is meaningfully taller than the viewport (e.g.
  content height exceeds the viewport by more than ~1.5×); short lists never
  show it.

### Dragging

* Touching and dragging the thumb maps the drag's vertical position to a scroll
  offset across the full content height, so a full-height drag spans the whole
  list.
* While dragging, the list follows the thumb directly (no momentum); on release
  the list stays where it landed.
* A light haptic tick (`UIImpactFeedbackGenerator`, soft style) fires when a drag
  begins, keeping with the restrained feel.

### Hit area

* The visible thumb is narrow, but the touch target on the right edge is wider
  (about 28–32pt) so it is grabbable without precision.
* The hit area lives only along the right edge and must not overlap note rows'
  tap targets, so tapping a note anywhere else still opens it normally.

## UI Direction

Follow the Editorial Minimal palette and restraint from `style_guide.md`.

* Thumb: a thin rounded capsule, roughly 3pt wide and 44–64pt tall, inset a few
  points from the right edge.
* Color: `EditorialColor.mutedAccent` (#C9C2B8) at rest, deepening toward
  `EditorialColor.secondaryText` while actively dragging. No saturated color.
* Optional position bubble while dragging: a small quiet pill showing the current
  section name (e.g. "Edited This Week") in compact sans-serif
  (`EditorialFont.ui(.caption)`), `EditorialColor.surface` fill with a hairline
  border. Keep it subtle; omit if it feels heavy.
* Motion: fade in/out and a gentle position spring consistent with the existing
  `.spring(response: 0.28, dampingFraction: 0.88)` style used elsewhere.
* No drop shadows beyond what the rest of the app uses; no borders heavier than a
  hairline.

## Implementation Notes

Target: `FastObsidianMobile/HomeView.swift`, the `homeContent` `ScrollView`.

* Wrap the existing `ScrollView` in a `ScrollViewReader` or use a
  `GeometryReader` + scroll offset preference key to read content height and the
  current vertical offset. SwiftUI's `.scrollPosition` / scroll geometry APIs are
  acceptable if available on the deployment target.
* Track offset via a `PreferenceKey` reporting the content's `minY` against the
  outer container coordinate space; derive a 0...1 progress value.
* Overlay the indicator with `.overlay(alignment: .trailing)` on the scroll
  container so it floats above content and ignores the horizontal content
  padding.
* Drive scrolling from a drag by translating the gesture's `location.y` into a
  target offset, then scrolling to it (programmatic scroll to an anchor, or by
  binding scroll position). Keep the mapping clamped to `0...1`.
* Reuse the section model already rendered in `homeContent` (Recent Notes,
  Edited Today, Edited This Week, Daily Notes) to label the optional position
  bubble; do not introduce a parallel data source.
* Gate the whole overlay behind the "content taller than viewport" check so it is
  inert on short lists and on the empty / choose-vault states.

Keep it a small, self-contained subview (e.g. `private struct FastScrollIndicator`)
so `HomeView` stays readable.

## Acceptance Criteria

* With a long Home list, a vertical drag on the right edge moves through the
  entire list in one gesture, and releasing leaves the list settled at that spot.
* The indicator is hidden at rest, appears while scrolling or dragging, and fades
  out after scrolling stops.
* The indicator does not appear when the list is shorter than the viewport, nor
  on the empty-vault or choose-vault states.
* Normal flick scrolling and tapping a note row anywhere outside the right-edge
  grabber are unaffected.
* Colors, typography, and motion stay within the Editorial Minimal direction in
  `style_guide.md`.
* The app builds with `xcodebuild` for the iOS Simulator.
