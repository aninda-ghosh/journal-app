# Changelog

All notable changes to Journal are recorded here.

Version numbers read left to right: the first changes only if you'd have to do
something differently, the second when something new is added, and the third
when something is fixed.

## 2.0.1 — 2026-09-12

### Photos are stored as one 256px square

The photo pipeline is now single-tier on both platforms, and this changes what
lands on your disk — so it is worth reading before you update.

- **One file per photo.** A photo is centre-cropped to a 1:1 square, scaled to
  256×256 and encoded as JPEG at 0.82 quality. If the lower dimension is less
  than 256px, it is enlarged to 256px; if larger, it is downscaled. That square
  is the only copy kept: the file you picked is not stored beside it, and the
  crop cannot be undone. Keep your originals in Photos, or wherever you already
  keep them.
- **The `.thumb.jpg` tier is gone.** At 256px the stored square is already small
  enough to serve the calendar and the feed directly, and a second tier doubled
  the file count every iCloud sync had to reconcile.
- **Nothing already on disk changes.** Photos stored at the old size still
  display at that size; entries keep pointing at exactly the files they always
  did. Old `.thumb.jpg` files simply become unreferenced.
- **Feed gallery portrait aspect ratio fixed.** Single-photo feed cards no
  longer constrain the image to a fixed-height landscape box that sheared
  additional slices off portrait and square photos.
- **Journal → Reclaim Unused Photos…** finds photos no entry refers to —
  including those orphaned thumbnails — and moves them to the Trash, never
  straight to nowhere.
- **Two-column entry layout with fixed-size media.** Entries with photos
  now display as a two-column card with a compact 220px fixed image on the left
  and prose in the larger right section. The image remains crisp without
  expanding when the window widens, and stacks vertically on narrow viewports.
- **Book-like justified prose.** Paragraphs in entries on both macOS and iOS
  now render with justified margins and natural hyphenation for a refined,
  publication-grade reading experience.
- **Migration tool for existing libraries.** Added `mac/tools/migrate-media-256.swift`
  to safely convert historical photo collections into 256×256 px squares with
  automatic backup.

### Fixed

- **Editing an entry no longer restamps it.** Saving an edit rewrote the entry's
  `date` to the current moment while its id kept the original day, so the
  calendar and the feed disagreed about when it was written, permanently.
- **Two entries in a row on iPhone could overwrite each other.** The id was
  taken from when the composer opened rather than when Save was pressed, so a
  second entry written without leaving the tab silently replaced the first.
- **Entries written on the Mac now read properly on iPhone.** The phone wrote a
  space where the Mac writes a `T` in timestamps, and only accepted its own
  form — so every Mac-written entry showed a raw `2026-09-08T14:30:00` in the
  feed and no time at all in the calendar. Both forms are accepted now; `T` is
  written.
- **Dates no longer break on non-Gregorian calendars.** Every date formatter
  that touches the stored format is pinned to a fixed calendar and locale. A
  device set to a Buddhist or Japanese calendar was writing era years into
  entry ids.
- **Photos from an iPhone are no longer stored sideways.** EXIF orientation was
  never applied, so portrait photos were saved rotated — and centre-cropped on
  the wrong axis. Transparent images are also flattened onto white rather than
  black, matching the Mac.
- **Dictation no longer repeats itself.** Each pass of the speech engine was
  seeded with the previous pass's text; over an overlapping window that feeds
  itself, and phrases began to loop.
- **The last words of a take are kept.** On iPhone, results arriving in the
  moment after you stop were discarded by the very code that waited for them.
  On the Mac, a slow finish threw away the whole ramble instead of handing back
  what it had heard.
- **A failed start releases the microphone.** If audio capture failed part-way,
  the microphone stayed live and the button believed it was still recording.
- **Dictation failures are reported while they matter.** The speech engine
  reports readiness before the model has finished loading, so it can still fail
  once you are mid-sentence; the window is now told, instead of letting you talk
  into nothing until you stop.
- **The speech helper no longer aborts on a bad model.** It crashed rather than
  exiting when the weights could not be loaded.
- **Entries evicted by iCloud come back.** On iPhone the placeholder files that
  iCloud leaves behind are hidden, and the enumerator was skipping hidden files
  — so the code meant to download them could never run, and the entries just
  disappeared from the list.
- **An unsaved draft survives the app being killed** on iPhone, as it already
  did on the Mac.
- **Entry bodies render as Markdown on iPhone** instead of showing raw
  asterisks.
- **Save is no longer offered for a title with nothing under it**, which storage
  would refuse anyway.
- **Typing while dictating no longer duplicates the spoken text.**
- **`journal://` cannot reach outside `media/`.** The path check confirmed only
  that a request stayed inside the journal folder.
- **The window can ask for the microphone, and only the microphone.** The
  permission handler also covered the camera.
- **Dark mode's accent tint is visible again** — an eight-digit hex made it
  12.5% opaque, so tag chips nearly vanished.
- **Keyboard focus is visible**, and the calendar's day buttons have accessible
  names. Reduced-motion preferences are respected.

### Improved

- **Photos are decoded once, off the main thread, on iPhone.** A month of
  calendar tiles was decoding up to 31 JPEGs on the main thread on every
  redraw. Importing a photo no longer freezes the composer either.
- **The renderer runs sandboxed**, and no longer leaks a preview image per photo
  added.
- **`make.command` tracks dependency freshness.** Modifying `transcriber.cpp` or
  `CMakeLists.txt` automatically triggers a rebuild of the speech helper, and
  editing `package.json` updates dependencies. Packaging warns if the transcriber
  is missing.
- **`whisper-check.js` strictly validates PCM format.** Asserts that input audio
  is 16 kHz mono 16-bit PCM before starting the speech engine.

### Added

- **[`docs/FORMAT.md`](docs/FORMAT.md)** — the entry format written down as a
  contract rather than implied by two implementations.
- **`spec/fixtures/`** — one Markdown file per awkward case and the parse it
  must produce. Both platforms check themselves against the same files, so a
  drift between them fails a test instead of surfacing as a wrong date on
  someone's phone.
- **Continuous integration** — the format fixtures, the desktop end-to-end
  suite, the iPhone verification suites and the Xcode build, and a compile of
  the speech engine.
- **`ios/run-tests.sh`** — every iPhone suite in one command, instead of five
  `swiftc` lines copied out of the docs.
- **Linting** (`npm run lint`) and an `.editorconfig`.

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
