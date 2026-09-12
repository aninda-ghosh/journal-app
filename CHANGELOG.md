# Changelog

All notable changes to Journal are recorded here.

Version numbers read left to right: the first changes only if you'd have to do
something differently, the second when something new is added, and the third
when something is fixed.

## Unreleased

Nothing yet.

## 2.0.0 — 2026-09-12

Major release introducing the native iOS companion app, zero-cost cross-device iCloud Drive sync, continuous on-device rambling dictation, and desktop calendar enhancements.

### iOS Companion App

- **Native SwiftUI Application**: Built from the ground up for iPhone and iPad (`ios/Journal.xcodeproj`) with zero third-party dependencies.
- **Unified Theme & Aesthetics**: Complete design parity with the macOS desktop app — warm paper canvas (`#faf8f5`) in light mode, obsidian ink (`#17161a`) in dark mode, terracotta accents (`#9a5b3d`), and book-like serif typography.
- **Three Core Views**:
  - **Write**: Floating composer card, date picker pill, live mic waveform meter, 1:1 photo thumbnails, `#tag` chips, and instant Save.
  - **Calendar**: Visual monthly grid with square tiles displaying representative daily photos, today highlight, summary statistics, and interactive expandable day entries with inline photo galleries, full prose, tag chips, and instant editing.
  - **Entries**: Chronological card feed with search, active date filter pills, tag filters, and photo galleries.
- **Ergonomic Navigation**: Bottom selection tab bar optimized for single-handed thumb reach, with a clean and spacious top header.
- **Shared App Branding**: High-resolution icon and transparent squircle logo matching the Mac app.

### Free Cross-Device iCloud Sync

- **Zero Paid Developer Fees**: Uses standard iCloud Drive and Security-Scoped Bookmarks (the Obsidian / Working Copy model) — no $99/year Apple Developer account required.
- **Real-Time Desktop Ingestion**: The Mac app continuously watches `entries/` via `fs.watch` and automatically refreshes its calendar and feed whenever you write or dictate on your iPhone.
- **Foreground Re-Sync**: iOS automatically detects external updates from your Mac on app wakeup (`scenePhase`).
- **100% File Reciprocity**: Both apps read and write identical Markdown files with frontmatter (`entries/YYYY/MM/*.md`) and 1:1 square JPEG media (`media/YYYY/MM/*.jpg`).

### Dictation & Audio

- **Continuous Rambling & Pause Survival (iOS)**: Apple Neural Engine speech recognition now preserves earlier sentences across silence pauses. You can pause to think for several seconds without your previous thoughts disappearing.
- **AirPods & Bluetooth Input (iOS & macOS)**:
  - iOS audio session configured with `.allowBluetooth` and `.allowBluetoothA2DP` in `.spokenAudio` mode; automatically prioritizes connected AirPods and handles live route transitions.
  - macOS dictation queries `enumerateDevices()` to prioritize AirPods / Bluetooth headsets over the internal laptop microphone.
- **Instant Save Teardown**: Tapping "Save entry" while dictating immediately commits any in-flight speech in **0ms**, shuts down audio hardware, and saves the file without artificial delays.
- **Shortcut Parity**: Added `⌘ + Return` keyboard shortcut to save entries on both macOS and iOS.

### Desktop App Enhancements

- **Calendar Date Filtering Fix**: Clicking any date tile on the desktop calendar immediately filters the entries feed to that specific date and displays the active date chip in the filter bar.
- **Nav Reset**: Clicking the **Entries** button in the header nav (or pressing `⌘ 3`) clears the active date filter and returns to the full unconstrained feed.
- **Robust Date Key Matching**: `dayKeyOf` extracts `YYYY-MM-DD` via regex across both entry IDs and timestamps.

### Monorepo Architecture

- Structured into [`mac/`](mac/), [`ios/`](ios/), and [`docs/`](docs/) with unified build and testing tooling.
- In-depth system design, GPU compute pipeline, and developer runbooks in [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md).

## 1.0.0 — 2026-09-11

First release.

### Writing

- Entries with an optional title, Markdown body, tags and photos.
- **Calendar** view showing which days were written on. A day with photos shows
  one; several entries on a day share one square, leading with the photo from
  whichever entry was written at most length.
- **Entries** view, newest first, filterable by tag.
- Full-text search across everything.
- Unfinished entries survive quitting the app.

### Photos

- Drop, paste or choose them. Click any photo to see it full size.
- Cropped square and reduced to 2048×2048 on the way in, which keeps a year of
  daily photographs to a few hundred megabytes. **This is permanent** — keep
  your originals elsewhere.
- Photos the app can't decode are stored untouched rather than lost.
- Deleting an entry leaves its photos on disk.

### Dictation

- Press **Dictate** and talk; words appear as you speak and settle as you go.
- Runs entirely on your Mac using Whisper. The model ships inside the app, so it
  works offline, and audio is never written to disk.
- `Esc` discards a take and leaves the entry exactly as it was.
- **Journal → Check Dictation…** reports whether it's working.

### Your files

- Everything lives in `~/Documents/Journal` as Markdown files and images.
  Readable in any text editor, with or without this app.
- **Move…** relocates the journal and takes your entries and photos with it.
- The app and your journal are independent: replacing or deleting the app never
  touches a word.

### Notes

- Apple Silicon only. Unsigned, so the first launch needs right-click → **Open**.
- The only permission asked for is the microphone, and only when you first
  dictate.
