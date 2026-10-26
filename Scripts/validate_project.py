#!/usr/bin/env python3
"""Lightweight contract checks for the repository's packaging and player navigation."""
from __future__ import annotations
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
errors: list[str] = []

def require(condition: bool, message: str) -> None:
    if not condition:
        errors.append(message)

project = (ROOT / "project.yml").read_text(encoding="utf-8")
root_view = (ROOT / "PunPlayer/UI/RootView.swift").read_text(encoding="utf-8")
player_view = (ROOT / "PunPlayer/UI/NowPlayingView.swift").read_text(encoding="utf-8")
engine = (ROOT / "PunPlayer/Playback/PlayerEngine.swift").read_text(encoding="utf-8")
playback_support = (ROOT / "PunPlayer/Core/PlaybackSupport.swift").read_text(encoding="utf-8")
playback_tests = (ROOT / "Tests/PunCoreTests/PlaybackSupportTests.swift").read_text(encoding="utf-8")
edge_swipe_tests = (ROOT / "Tests/PunCoreTests/PlayerEdgeSwipeTests.swift").read_text(encoding="utf-8")
orbit_button = (ROOT / "PunPlayer/UI/OrbitPlayPauseButton.swift").read_text(encoding="utf-8")

version_match = re.search(r'^\s*MARKETING_VERSION:\s*"([^"]+)"', project, re.MULTILINE)
require(version_match is not None and version_match.group(1) == "0.0.6", "project.yml must declare MARKETING_VERSION 0.0.6")
require('CURRENT_PROJECT_VERSION: "6"' in project, "project.yml must declare build number 6")
require('.navigationDestination(isPresented: $showNowPlaying)' in root_view, "Player must use NavigationStack navigation (not a modal player sheet)")
require('.sheet(isPresented: $showNowPlaying)' not in root_view, "Old modal player sheet must not return")
require('if !showNowPlaying {' in root_view, "Home mini-player/storage banner must hide while the full player is open")
require('MiniPlayer { showNowPlaying = true }' in root_view, "Mini-player must be part of the root layout flow")
require('.safeAreaInset(edge: .bottom' not in root_view, "Mini-player must not overlay home content through safeAreaInset")
require('private struct MiniProgress: View' in root_view and 'MiniProgress(clock: player.clock, song: song)' in root_view, "Waveform and progress must share one lane inside the mini-player card")
require('WaveformCache.shared.waveform(for: song)' in root_view and 'guard !Task.isCancelled else { return }' in root_view, "Mini-player must use actual waveform and reject stale async results")
require('WaveformProgressVisual(amplitudes: waveform, fraction: fraction' in root_view, "Mini-player must render waveform and progress in one visual")
require('.background { artworkBackground }' in player_view, "Blurred artwork must be installed as a constrained background")
require('struct SeekBar: View' in player_view and 'DragGesture(minimumDistance: 0' in player_view, "Seek control must respond continuously to touch/drag")
require('Button { player.toggleShuffle() }' not in player_view, "Shuffle must live in the actions menu, not the main transport row")
require('Button { player.cycleRepeat() }' not in player_view, "Repeat must live in the actions menu, not the main transport row")
require('Text("Player actions")' in player_view, "Player actions menu must have a visible text label")
require('seekGate.complete(request)' in engine and 'guard !seekGate.isPending else { return }' in engine, "AVPlayer stale ticks must not overwrite an in-flight seek")
require('struct SeekRequestGate: Equatable' in playback_support and 'final class SeekRequestGateTests' in playback_tests, "Seek callback race must remain covered by core tests")
require('private func actionsOverlay' not in player_view, "Custom full-screen action overlay must not return")
require('TrackActionsSheet' in player_view and '.sheet(item: $activeSheet)' in player_view, "Player actions must use the native sheet")
require('case .tracklist' in player_view and 'AlbumTracklistSheet(currentSong: song, librarySongs: library.songs)' in player_view, "The current album tracklist must be a supported player panel")
require('sameArtist.count > 1' in (ROOT / 'PunPlayer/UI/AlbumTracklistSheet.swift').read_text(encoding='utf-8') and 'LibraryGrouping.albumOrder' in (ROOT / 'PunPlayer/UI/AlbumTracklistSheet.swift').read_text(encoding='utf-8'), "Album tracklist must handle multi-artist albums and stable track order")
require('edgeGestureOverlays(size:' in player_view, "Player gestures must be handled by edge gesture overlays")
require('PlayerEdgeSwipeResolver.resolve(' in player_view, "UI must delegate screen-edge gesture decisions to the pure resolver")
require('enum PlayerEdgeSwipeResolver' in playback_support and 'testSameHorizontalSwipeFromCentreDoesNothing' in edge_swipe_tests, "Edge-only gesture policy must be unit-tested, including no gesture from cover/centre")
require('testSwipeInFromRightEdgeOpensAlbumTracklist' in edge_swipe_tests and 'testSwipeUpFromBottomEdgeOpensTrackActions' in edge_swipe_tests, "Both edge gestures must have regression tests")
require('artwork itself has no drag' in player_view.lower() or 'there is deliberately no gesture attached to' in player_view.lower() or 'the main player content never receives' in player_view.lower(), "Player code must document that artwork does not own a gesture")
require('edgeGestureOverlays' in player_view and 'PlayerEdgeSwipeResolver.resolve(' in player_view, "Edge gesture overlays must handle edge swipes via the resolver")
require('.accessibilityAction(named: Text("Show album tracks"))' in player_view, "Album tracklist must be reachable through accessibility actions")
require('OrbitPlayPauseButton(' in player_view and 'accessibilityReduceMotion' in orbit_button, "Signature Play/Pause animation must honour Reduce Motion")
require('case .orbit' in orbit_button and 'case .depart' in orbit_button and 'case .rest' in orbit_button, "Orbit animation must include orbit phase, depart and rest")
require('offsetForAngle' in orbit_button and 'orbitRadius' in orbit_button, "Orbit path must use angle-based circular positioning")
require('onShowTracklist' in player_view, "Album tracks must be accessible from visible actions as well as a gesture")
require((ROOT / "PunPlayer/Services/WaveformCache.swift").is_file(), "Missing real-signal waveform cache")
require('AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)' in (ROOT / 'PunPlayer/Services/WaveformCache.swift').read_text(encoding='utf-8'), "Waveform must be decoded from audio, not synthetic")
require('options: .atomic' in (ROOT / 'PunPlayer/Services/WaveformCache.swift').read_text(encoding='utf-8'), "Waveform cache writes must be atomic")
require('showGestureGuide' in root_view and 'Show player gesture guide' in (ROOT / "PunPlayer/UI/SettingsView.swift").read_text(encoding="utf-8"), "Gesture guide preference must be available on home and in Settings")
require('Shortcuts start at the screen edges' in (ROOT / "PunPlayer/Resources/en.lproj/Localizable.strings").read_text(encoding="utf-8"), "Gesture guide must describe edge-only shortcuts")
require('On cover: album tracks' not in (ROOT / "PunPlayer/Resources/en.lproj/Localizable.strings").read_text(encoding="utf-8"), "Obsolete cover-swipe text must be removed")
require('.frame(height: 48)' not in player_view and '.frame(minHeight: 48)' in player_view, "Player header must not use a clipping fixed height")

