# Journal

**A private, local-first photo journal for your Mac and iPhone.** Write about your day, attach photos, and keep everything in plain files inside a folder that belongs entirely to you.

No accounts, no subscriptions, and zero cloud lock-in. Journal never connects to remote servers or third-party tracking — your words and photos stay on your devices. You can type, or just talk and let on-device speech models transcribe your voice in real time with complete privacy.

---

## Highlights

- **📅 Calendar View**: Monthly overview featuring representative photos from your writing, entry count badges, and single-click date filtering to view entries for any specific day.
- **✏️ Write / Composer**: Book-like serif typography, instant auto-save drafts, 1:1 square photo dropzones, `#tag` chips, and date picker.
- **📄 Entries Feed**: Chronological reading feed with full-text search, horizontal tag filter chips, photo galleries, and formatted date headers.
- **🎤 100% On-Device Neural Dictation**:
  - **macOS**: Custom C++ `whisper.cpp` engine accelerated directly on Apple Silicon Metal GPU unified memory (UMA).
  - **iOS**: Apple Neural Engine speech recognition with continuous rambling pause protection (never wipes out previous thoughts when you pause to think).
  - **Instant Save**: Tapping "Save entry" while dictating immediately commits any in-flight words, cleanly releases the microphone hardware, dismisses the keyboard, and saves the file in milliseconds.
- **🎨 Unified Design System**:
  - Warm paper canvas (`#faf8f5`) in light mode; obsidian ink (`#17161a`) in dark mode.
  - Terracotta accent (`#9a5b3d`), refined hairline borders, and serif typography (Iowan Old Style / Palatino / Georgia).
  - Shared branding, icons, and layout familiarity across Mac and iPhone.
- **☁️ Free Cross-Device iCloud Sync**: Automatic bidirectional syncing between your Mac and iPhone using standard iCloud Drive and Security-Scoped Bookmarks — **no $99/year Apple Developer membership required**.

---

## Getting Started

### macOS Desktop App

#### Pre-built App
Download the `.dmg` from the **Releases** section, open it, and drag Journal into your Applications folder. (Requires an Apple Silicon Mac: M1 or newer).

*On first launch: Right-click the Journal icon, choose **Open**, and confirm (standard for apps distributed outside the Mac App Store).*

#### Running from Source
```bash
cd mac
npm install
npm start
```

### iPhone Companion App

The native iOS companion app (`ios/Journal.xcodeproj`) runs on iOS 17.0+ and uses on-device neural voice models.

1. Open `ios/Journal.xcodeproj` in Xcode.
2. Under **Signing & Capabilities**, confirm your personal Team (free Apple ID) is selected.
3. Connect your iPhone via USB or select an iOS Simulator.
4. Press `⌘ R` to build and run!

---

## Free iCloud Drive Sync (No Paid Account Needed)

Journal uses the same security-scoped bookmark architecture as apps like Obsidian and Working Copy:

1. **On iPhone**:
   - Open Journal and tap the gear/cloud icon in the top header.
   - Tap **"Select Folder in iCloud Drive…"** and choose or create a folder named `Journal`.
2. **On Mac**:
   - Open menu **Journal** → **Move Journal Folder…**.
   - Navigate to your **iCloud Drive** and select that same `Journal` folder.
3. **Live Syncing**:
   - When you write or dictate on your iPhone, iCloud pushes the `.md` file to your Mac; the desktop app's file watcher detects the change and updates the calendar and feed automatically in real time.
   - When you open or return to the iPhone app, it automatically re-syncs with any changes made on your Mac.

---

## Keyboard Shortcuts (macOS)

| Shortcut | Action |
|---|---|
| `⌘ N` | New entry |
| `⌘ S` or `⌘ Enter` | Save entry |
| `⌘ F` or `⌘ K` | Focus search bar |
| `⌘ 1` | Switch to Calendar view |
| `⌘ 2` | Switch to Write view |
| `⌘ 3` | Switch to Entries view |
| `Esc` | Cancel dictation take / Dismiss lightbox |

---

## Your Files & Privacy

Everything lives in plain files in your **Journal** folder:
```
Journal/
├── entries/
│   └── YYYY/
│       └── MM/
│           └── YYYY-MM-DD-HHmmss.md        <-- Plain text with frontmatter
└── media/
    └── YYYY/
        └── MM/
            └── <uuid>.jpg                  <-- 256x256 square — the stored photo
```

Each entry is a plain Markdown file with human-readable frontmatter. Photos are stored locally alongside them. You can read, edit, or back up your journal using TextEdit, Finder, or any tool of your choice.

Photos are centre-cropped to a 1:1 square, scaled to 256×256 and re-encoded as JPEG on the way in. **That square is the only copy Journal keeps** — the file you picked is not stored alongside it, and the crop cannot be undone, so keep your originals in Photos or wherever you already keep them. What it buys is size: a full year of daily photographs comes to tens of megabytes rather than several gigabytes, which is what makes syncing an entire journal over iCloud Drive practical.

---

## Project Structure

This monorepo contains:

- **[`mac/`](mac/)**: The macOS desktop app (Electron, Vanilla JS, custom C++ `whisper.cpp` engine running on Metal GPU).
- **[`ios/`](ios/)**: The companion iPhone app (Native SwiftUI, on-device neural dictation engine, security-scoped bookmark storage).
- **[`docs/`](docs/)**: In-depth system design, Metal GPU compute pipeline, and developer runbooks ([`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md)).

---

[What's changed](CHANGELOG.md) · [System Design & Architecture](docs/DEVELOPMENT.md) · [License](LICENSE)
