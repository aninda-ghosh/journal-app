# Development

How Journal is put together, and how to work on it.

## How it works

```
src/main.js            window, menu, journal folder, IPC, dictation session
src/preload.js         the only bridge to the interface
src/journal.js         reading and writing your files — no Electron, no HTTP
src/renderer/          the interface: HTML, CSS, one script, an audio worklet
native/transcriber.cpp streams audio in, words out; links whisper.cpp statically
```

The interface has no filesystem access and no Node. It asks `preload.js`, which
asks the main process, which touches disk. Photos reach the window through a
custom `journal://` scheme that refuses any path outside the media folder, and
the page runs under a `default-src 'none'` content policy.

Dictation streams 16 kHz mono PCM into the C++ helper on stdin and reads JSON
lines back — `ready`, `partial`, `final`. Audio passes through memory to the
recogniser and is never written anywhere.

Whisper transcribes windows of audio rather than word by word, so "live" means
the tail of what you've said is re-transcribed every couple of seconds and the
guess settles. Audio older than twenty seconds is committed and never revisited,
cut at the quietest moment nearby, which keeps every pass short however long the
recording runs.

## Building from source

The speech engine is a submodule, so clone recursively — and if you forget,
`make.command` fills it in rather than failing:

```bash
git clone --recursive <repo>
cd journal
./make.command
```

Needs [Node.js](https://nodejs.org) and, for dictation, `cmake`
(`brew install cmake` — it is not part of the Xcode command line tools). The
first build compiles whisper.cpp and downloads a ~180MB speech model, so it
takes a while once and is quick afterwards. The finished `.dmg` lands in
`dist/`.

### Commands

```bash
./make.command             build, then run every check
./make.command build       just produce the dmg
./make.command test        the app's checks
./make.command dictation   prove Whisper really transcribes
./make.command engine      build the speech engine, fetch the model
./make.command clean       throw away build output and start fresh
```

Exits non-zero on failure, so it drops into CI unchanged. `clean` only removes
what it can rebuild and never touches your journal.

whisper.cpp is a submodule pinned to a specific commit, linked statically, so
the app ships one self-contained binary with no dylibs to find at runtime. To
move to a newer upstream version, check out the commit you want inside
`native/whisper.cpp`, run the checks, and commit the new pointer.

Built for `--arm64`; change to `--x64` in the `dist` script for Intel.

## Cutting a release

```bash
./make.command                      # build and verify
npm version patch|minor|major       # bump package.json and tag
git push && git push --tags
```

Then create the GitHub release for that tag and attach `dist/*.dmg`. The
README's download link points at `releases/latest`, so it follows along on its
own. Add the changes to `CHANGELOG.md` under a new version heading before
tagging.

<details>
<summary>Underlying npm scripts</summary>

```bash
npm install
npm start                 # run from source
npm test                  # the end-to-end checks
npm run check-dictation   # prove Whisper transcribes
npm run icon              # redraw build/icon.icns
npm run native            # rebuild just the speech engine
npm run dist              # package the dmg
```
</details>

## Testing

`npm test` boots the real app and drives it over the DevTools protocol,
asserting against actual files on disk — 45 checks covering the preload bridge,
Node isolation, storage, the photo pipeline, the calendar, and dictation.

Dictation is exercised with Chromium's fake microphone and a stub transcriber
that describes the audio it's fed rather than inventing a transcript, so a wrong
sample rate or a silent stream fails loudly rather than passing quietly. The
tests also assert that words appear *during* recording, not only after it.

On macOS a window appears for the minute the run takes — that's the real app
being driven. On Linux the checks borrow a virtual display and need `xvfb`.

The one thing `npm test` can't cover is Whisper's own accuracy, which needs the
real model and Apple Silicon. `./make.command dictation` streams a known
recording through the engine and checks recognisable words come back.

## Things that will bite you

Each of these cost real time at least once.

**Platform**

- `xvfb-run` is Linux-only. Hardcoding it makes the suite die instantly on
  macOS — the platform this app is for.
- macOS resolves `getPath('documents')` from the real account, ignoring a `HOME`
  override, so a test run can write into a real journal. The tests pin the
  folder with `JOURNAL_ROOT`.
- CMake's generator decides whether the built binary lands in `build/` or
  `build/Release/`. `make.command` normalises it.

**Electron**

- `journal://` is registered as a *standard* scheme, so `journal://media/x.jpg`
  parses `media` as the **host**. The handler must join `url.host +
  url.pathname` to recover the path. Getting this wrong silently breaks every
  image.
- Reading pixels from a `journal://` image taints the canvas. Test the cropping
  function on a `blob:` URL rather than loosening the protocol for a test.
- `fetch()` is blocked by the page's content policy; build test images with
  `canvas.toBlob`.
- `session` is an Electron import — don't shadow it with a local variable.
- A leftover Electron process holds the debug port and the test will silently
  attach to the *stale* build. The test kills that port first.

**Dictation**

- The helper emits `ready` *before* loading the model, with the reader thread
  already buffering. Loading 190MB first meant every press of Dictate waited on
  "Starting…".
- Let CMake work out the link line via `add_subdirectory(whisper.cpp)`.
  Hand-rolled `g++` flags fail on missing OpenMP symbols on Linux and would need
  different flags again on macOS.

**Repo**

- The speech model is deliberately not in the repository. At 182MB it is past
  GitHub's hard 100MB limit for ordinary files, and git would keep every version
  of it forever. `make.command` downloads it once, on the first build.
- Verify ignore rules with `git check-ignore -v <path>` rather than trusting a
  comment: one once claimed to exclude the model while the matching line was
  missing, and `git add -A` was about to commit it into history.

**Bash**

- An apostrophe inside `${var:-default}` opens a quoted string *even within
  double quotes*, and bash reports the error at end of file, far from the cause.