for relative in [
    "README.md", "LICENSE", "NOTICE.md", "CONTRIBUTING.md", "SECURITY.md", "PunPlayer/UI/AlbumTracklistSheet.swift",
    "CHANGELOG.md", "docs/UI_VALIDATION_0.0.4.md", "docs/UI_VALIDATION_0.0.5.md",
    ".github/workflows/build-ipa.yml",
    ".github/ISSUE_TEMPLATE/bug_report.yml",
    ".github/ISSUE_TEMPLATE/feature_request.yml",
    ".github/PULL_REQUEST_TEMPLATE.md",
]:
    require((ROOT / relative).is_file(), f"Missing GitHub/project file: {relative}")

for relative in [
    "PunPlayer/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json",
    "PunPlayer/Resources/Assets.xcassets/PunPlayerMark.imageset/Contents.json",
]:
    path = ROOT / relative
    try:
        catalog = json.loads(path.read_text(encoding="utf-8"))
        for item in catalog.get("images", []):
            filename = item.get("filename")
            if filename:
                require((path.parent / filename).is_file(), f"Asset referenced but missing: {relative}/{filename}")
    except (OSError, json.JSONDecodeError) as error:
        errors.append(f"Invalid asset catalog {relative}: {error}")

if errors:
    print("Project validation failed:", *[f"- {e}" for e in errors], sep="\n", file=sys.stderr)
    raise SystemExit(1)
print("Project validation passed: version, edge-only gestures, playback controls, cached real waveform, localization, navigation/layout and build workflow files.")
