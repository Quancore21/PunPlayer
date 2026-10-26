<p align="center">
  <img src="PunPlayer/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png" width="120" height="120" style="border-radius: 26px;" alt="PunPlayer Icon">
</p>

<h1 align="center">PunPlayer</h1>

<p align="center">
  <b>A fast, private, artwork-first local music player for iPhone.</b><br>
  Built with Swift & SwiftUI · Zero tracking · Pure local audio · GNU GPLv3
</p>

<p align="center">
  <a href="https://github.com/Quancore21/PunPlayer/actions/workflows/build-ipa.yml"><img src="https://github.com/Quancore21/PunPlayer/actions/workflows/build-ipa.yml/badge.svg" alt="Build Status"></a>
  <a href="https://github.com/Quancore21/PunPlayer/releases"><img src="https://img.shields.io/github/v/release/Quancore21/PunPlayer?include_prereleases&color=orange" alt="Release"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPL--3.0-blue.svg" alt="License: GPLv3"></a>
  <img src="https://img.shields.io/badge/iOS-16.0%2B-black?logo=apple" alt="iOS 16+">
</p>

---

## 🎵 Why PunPlayer?

In an era of monthly streaming subscriptions, algorithmic feeds, and cloud-locked libraries, **PunPlayer** is built for those who treasure owning their music collection.

No accounts. No sign-ups. No telemetry. No internet connection needed. Ever.

Drop your albums into the Files app, import via AirDrop, or pick documents from your device. PunPlayer turns your library into a warm, tactile, artwork-centered listening experience with signature amber aesthetics and liquid-smooth animations.

---

## ✨ Features & Highlights

### 🪐 Signature 3D Orbit Transport
The Play/Pause button is a tribute to celestial mechanics and the PunPlayer mark. When tapped, an amber satellite swings into orbit around a central dark planet, passes behind it in 3D perspective, emerges along the diagonal axis, and settles into the new transport state. Playback starts or pauses **instantaneously** on touch — the animation is purely visual and never delays audio.

### 📊 Real Decoded Waveforms
No fake randomized sine waves or decorative pulsing bars. PunPlayer decodes the genuine PCM audio signal using `AVAudioFile` into precise amplitude buckets, cached atomically by file fingerprint for seamless seek navigation and continuous visual scrubbing.

### 🖐️ Gesture-Driven Navigation (No Jitter)
- **Swipe ← from right screen edge:** The current album’s tracklist slides in as a sleek trailing drawer matching your gesture direction.
- **Swipe ↑ from bottom edge or anywhere on the screen:** The Track Actions sheet pops up effortlessly without fighting the iOS Home Indicator.
- **Fixed, non-scrolling player viewport:** Gestures never cause the album artwork or transport buttons to jitter or scroll off-screen.

### 📝 Synced LRC Lyrics
Follow along with karaoke-style synchronized scrolling lyrics from embedded audio tags or adjacent `.lrc` files.

### 🎛️ Complete Library & Queue Management
- **Full library sorting:** Tracks, Albums, Artists, Genres, Folders, and Playlists.
- **Queue control:** Drag-and-drop reordering, shuffle with history weighting, and smart repeat modes.
- **Smart & Personal Playlists:** Custom playlists, Most Played, Recently Added, and History with standard `.m3u` export.
- **System integration:** Background audio playback, Lock Screen media controls with full artwork, Control Center support, and headphone remote handling.

---

## 🎧 Audio Format Support

PunPlayer plays every format decoded natively by Apple's Core Audio / AVFoundation engine:

| Format | Container / Extension | Quality |
|---|---|---|
| **FLAC** | `.flac` | Lossless / Hi-Res (up to 24-bit / 192 kHz) |
| **Apple Lossless** | `.m4a`, `.alac` | Lossless |
| **WAV / AIFF** | `.wav`, `.aiff`, `.aif` | Uncompressed PCM |
| **AAC** | `.m4a`, `.aac` | High-efficiency compressed |
| **MP3** | `.mp3` | Standard compressed (ID3v1 / ID3v2.4) |

