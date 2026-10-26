# Contributing to PunPlayer

Thanks for helping improve PunPlayer. It is an early iPhone music player; reliability and usable playback controls take priority over decorative UI changes.

## Before opening a pull request

1. Run `swift test` from the repository root.
2. Run `python3 Scripts/validate_localizations.py`.
3. If you have macOS and Xcode, run `xcodegen generate`, build the `PunPlayer` scheme and test on a simulator or device.
4. Update both `en.lproj/Localizable.strings` and `ru.lproj/Localizable.strings` for user-facing text. Keep format placeholders in the same order and type.
5. Update `CHANGELOG.md` when changing behavior.

## UI rules

- Respect safe areas and the available width. Never rely on an unconstrained `scaledToFill` image as a layout sibling.
- Keep player controls tappable, accessible and visible on compact iPhones and with long localized strings.
- Keep the mini-player inside a reserved bottom safe-area inset; it must not cover the scrollable page content.
- Use the established amber accent and theme tokens rather than hard-coded colors scattered through screens.
- Use native SwiftUI navigation and presentation primitives unless there is a clear, tested reason not to.
- Avoid changing audio-engine, queue or persistence behavior as a side effect of UI-only work.

## Commit and PR guidance

Use a short imperative title, explain the problem and the chosen fix, and include test results. For UI changes, attach before/after screenshots and note device + iOS version. Never commit signing certificates, provisioning profiles, credentials, private music or generated `.ipa` files.
