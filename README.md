# CarLyrics

An iPhone app that shows synced lyrics for whatever you're playing on Spotify. In the app, the
current line lights up word by word. On the Lock Screen and the CarPlay dashboard, a Live
Activity card shows the line being sung and the one after it.

I built it because the app I was using started charging for the real-time lyrics widget.

<img src="docs/login.png" width="260" alt="CarLyrics start screen">

## How it works

- **Spotify.** You log in once (Authorization Code with PKCE, so there's no client secret on the
  phone). The app asks Spotify's Web API what's playing every 2 seconds and fills in the
  position between checks.
- **Lyrics.** Lyrics come from [LRCLIB](https://lrclib.net), which is free and needs no API key.
  Most songs have timestamps for each line. If a song only has plain lyrics, the app spreads
  the lines evenly across the song and says the timing is a guess.
- **Word by word.** LRCLIB times whole lines, not words, so the app estimates when each word
  starts from how long the word is. It's close enough to sing along to.
- **CarPlay.** iOS 26 shows Live Activities on the CarPlay dashboard when they support the
  `.small` activity family. That means this doesn't need Apple's CarPlay entitlement. The
  card's background color is sampled from the album art.
- **Background updates.** iOS suspends apps soon after you leave them, which would freeze the
  card. The app plays silent audio mixed with Spotify's (it never interrupts it) so it can
  keep pushing new lines. That's fine for personal use but would not pass App Store review.

## Requirements

- iPhone on iOS 26 or later (CarPlay Live Activities need 26)
- Xcode 26 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- A Spotify account and an app on the [Spotify developer dashboard](https://developer.spotify.com/dashboard)
- An Apple developer account. A free one works, but free installs expire after 7 days.

## Setup

1. Create a Spotify app on the developer dashboard. Check **Web API**, and add
   `carlyrics://callback` and `http://127.0.0.1:8888/callback` as redirect URIs.
2. Put your client ID in `CarLyrics/Config.swift`, `tools/login_on_mac.py`, and set your own
   `DEVELOPMENT_TEAM` and bundle IDs in `project.yml`.
3. Run `xcodegen generate`, open `CarLyrics.xcodeproj`, pick your iPhone, and press Run.
4. Tap **Connect Spotify**, play a song, and turn on **Show in CarPlay**.

If lyrics show up after the singer, use the timing offset in Settings. Bluetooth audio usually
runs a little behind.

### If Spotify's login page errors on the phone

Spotify's login page sometimes fails inside the app's login sheet with "Oops! Something went
wrong." With the phone plugged into your Mac, run:

```sh
python3 tools/login_on_mac.py <device-udid>   # UDID from: xcrun devicectl list devices
```

It logs in through your Mac's browser and copies the login into the app on the phone.

## Sharing it

A web app or PWA can't do this. Only native apps can show Live Activities or anything else in
CarPlay. Without the App Store, the options are:

- **Build it yourself.** Anyone with a Mac can clone this repo and follow the setup above with
  their own Spotify app. This is the easiest option, since every person has their own Spotify
  quota.
- **Ad Hoc builds.** A paid Apple developer account can register up to 100 iPhones a year by
  UDID and send them a signed build.
- **TestFlight.** Up to 100 internal testers skip review. External testers need a beta review,
  and the silent-audio trick may not pass it.

Spotify also limits apps in development mode to a small allowlist of users, which you manage
under **User Management** on the dashboard. Going past that requires Spotify's extended quota
approval.

## Project layout

| Path | What's there |
| --- | --- |
| `CarLyrics/` | The app: Spotify login and API, LRCLIB lookup, sync engine, background keep-alive, UI |
| `CarLyricsWidget/` | Live Activity views for CarPlay, the Lock Screen, and the Dynamic Island |
| `Shared/` | `LyricsActivityAttributes`, used by both targets |
| `tools/` | The Mac login fallback |

Lyrics are provided by [LRCLIB](https://lrclib.net).
