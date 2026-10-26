<p align="center">
  <img src="PunPlayer/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png" width="112" alt="PunPlayer app icon">
</p>

<h1 align="center">PunPlayer</h1>
<p align="center">Local music player for iPhone · SwiftUI · GPLv3</p>

<p align="center">
  <a href="https://github.com/Quancore21/PunPlayer/actions/workflows/build-ipa.yml"><img src="https://github.com/Quancore21/PunPlayer/actions/workflows/build-ipa.yml/badge.svg" alt="Build"></a>
  <a href="https://github.com/Quancore21/PunPlayer/releases"><img src="https://img.shields.io/github/v/release/Quancore21/PunPlayer?include_prereleases" alt="Release"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPL--3.0-blue.svg" alt="License"></a>
</p>

---

Play your own music. No streaming, no accounts, no bullshit.

Drop audio files into PunPlayer via Files app or the in-app importer and enjoy an artwork-first player with warm amber vibes.

## What's inside

- Full local library: songs, albums, artists, genres, folders
- Full-screen player with real decoded waveform and orbit play/pause animation
- Queue, shuffle, repeat, playback history
- Playlists (personal + smart) with M3U export
- Synced LRC lyrics
- Edge gestures for quick album/action access
- English & Russian UI, dark/light/system theme

Plays everything AVFoundation can decode — MP3, AAC, FLAC, WAV, AIFF, ALAC, etc.

## Install

1. Grab the IPA from [Releases](https://github.com/Quancore21/PunPlayer/releases)
2. Sideload with [AltStore](https://altstore.io/) or [Sideloadly](https://sideloadly.io/)

> The IPA is **unsigned** — not from the App Store.

## Build

```bash
# Core tests (any platform)
swift test

# iOS app (macOS + Xcode)
brew install xcodegen
xcodegen generate
open PunPlayer.xcodeproj
```

## Layout

```
PunPlayer/Core       Models and logic (platform-independent)
PunPlayer/Playback   AVPlayer, interruptions, Now Playing
PunPlayer/Services   Library, import, stores, artwork, persistence
PunPlayer/UI         SwiftUI views
Tests/               Unit tests
```

## License

[GPLv3](LICENSE) — see [NOTICE.md](NOTICE.md) for upstream credits.

Made by [@Quancore21](https://github.com/Quancore21)