---

## 🛠️ Architecture & Under the Hood

For developers and audio enthusiasts interested in how PunPlayer is structured:

```
PunPlayer/
├── Core/             # Platform-independent models, pure logic, and algorithmic engine
│   ├── PlayQueue.swift          # Resilient queue, shuffle states & history tracking
│   ├── PlaybackSupport.swift    # Pure state resolvers (SeekRequestGate, EdgeSwipeResolver)
│   ├── Lyrics.swift             # Timestamped LRC lyrics parser & synchronizer
│   ├── LibraryGrouping.swift    # Stable multi-artist album ordering & folder trees
│   └── M3UWriter.swift          # Standard playlist serialization
├── Playback/         # AVPlayer wrapper, audio sessions & lock screen metadata
│   ├── PlayerEngine.swift       # Audio engine, session interruptions, remote commands
│   └── PlaybackClock.swift      # High-precision time observation and seek gating
├── Services/         # Background storage, file import, waveform decoding
│   ├── WaveformCache.swift      # Background actor for multi-channel PCM decoding & cache
│   ├── ArtworkStore.swift       # Memory/disk cache for embedded cover images
│   └── LibraryStore.swift       # Local metadata indexing and persistence
├── UI/               # Pure declarative SwiftUI interface
│   ├── NowPlayingView.swift     # Full-screen adaptive player with zero-clipping layout
│   ├── OrbitPlayPauseButton.swift # 5-frame 3D orbit button animation
│   ├── WaveformProgressVisual.swift # Custom Canvas/Path waveform seek bar
│   ├── AlbumTracklistSheet.swift  # Trailing slide-over album track drawer
│   └── RootView.swift           # NavigationStack root with embedded MiniPlayer
└── Tests/            # Unit tests running platform-independent logic
    └── PunCoreTests/            # Automated tests for queue, edge swipes, seek gate, LRC
```

- **Zero Third-Party Dependencies:** 100% native Swift 5 and SwiftUI. Builds cleanly with Xcode and XcodeGen without CocoaPods, Carthage, or external SPM packages.
- **Headless Unit Testing:** Core modules are packaged as a pure Swift package (`PunCore`), allowing instant test runs on macOS or Linux CLI via `swift test` without needing an iOS Simulator.
- **Race-Free Seeking:** Custom `SeekRequestGate` ensures fast seek actions never get overwritten by stale periodic ticks from AVPlayer.
- **ProMotion Ready:** All custom springs and transitions are tuned for 120Hz ProMotion displays.

---

## 📲 Installation

### Option 1: Sideloading (Recommended)
1. Download the latest `PunPlayer-0.0.7.ipa` from [GitHub Releases](https://github.com/Quancore21/PunPlayer/releases).
2. Sideload it using [AltStore](https://altstore.io/), [Sideloadly](https://sideloadly.io/), or [TrollStore](https://github.com/opa334/TrollStore).
3. Sign in with your Apple ID when prompted to generate a free personal provisioning profile.

### Option 2: Build with Xcode
```bash
# Clone the repository
git clone https://github.com/Quancore21/PunPlayer.git
cd PunPlayer

# Run platform-independent unit tests
swift test

# Generate Xcode project (requires XcodeGen: brew install xcodegen)
xcodegen generate

# Open and build in Xcode
open PunPlayer.xcodeproj
```

---

## 📜 License & Provenance

PunPlayer is licensed under the **GNU General Public License v3.0 (GPLv3)**. See [LICENSE](LICENSE) for the full text.

- **Author & Maintainer:** [Quancore21](https://github.com/Quancore21)
- **Credits & Provenance:** See [NOTICE.md](NOTICE.md) for details on upstream GPLv3 architecture inspirations (TimberX, Musicr, Phonograph).
