# CarLyrics

Karaoke-style synced lyrics for whatever's playing on Spotify, shown as a Live Activity on
the **CarPlay dashboard** (iOS 26+), Lock Screen, and Dynamic Island. Free replacement for
Dynamic Lyrics' paid real-time widget.

## How it works
- **Spotify**: OAuth PKCE login → polls `/v1/me/player/currently-playing` every 2s, interpolates position between polls.
- **Lyrics**: [LRCLIB](https://lrclib.net) (free, no key). Synced LRC when available; plain lyrics fall back to evenly estimated timing.
- **CarPlay**: an ActivityKit Live Activity with `.supplementalActivityFamilies([.small])` — iOS 26 renders the `.small` family on the CarPlay dashboard. No CarPlay entitlement needed.
- **Staying live in the background**: a silent, mixed-with-others audio session (`UIBackgroundModes: audio`) keeps the app running so it can push each new line. Fine for personal sideloading, would not pass App Store review.

## Setup
1. In the Spotify dashboard app (client ID in `CarLyrics/Config.swift`), add redirect URI `carlyrics://callback`.
2. `xcodegen generate` (only needed after editing `project.yml`), open `CarLyrics.xcodeproj`, run on your iPhone.
3. Connect Spotify → tap **Show on CarPlay & Lock Screen** (auto-starts on every app open by default).
4. Use the lyrics-offset slider in Settings if lines feel early or late (Bluetooth adds delay).

## Layout
- `CarLyrics/` — app: auth, Spotify API, LRCLIB lookup, sync engine, keep-alive, UI
- `CarLyricsWidget/` — Live Activity views (CarPlay `.small`, Lock Screen, Dynamic Island)
- `Shared/` — `LyricsActivityAttributes`

### If Spotify login fails on the phone
Spotify's login page sometimes errors ("Oops! Something went wrong") inside the in-app sheet.
With the phone plugged in: `python3 tools/login_on_mac.py <device-udid>` (UDID from
`xcrun devicectl list devices`). It logs in via your Mac browser and copies the token into the app.
