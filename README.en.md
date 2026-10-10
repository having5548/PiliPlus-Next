<div align="center">
    <img width="200" height="200" src="assets/images/logo/logo.png">
</div>

<div align="center">
    <h1>PiliPlus Next</h1>
    <p>A community fork of <a href="https://github.com/bggRGjQaUbCoE/PiliPlus">PiliPlus</a> — adds a vertical "Featured" feed, focused on four-platform support and bug fixing</p>
</div>

<div align="center">

[![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20Android%20%7C%20macOS%20%7C%20iOS-2f81f7)](#platforms)
[![License](https://img.shields.io/badge/license-GPL--3.0-3fb950)](LICENSE)
[![Release](https://img.shields.io/github/v/release/having5548/PiliPlus-Next?label=latest&color=fb7299)](https://github.com/having5548/PiliPlus-Next/releases)

[中文](README.md) | **English**

</div>

> **Source project: https://github.com/bggRGjQaUbCoE/PiliPlus** — all credit goes to the upstream author [bggRGjQaUbCoE](https://github.com/bggRGjQaUbCoE) and contributors.

---

## Preview

### Featured vertical feed (new in this fork)

A Douyin-style vertical full-screen recommendation feed, available as a tab in the main UI (**sidebar stays visible**), with a bilibili-client-style slim progress bar, a full action rail, and working danmaku:

![Featured vertical feed](docs/images/featured-feed.jpg)

<details>
<summary>What it does (click to expand)</summary>

- **Bottom control bar**: play/pause, current time, a **draggable** progress bar, total duration, volume
- **Danmaku**: displayed and scrolling, plus a **danmaku toggle** and a **danmaku settings** panel (visibility / opacity / font size / display area) that applies instantly and persists
- **Action rail**: like, coin, comment, share (copies the bilibili link), details
- **Coin** uses the **original** panel (1 or 2 coins, with an optional "like as well" checkbox)
- **Comments** slide in **from the right** and the player shrinks accordingly; click again or press close to collapse
- **Keyboard**: space to play/pause, arrow up/down to switch videos
- **Mouse wheel**: one item per notch, with a 320 ms animation lock
- **No black flash when switching**: the video layer persists, only text and buttons are rebuilt
- The control bar **stays while paused and auto-hides ~3 s after playback starts**

</details>

### Software settings

A new "Software settings" category with **launch at startup** and **minimize to tray on close**; the startup state stays in sync with the installer option:

![Software settings](docs/images/settings.png)

---

## What this fork adds

### 1. Featured vertical feed (the headline feature)

Upstream has no such page. It turns the recommendation feed into a Douyin-style vertical full-screen video feed, aligned with the bilibili client and Douyin in interaction:

| Capability | Detail |
| --- | --- |
| Vertical switching | Swipe, arrow keys, or mouse wheel — one item per step |
| Full playback control | Draggable progress bar (slim track + buffered bar + thumb), play/pause, duration, volume |
| Danmaku | Displayed and scrolling, with a **toggle** and a **settings** panel |
| Interactions | Like, **original coin panel**, comment, share (copy link), open detail page |
| Comments | Slide in from the right, player shrinks (Douyin style) |
| Keyboard | Space to play/pause, arrow keys to switch |
| No black flash | The video layer persists across page changes |

### 2. Desktop UI rework

- **Icon-only sidebar** (for all non-portrait layouts), settings entry preserved
- **Volume button** in the player
- **Wide-screen video page layout** redone: player on the left, intro + comments on the right
- Landscape: the space below the player is filled with the plain-text description
- Removed leftover action buttons from the "Mine" page header

### 3. Software settings

- New "Software settings" category: **launch at startup**, **minimize to tray on close**
- **Startup state stays in sync with the installer** (previously ticking it during install left the setting showing as off)

### 4. Upstream bug fixes

- **9 upstream issues fixed** in one pass: `#3086` `#3107` `#3036` `#3049` `#3082` `#2422` `#2955` `#3136` `#3071`
- **Per-part resume**: switching to another part and back no longer restarts that part (`#2916` `#3139`) — submitted upstream as PR [#3237](https://github.com/bggRGjQaUbCoE/PiliPlus/pull/3237)
- Fixed the **blank settings page** (`RegCloseKey` export name)
- Assorted fixes: nested part lists on the detail page, subtitles, search results

The full list and progress live in [docs/BUGFIX.md](docs/BUGFIX.md) (upstream open issues were triaged — 79 groups after deduplication).

---

## Differences from upstream at a glance

| Area | Content |
| --- | --- |
| **New page** | Featured vertical feed (progress bar, danmaku settings, action rail, right-side comments, keyboard and wheel control) |
| **Desktop** | Icon-only sidebar, player volume button, wide-screen video layout, landscape description fill |
| **Settings** | "Software settings" category (launch at startup / minimize to tray), startup state synced with the installer |
| **Bug fixes** | 9 upstream issues, per-part resume, blank settings page |
| **Platforms** | Builds and publishes **Windows / Android / macOS / iOS**. Linux: the `linux/` scaffold and the upstream `linux_x64.yml` workflow are **kept but unmaintained** — this fork neither builds nor publishes Linux artifacts. HarmonyOS: a scaffold (`ohos/`) was tried and then **removed** |
| **Tooling** | `patch.ps1` pub-cache path fix on Windows, `build.ps1` `GITHUB_ENV` guard, Gradle mirror |

---

## Platforms

- [x] Android
- [x] Windows (Inno Setup installer)
- [x] macOS (DMG built in CI)
- [x] iOS (unsigned ipa built in CI, for sideloading)

> Linux and HarmonyOS are **outside this fork's build and release scope** (the Linux scaffold and upstream workflow are still in the repo but unmaintained; the HarmonyOS scaffold was removed). See the [differences table](#differences-from-upstream-at-a-glance) above.

## Download

- Grab a build from [Releases](https://github.com/having5548/PiliPlus-Next/releases)
- Or clone the repo and build locally (see below)

## Building from source

> **Read first**: this project depends on a set of **Flutter SDK patches** and **will not compile without running the patch script**.

1. Install **Flutter 3.47.6 stable** via git clone (version pinned in `.fvmrc`; the patches target this version)
2. Set environment variables:
   - `FLUTTER_ROOT` → your Flutter SDK directory
   - `GITHUB_WORKSPACE` → this repository root
3. `flutter pub get`
4. Run `pwsh lib/scripts/patch.ps1 <platform>`
   (`platform` = `android` / `windows` / `macos` / `ios`; the script patches both the Flutter SDK and the `material_ui` / `cupertino_ui` packages in the pub cache)
5. Generate version info with `pwsh lib/scripts/build.ps1` (uses git history), or create `pili_release.json` by hand
6. Build:
   - Android: `flutter build apk --release --split-per-abi --dart-define-from-file=pili_release.json --no-pub`
   - Windows: `flutter build windows --release --dart-define-from-file=pili_release.json --no-pub`
   - macOS / iOS: built by GitHub Actions (`.github/workflows/mac.yml` / `ios.yml`)

> **Note on the Flutter version**: upstream's `.fvmrc` declares `3.47.7`, but following it would require downloading that SDK and re-applying every patch. This fork is verified to compile upstream's code with **3.47.6** (`dart analyze` clean, all four platforms build), so 3.47.6 is used for now; moving to 3.47.7 is a separate follow-up step.

## Reporting issues

Please search [docs/BUGFIX.md](docs/BUGFIX.md) and existing issues before filing a new one — upstream open issues were triaged here and duplicates will be merged.

## Acknowledgements

- [guozhigq/pilipala](https://github.com/guozhigq/pilipala) — original author
- [orz12/PiliPalaX](https://github.com/orz12/PiliPalaX) — upstream fork author
- [bggRGjQaUbCoE/PiliPlus](https://github.com/bggRGjQaUbCoE/PiliPlus) — the direct source project
- [bilibili-API-collect](https://github.com/SocialSisterYi/bilibili-API-collect) — bilibili API docs
- [media-kit](https://github.com/media-kit/media-kit) — cross-platform player
- [flutter_meedu_videoplayer](https://github.com/zezo357/flutter_meedu_videoplayer)

## License

Distributed under the **GNU GPL-3.0** license, same as the upstream project. See [LICENSE](LICENSE). Based on [PiliPlus](https://github.com/bggRGjQaUbCoE/PiliPlus); the modifications are the commits added in this repository, and all original copyright and license notices are retained.
