# UI & Audio Validation Checklist -- 0.1 (Beta)

## 1. App Icons (Liquid Glass & Classic)
- [ ] Fresh install shows the **Liquid Glass** app icon on the iOS Home Screen and in the Home header.
- [ ] Switching **Settings -> Personalization -> App icon** to **Classic** updates both the iOS Home Screen icon and the in-app header mark.
- [ ] Switching back to **Liquid Glass** restores the default icon without delay.

## 2. PunPun Companion & Mini-Faces
- [ ] On a fresh install, **Settings -> PunPun -> Show PunPun in player** is **off** by default.
- [ ] Enabling PunPun shows the animated mini-face in the mini-player and the full-body PunPun companion above the seek waveform in `NowPlayingView`.
- [ ] During playback, PunPun dances smoothly at a calm cadence synchronized with local waveform energy and onset flux.
- [ ] Pausing playback transitions PunPun to the sleeping pose with gentle breathing.
- [ ] Tapping PunPun triggers the closed-eye love pose (`punpun_love`), soft haptic feedback, and floating hearts.

## 3. Dynamic Island & Notch Safe-Area Clearance
- [ ] Opening the Album Tracklist Drawer (swipe left from right edge or via Player Actions) positions the drawer cleanly below the Dynamic Island, notch, and status bar clock.
- [ ] The drawer header displays localized **Album tracks** and the **Done** button.
- [ ] Album track count displays proper Russian and English pluralization.

## 4. Background Waveform Preloading
- [ ] Launching the app or importing songs schedules low-priority background waveform decoding (`WaveformCache.shared.preload`).
- [ ] Opening preloaded tracks displays their genuine PCM waveform immediately.
