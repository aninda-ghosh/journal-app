# The Journal file format

This is the contract between the Mac app and the iPhone app. Both implement it
independently — `mac/src/journal.js` and `ios/Journal/Models/Entry.swift` — and
the only thing keeping them honest is `spec/fixtures/`, which both test suites
read. **If you change anything here, change a fixture too.**

Everything a journal contains is plain text and ordinary image files. Nothing
about the format requires either app to read it.

---

## Layout

```
Journal/
├── entries/
│   └── YYYY/
│       └── MM/
│           └── YYYY-MM-DD-HHmmss.md
└── media/
    └── YYYY/
        └── MM/
            └── <id>.jpg
```

The year and month folders come from the entry's id, not from the file's
modification time. `media/` is organised by the date the photo was *added*.

## An entry file

```
---
id: 2026-09-08-143000
date: 2026-09-08T14:30:00
title: Morning walk in Presidio
tags: nature, walking, fog
photos: media/2026/09/a.jpg, media/2026/09/b.jpg
---

The fog didn't lift until noon.
Walked along the battery ridge.
```

Deliberately not YAML. Flat `key: value` lines, lists comma-separated, so it
stays readable by hand and needs no parser library on either platform.

### Fields

| Key | Meaning |
|---|---|
| `id` | `YYYY-MM-DD-HHmmss`. Sorts correctly as a plain string; also gives the file its name and its folder. |
| `date` | Local time, `YYYY-MM-DDTHH:MM:SS`. No timezone offset and no conversion: a journal entry belongs to the day it felt like, not to UTC. |
| `title` | Free text on one line. May contain colons. |
| `tags` | Comma-separated, lowercase, de-duplicated, order preserved. A tag cannot contain a comma. |
| `photos` | Comma-separated journal-relative paths. Every one must start with `media/`. |

### Reading

- A file that does not begin with `---\n` is all body.
- Frontmatter ends at the first `\n---` after the opening line. Anything after
  that is body, including further `---` lines.
- On each frontmatter line, the **first** colon separates key from value; the
  rest of the line is the value, so `title: 10:30: the meeting` works.
- Whitespace around keys and values is trimmed. Empty list items are dropped.
- Unknown keys are ignored. **They are also not preserved on rewrite** — see
  Known gaps below.
- CRLF is normalised to LF. The body is trimmed of leading blank lines and
  trailing whitespace.
- A missing `date:` means the entry has no date. The caller derives one from the
  id (`readAll` uses midnight on the id's day); parsing must not invent one.
- `date` is also accepted with a space instead of `T`. Builds of the iPhone app
  before 2.0.1 wrote that form. Nothing writes it now, and readers must keep
  accepting it for as long as those files exist.

### Writing

- Always `T`, never a space.
- Always all five keys, even when empty (`tags: ` with nothing after it).
- One blank line between the closing `---` and the body; one trailing newline.
- An entry needs a body or at least one photo. A title alone is not an entry.
- Saving an entry that already has a valid id keeps that id, and keeps its
  `date` — editing an entry must never restamp it.
- A new entry's id comes from the current time, taken at the moment of saving.
  Not from when the composer was opened: two entries written one after the other
  must not collide, because a collision silently overwrites.

## Photos

One file per photo: a centre-cropped square, 256×256, JPEG at 0.82
quality (images with lower dimension < 256 are enlarged to 256; larger images
are downscaled). **It is the only copy** — the original is never stored, and the crop
cannot be undone. When the platform cannot decode a file at all, it is stored
byte-for-byte as it arrived instead, keeping its original extension; that is the
one case where a stored photo is not a 256px square.

There is no thumbnail tier. Journals written before 2.0.1 may contain
`<id>.thumb.jpg` files; nothing references them and they are safe to delete.

Deleting an entry never deletes its photos.

## Checking an implementation

```bash
# Mac
node mac/tools/format-conformance.js

# iPhone (from the repository root)
xcrun swiftc -parse-as-library ios/Tests/VerifyFormat.swift \
  ios/Journal/Models/Entry.swift -o .cache/verify_format && .cache/verify_format
```

Each fixture in `spec/fixtures/` is one `.md` file plus the parse it must
produce, using `2026-09-08-143000` as the fallback id. Both runners also check
that parsing, serialising and parsing again changes nothing.

## Known gaps

- **Unknown keys are dropped on rewrite.** An older client that opens and saves
  an entry written by a newer one will strip any key it doesn't recognise. If
  the format ever grows a field, this needs fixing first — preserve unknown
  lines and write them back.
- **No version field.** Everything in the wild is version 1 by assumption.
- **No escaping.** A newline in a title is replaced with a space on write; there
  is no way to represent a comma inside a tag.
