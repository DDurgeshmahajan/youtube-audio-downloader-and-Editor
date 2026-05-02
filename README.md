# 🎵 YT Audio Downloader

> **The fastest way to save YouTube videos & audio on Android — no BS, just tap Share and you're done.**

Built with Flutter + native Android by **[Durgesh Mahajan](https://github.com/DDurgeshmahajan)**

---

## Why I Built This

I was tired of opening sketchy websites, clicking through five ads, waiting for some server to "process" my video, only to get a corrupted file half the time.

So I built this. It lives on your phone. It uses the real `yt-dlp` engine under the hood — the same one developers and power users trust — and it just... works. Share a link from YouTube, pick your quality, done. File saved to your Downloads folder.

No ads. No account. No cloud. Everything happens on your device.

---

## The Core Idea

The whole point of this app is that it gets out of your way.

You're watching a video on YouTube. You tap **Share → YT Audio Downloader**. The app opens, analyzes the link, shows you the available quality options, and downloads it. That's literally the entire flow. No copy-pasting links, no switching apps back and forth.

---

## Features

- **📤 Share-to-Download** — Share any YouTube link directly from the YouTube app. The downloader opens instantly and starts analyzing.
- **📋 Manual Paste** — Don't feel like sharing? Just open the app and paste your link directly. The URL box wraps text so long links don't go off-screen.
- **🎬 Video Quality Picker** — Automatically detects every available resolution (144p to 4K) and lists them in descending order so you always download the best quality first.
- **🎧 Audio Extraction** — Download audio only as MP3. Two modes: Best Quality (highest bitrate available) or Standard (optimized for smaller file size).
- **🔄 Self-Updating Engine** — The first time you download in a new session, the app silently checks if `yt-dlp` needs an update and refreshes it automatically. YouTube changes their API constantly; this keeps things working without you having to do anything.
- **📂 Saves to Public Downloads** — Files go straight to your `/Downloads` folder, not some buried app-private directory. Open your Files app and they're right there.
- **🖼️ Gallery Visible** — After saving, the app triggers Android's Media Scanner so videos appear in your Gallery immediately. No reboot needed.
- **✅ Success Animation** — When a download finishes, you get a satisfying animated checkmark (inspired by the GPay success screen) and a dialog showing the exact file path.
- **📱 Real Progress Tracking** — A live circular progress indicator shows download percentage and estimated time remaining while the file is being saved.
- **🌑 Dark UI** — Designed for night use. Deep purple + neon green palette, glassmorphism elements, no eye strain.

---

## How to Use

### The Easy Way (Share Intent)
1. Open YouTube, find your video.
2. Tap **Share**.
3. Select **YT Audio Downloader** from the share sheet.
4. The app opens — select Video or Audio tab, pick your quality.
5. Wait for the download. Tap **Awesome!** on the success screen.

### The Manual Way
1. Copy a YouTube URL.
2. Open the app directly.
3. Paste the link in the input box (tap the paste icon or long-press and paste).
4. Hit the arrow button → pick your format → done.

---

## Tech Stack

| Layer | Technology |
|---|---|
| UI Framework | Flutter (Dart) |
| Native Bridge | Kotlin + Flutter MethodChannel / EventChannel |
| Download Engine | `yt-dlp` via [`youtubedl-android`](https://github.com/yausername/youtubedl-android) |
| Media Muxing | FFmpeg (bundled via youtubedl-android) |
| Share Handling | `receive_sharing_intent` |
| File Scanning | Android `MediaScannerConnection` |
| Image Loading | `cached_network_image` |
| Permissions | `permission_handler` |

---

## Building From Source

```bash
# Clone the repo
git clone https://github.com/DDurgeshmahajan/ytdownloaderapp.git
cd ytdownloaderapp

# Install Flutter dependencies
flutter pub get

# Run on connected Android device (minSdk 24 required)
flutter run
```

> **Note:** Requires Android 7.0+ (API 24). The app needs `WRITE_EXTERNAL_STORAGE` and `MANAGE_EXTERNAL_STORAGE` permissions which are requested on first launch.

---

## Project Structure

```
lib/
  main.dart              # All UI + state + channel logic

android/app/src/main/
  kotlin/.../
    MainActivity.kt      # Native yt-dlp integration, download handler
  res/values/
    styles.xml           # Full-screen theme setup
  AndroidManifest.xml    # Permissions + share intent filters
```

---

## Known Limitations

- **Android only** — iOS doesn't allow sideloaded yt-dlp binaries, so no iOS support currently.
- **Age-restricted / private videos** — `yt-dlp` can't bypass videos that require login.
- **Shorts** — Most Shorts work. Some regional restrictions may cause failures.
- **Playlists** — Currently downloads single videos only.

---

## Permissions Explained

| Permission | Why |
|---|---|
| `INTERNET` | Downloading videos and fetching metadata |
| `WRITE_EXTERNAL_STORAGE` | Saving files to public Downloads (Android < 10) |
| `MANAGE_EXTERNAL_STORAGE` | Saving files to public Downloads (Android 10+) |
| `POST_NOTIFICATIONS` | Future: download progress notifications |

---

## License

AGPL v3.0 — use it, modify it, build on it. See the [LICENSE](LICENSE) file for more details. Just don't strip the credit.

---

<div align="center">

Made with way too much caffeine ☕ by **Durgesh Mahajan**

*If this saved you from a sketchy website, consider giving it a ⭐*

</div>
