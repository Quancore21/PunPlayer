# Notice

PunPlayer © 2026 [Quancore21](https://github.com/Quancore21), licensed under the **GNU GPL v3.0** (`LICENSE`).

It is a derivative work. The queue, playback, playlist, statistics and lyrics logic was re-implemented in
Swift from these GPLv3 projects, and the feature set is modelled on them. The Android code cannot run on iOS,
so no source file is copied; each ported file names its origin in its header comment.

| Project | Author | License | Ported / modelled |
|---|---|---|---|
| [TimberX](https://github.com/naman14/TimberX) 1.8 | Naman Dwivedi | GPLv3 | play queue (`Core/PlayQueue.swift`), playback flow, library structure |
| [Musicr](https://github.com/dtrung98/MusicPlayer) | dtrung98 | GPLv3 | smart playlists, LRC lyrics (`Core/Lyrics.swift`), M3U (`Core/M3UWriter.swift`) |
| Phonograph (code inside Musicr) | Karim Abou Zeid | GPLv3 | shuffle helper, history and play-count stores (`Core/PlayStats.swift`) |
| CyanogenMod (code inside Musicr) | The CyanogenMod Project | Apache-2.0 | play-count scoring (compatible with GPLv3) |

Deliberate differences from the originals (bug fixes and iOS adaptations) are marked `DEVIATION` in the code.

No fonts, icons or artwork of the originals are used. The app icon was supplied by the project author.
There are no third-party dependencies.

## What the license means
Whoever receives a build (for example an IPA sideloaded by a friend) must be able to get the source under the
same license. The GPL conflicts with App Store terms.

PunPlayer is **not** independent of the projects above: porting to Swift, renaming or rewording does not change
that. An independent implementation would have to be a separate clean-room project (new repository, written from
a neutral specification by someone who has not seen this code or the originals, with documented provenance).
Before publishing a build, check the licenses of any dependency or resource added since this notice.
