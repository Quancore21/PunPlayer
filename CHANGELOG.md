# Changelog

## 0.0.6

- Fixed orbit Play/Pause animation: authentic 3D orbit where the satellite sweeps behind the central dark planet and returns in front
- Fixed player gestures: widened swipe detection across the bottom control area to avoid iOS Home Indicator conflicts, eliminated content shifting
- Fixed player layout clipping: removed outer scroll container and dynamically scaled artwork to guarantee transport controls are always completely visible
- Added in-player gesture hint banner with instant dismiss toggle (persisted via Settings)
- Cleaned up repository: removed verbose docs, streamlined README

Notable changes for each version are listed here. Dates may be added when a release is published.

## 0.0.5 — in development

### UI, gestures and animation
- Added edge-only player gestures: swipe in from the right edge to open the current album's tracklist; swipe up from the bottom edge to open track actions. Dragging/tapping the artwork itself has no gesture behavior.
- Added a visible, dismissible home-screen gesture guide near Quick picks, a persistent Settings toggle to restore it, and a short Undo toast. Hiding the guide never disables the gestures.
- Added an album tracklist sheet so changing tracks stays within the player; the same list is also available from the visible actions menu.
- Added the PunPlayer two-circle Play/Pause animation, with immediate playback response and a Reduce Motion fallback.
- Added a mini-player waveform decoded from the audio signal with an actor-isolated cache keyed by a file fingerprint. Waveform and progress share a single lane inside the mini-player card; unsupported files show a plain progress line rather than a fake waveform.
- Tightened tracklist row layout, album-cover transition, and seek-thumb positioning for small displays and long metadata.

### Bugfix and verification
- Updated the project version to `0.0.5` / build `5`.
- Added edge-gesture and waveform regression conditions to project validation and a dedicated on-device UI checklist.
- Core logic, SwiftUI layout, AVAudioFile waveform decoding and AVPlayer behavior still require the device/CI checks described in `docs/UI_VALIDATION_0.0.5.md`; local Linux tests do not substitute for an iOS build.

## 0.0.4 — previous development build

### UI and interaction
- Replaced the overlay-style bottom mini-player with a normal layout row below the navigation stack; list content is no longer covered by the progress line or controls.
- Removed the animated waveform floating above the mini-player. Progress now sits inside the opaque mini-player card.
- Rebuilt the full player around the artwork, title/artist, a custom amber seek control and only three primary transport buttons (previous, play/pause, next).
- Moved shuffle and repeat to the actions sheet and made that sheet discoverable with a visible, text-labelled “Player actions” button.
- Removed the artwork swipe as a hidden way to discover actions; no core action requires a secret gesture.
- Fixed seek-position race: stale periodic AVPlayer time ticks can no longer overwrite the latest in-flight seek request. Older seek callbacks are ignored after a newer seek or track change.
- Reworked the seek thumb into a small amber dot, added VoiceOver value/adjustment support and preserved immediate feedback while dragging.

### Project and GitHub
- Updated marketing version to 0.0.4 and build number to 4.
- Updated the manual UI validation checklist to cover mini-player overlap and continuous seek interaction.

### Validation
- Core tests and localization/resource checks should run in GitHub Actions; an actual Xcode build and device-level playback test are still required before the release is considered device-verified.

## 0.0.3 — previous development build

### UI and interaction
- Player is a navigation screen instead of a large modal sheet, so it belongs to the app rather than feeling like a floating window.
- Moved the blurred artwork into a size-constrained background; it no longer participates as an unconstrained sibling in the layout.
- Rebuilt the player layout around explicit horizontal bounds, responsive artwork sizing and two-line title handling to prevent left/right clipping on compact screens.
- Replaced the custom full-screen action overlay with a native, scrollable action sheet; added clear Queue and Lyrics shortcuts and a persistent top-right actions button.
- Made the seek bar clamp invalid playback values before passing them to `Slider`.
- Kept the artwork-first direction, amber accent, language/theme support and the persistent mini-player.

### Project and GitHub
- Updated marketing version to 0.0.3 and build number to 3.
- Added contribution guidance and issue/PR templates.
- Expanded README for setup, testing, unsigned IPA installation and release publishing.
- Reduced the in-app logo asset size while retaining the full-resolution app icon.

### Validation
- Core tests and localization/resource checks are run locally where possible and again in GitHub Actions.
- A successful Xcode/iOS build and real-device UI checks are still required before calling this version device-verified.

## 0.0.2
- Core reliability improvements, import/storage recovery, English/Russian localization and first integrated PunPlayer visual system.
