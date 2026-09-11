# Changelog

All notable changes to Journal are recorded here.

Version numbers read left to right: the first changes only if you'd have to do
something differently, the second when something new is added, and the third
when something is fixed.

## Unreleased

Nothing yet.

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
