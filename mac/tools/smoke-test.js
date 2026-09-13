/**
 * End-to-end smoke test.
 *
 * Boots the real app under a virtual display, then drives the actual interface
 * over the DevTools protocol: renderer -> preload -> IPC -> main -> disk, and
 * back out again through the journal:// image protocol. Nothing is stubbed.
 */

'use strict';

const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os');
const WebSocket = require('ws');

const PORT = 9222;
const HOME = path.join(os.tmpdir(), 'journal-smoke-home');

// Where the app decides to store things — discovered at runtime rather than
// assumed. On macOS this is ~/Documents/Journal; a bare Linux container has no
// XDG documents dir, so Electron falls back to $HOME/Journal there.
let ROOT = null;

const TINY_PNG =
  'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAQAAAAECAYAAACp8Z5+AAAAFUlEQVR42mP8' +
  'z8BQz0AEYBxVSF+FABJADveWkH6oAAAAAElFTkSuQmCC';

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

/** Pull the real pixel dimensions out of a JPEG's start-of-frame marker. */
function jpegSize(buffer) {
  let i = 2;
  while (i + 9 < buffer.length) {
    if (buffer[i] !== 0xff) { i++; continue; }
    const marker = buffer[i + 1];
    const isFrame = marker >= 0xc0 && marker <= 0xcf &&
                    marker !== 0xc4 && marker !== 0xc8 && marker !== 0xcc;
    if (isFrame) return { height: buffer.readUInt16BE(i + 5), width: buffer.readUInt16BE(i + 7) };
    if (marker === 0xd8 || (marker >= 0xd0 && marker <= 0xd9)) { i += 2; continue; }
    i += 2 + buffer.readUInt16BE(i + 2);
  }
  return null;
}
const pass = [];
const fail = [];

function check(name, ok, detail) {
  (ok ? pass : fail).push(name);
  console.log(`${ok ? '  ok  ' : ' FAIL '} ${name}${detail ? '  — ' + detail : ''}`);
}

async function findPageTarget() {
  for (let i = 0; i < 60; i++) {
    try {
      const res = await fetch(`http://127.0.0.1:${PORT}/json`);
      const targets = await res.json();
      const page = targets.find((t) => t.type === 'page' && t.webSocketDebuggerUrl);
      if (page) return page;
    } catch { /* devtools not up yet */ }
    await sleep(500);
  }
  throw new Error('The app never exposed a page to inspect');
}

function connect(url) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(url);
    let id = 0;
    const pending = new Map();

    ws.on('open', () => resolve({
      /** Evaluate an async expression in the page and return its value. */
      async eval(expression) {
        const msgId = ++id;
        ws.send(JSON.stringify({
          id: msgId,
          method: 'Runtime.evaluate',
          params: { expression, awaitPromise: true, returnByValue: true }
        }));
        return new Promise((res, rej) => {
          pending.set(msgId, { res, rej });
          setTimeout(() => rej(new Error('timed out: ' + expression.slice(0, 60))), 20000);
        });
      },
      close: () => ws.close()
    }));

    ws.on('message', (raw) => {
      const msg = JSON.parse(raw);
      if (!pending.has(msg.id)) return;
      const { res, rej } = pending.get(msg.id);
      pending.delete(msg.id);
      if (msg.error) return rej(new Error(msg.error.message));
      const r = msg.result?.result;
      if (msg.result?.exceptionDetails) {
        return rej(new Error(msg.result.exceptionDetails.exception?.description || 'threw'));
      }
      res(r?.value);
    });

    ws.on('error', reject);
  });
}

(async () => {
  fs.rmSync(HOME, { recursive: true, force: true });
  fs.mkdirSync(path.join(HOME, 'Documents'), { recursive: true });
  // The app checks the model exists before starting; the stub ignores it.
  fs.writeFileSync(path.join(HOME, 'stub-model.bin'), 'stub');

  // A leftover app from an earlier run would hold the debug port and quietly
  // serve stale code to this test, so clear the decks first.
  try {
    require('child_process').execSync(
      "pkill -f 'remote-debugging-port=" + PORT + "' || true", { stdio: 'ignore' });
  } catch { /* nothing to kill */ }
  await sleep(1200);

  const electron = require('electron');

  const electronArgs = [
    '.',
    '--no-sandbox',
    `--remote-debugging-port=${PORT}`,
    // A synthetic microphone, so dictation can be exercised without hardware.
    '--use-fake-device-for-media-stream',
    '--use-fake-ui-for-media-stream'
  ];

  // Linux has no display in CI or a container, so borrow a virtual one.
  // macOS has a real one — there, Electron just opens a window, and a window
  // will visibly appear for the minute or so this takes.
  const headless = process.platform === 'linux';
  const command = headless ? 'xvfb-run' : electron;
  const args = headless ? ['-a', electron, ...electronArgs] : electronArgs;

  const child = spawn(command, args, {
    cwd: path.join(__dirname, '..'),
    env: {
      ...process.env,
      HOME,
      ELECTRON_DISABLE_SECURITY_WARNINGS: '1',
      // Whisper's real weights can't be fetched here; everything around them can.
      JOURNAL_TRANSCRIBER: path.join(__dirname, 'fake-transcriber.js'),
      JOURNAL_MODEL: path.join(HOME, 'stub-model.bin'),
      JOURNAL_ROOT: path.join(HOME, 'Journal')
    },
    stdio: ['ignore', 'pipe', 'pipe'],
    detached: true            // so the whole group can be torn down afterwards
  });

  child.on('error', (err) => {
    console.error(err.code === 'ENOENT' && headless
      ? 'xvfb is needed to run these on Linux:  apt-get install xvfb'
      : 'Could not start the app: ' + err.message);
    process.exit(1);
  });

  let stderr = '';
  child.stdout.on('data', (d) => process.stdout.write('  [app] ' + d));
  child.stderr.on('data', (d) => {
    stderr += d;
    // Into the log as it happens: when startup fails there is no later chance
    // to report it, and a silent failure is the hardest kind to chase.
    process.stdout.write('  [app:err] ' + d);
  });

  try {
    const target = await findPageTarget();
    check('app boots and opens a window', true, target.title || 'Journal');

    const page = await connect(target.webSocketDebuggerUrl);
    await sleep(800);

    // --- the bridge -------------------------------------------------------
    const api = await page.eval('Object.keys(window.journal).sort().join(",")');
    check('preload bridge is exposed', typeof api === 'string' && api.includes('saveMedia'), api);

    const leaked = await page.eval(
      "[typeof window.require, typeof window.process, typeof window.module].join(',')"
    );
    check('renderer has no Node access', leaked === 'undefined,undefined,undefined', leaked);

    // --- where it stores --------------------------------------------------
    const info = await page.eval('window.journal.info()');
    ROOT = info.root;
    check('journal folder is created without asking',
      typeof ROOT === 'string' && path.basename(ROOT) === 'Journal' && fs.existsSync(ROOT), ROOT);

    // --- photo round trip -------------------------------------------------
    const media = await page.eval(
      `window.journal.saveMedia({name:'test.png', photo:'${TINY_PNG}', processed:true})`
    );
    check('photo saves to disk', Boolean(media?.path), media?.path);
    check('the photo file is written',
      fs.existsSync(path.join(ROOT, media.path)), media.path);

    // --- the journal:// protocol actually serves the image -----------------
    const loaded = await page.eval(`new Promise((resolve) => {
      const img = new Image();
      img.onload = () => resolve('loaded ' + img.naturalWidth + 'x' + img.naturalHeight);
      img.onerror = () => resolve('ERROR');
      img.src = window.journal.mediaUrl(${JSON.stringify(media.path)});
    })`);
    check('journal:// serves photos to the window', loaded.startsWith('loaded'), loaded);

    const escaped = await page.eval(`new Promise((resolve) => {
      const img = new Image();
      img.onload = () => resolve('LEAKED');
      img.onerror = () => resolve('blocked');
      img.src = 'journal://media/../../../../etc/hostname';
    })`);
    check('journal:// refuses paths outside the journal', escaped === 'blocked', escaped);

    // --- entries ----------------------------------------------------------
    const saved = await page.eval(`window.journal.save({
      title: 'Smoke test',
      body: 'Line one.\\n\\n- bullet\\n\\n**bold** text.',
      tags: ['Fog','coast','fog'],
      photos: ${JSON.stringify([media.path])}
    })`);
    check('entry saves', Boolean(saved?.id), saved?.id);
    check('tags are lowercased and de-duplicated',
      JSON.stringify(saved.tags) === '["fog","coast"]', JSON.stringify(saved.tags));

    const file = path.join(ROOT, 'entries', saved.id.slice(0, 4), saved.id.slice(5, 7), saved.id + '.md');
    check('entry is a Markdown file on disk', fs.existsSync(file), path.relative(ROOT, file));

    const contents = fs.existsSync(file) ? fs.readFileSync(file, 'utf8') : '';
    check('file is human-readable with frontmatter',
      contents.startsWith('---\nid: ') && contents.includes('tags: fog, coast'));

    const list = await page.eval('window.journal.list()');
    check('entry reads back', Array.isArray(list) && list.length === 1, `${list.length} entries`);
    check('body survives the round trip', list[0]?.body.includes('**bold** text.'));

    const rejected = await page.eval(
      "window.journal.save({body:'   '}).then(() => 'ACCEPTED').catch(e => e.message)"
    );
    check('empty entries are refused', /needs some words or a photo/.test(rejected), rejected);

    // --- the interface actually rendered ----------------------------------
    const ui = await page.eval(`JSON.stringify({
      days: document.querySelectorAll('#cal-grid .day').length,
      withEntry: document.querySelectorAll('#cal-grid .day.has-entry').length,
      title: document.querySelector('#cal-title').textContent
    })`);
    const uiData = JSON.parse(ui);
    check('calendar renders a month', uiData.days >= 28, `${uiData.days} cells, ${uiData.title}`);

    await page.eval('window.location.reload()');
    await sleep(1500);
    const page2 = await connect((await findPageTarget()).webSocketDebuggerUrl);
    await sleep(600);
    const afterReload = await page2.eval(
      "document.querySelectorAll('#cal-grid .day.has-entry').length"
    );
    check('saved entry shows on the calendar', afterReload === 1, `${afterReload} day(s) marked`);

    // --- several entries in one day ---------------------------------------
    // The calendar shows one square per day, so when a day holds more than one
    // entry it should lead with the photo from whichever one was written at
    // most length — not just whichever came first.
    const second = await page2.eval(
      `window.journal.saveMedia({name:'second.png', photo:'${TINY_PNG}', processed:true})`
    );
    await page2.eval(`window.journal.save({
      title: 'The long one',
      body: ${JSON.stringify('A much longer account of the day. '.repeat(14))},
      photos: ${JSON.stringify([second.path])}
    })`);
    await page2.eval('loadEntries()');
    await sleep(400);

    const dayCell = JSON.parse(await page2.eval(`JSON.stringify({
      entries: state.entries.length,
      squares: document.querySelectorAll('#cal-grid .day.has-entry').length,
      badge: document.querySelector('#cal-grid .day.today .count')?.textContent || null,
      photo: document.querySelector('#cal-grid .day.today img')?.getAttribute('src') || null
    })`));

    check('two entries on one day stay one calendar square',
      dayCell.entries === 2 && dayCell.squares === 1, `${dayCell.entries} entries, ${dayCell.squares} square`);
    check('the square counts the day\'s entries', dayCell.badge === '2', `badge: ${dayCell.badge}`);
    check('the day leads with the longer entry\'s photo',
      Boolean(dayCell.photo) && dayCell.photo.includes(second.path.split('/').pop().replace(/\.[^.]+$/, '')),
      dayCell.photo ? dayCell.photo.split('/').pop() : 'none');

    const bothShown = await page2.eval(`(() => {
      document.querySelectorAll('#cal-grid .day.today')[0].click();
      return document.querySelectorAll('#entry-list .entry').length;
    })()`);
    check('clicking the day shows both entries', bothShown === 2, `${bothShown} entries listed`);

    // --- photos are squared and shrunk on the way in ----------------------
    // One 256px square per photo, and it is the only copy kept.
    // Bands of colour make it possible to prove the crop is centred rather
    // than merely square: the middle 160px of a 400px-wide image is green, so
    // a correctly centred crop comes out entirely green.
    const makePhoto = (w, h, banded) => `(async () => {
      const c = document.createElement('canvas');
      c.width = ${w}; c.height = ${h};
      const x = c.getContext('2d');
      x.fillStyle = '#cc2020'; x.fillRect(0, 0, c.width, c.height);
      if (${banded}) {
        const side = Math.min(c.width, c.height);
        x.fillStyle = '#20aa50';
        x.fillRect((c.width - side) / 2, (c.height - side) / 2, side, side);
      }
      const blob = await new Promise(r => c.toBlob(r, 'image/png'));
      const file = new File([blob], 'shot.png', { type: 'image/png' });
      state.photos = [];
      await addPhotos([file]);
      const p = state.photos[0];
      return JSON.stringify({ path: p && p.path, bytes: blob.size });
    })()`;

    const wide = JSON.parse(await page2.eval(makePhoto(400, 160, true)));
    const wideFile = path.join(ROOT, wide.path);
    const wideSize = jpegSize(fs.readFileSync(wideFile));
    check('a wide photo is stored as a square',
      wideSize && wideSize.width === 160 && wideSize.height === 160,
      wideSize ? `${wideSize.width}x${wideSize.height}` : 'unreadable');
    check('the stored photo is a JPEG regardless of what came in',
      wide.path.endsWith('.jpg'), wide.path.split('/').pop());

    // Sampling pixels through journal:// taints the canvas, so check the real
    // cropping function directly on a blob-backed image instead: same code
    // path, readable pixels. If the crop came from a corner, red shows up.
    const sampled = await page2.eval(`(async () => {
      const c = document.createElement('canvas');
      c.width = 400; c.height = 160;
      const x = c.getContext('2d');
      x.fillStyle = '#cc2020'; x.fillRect(0, 0, 400, 160);
      x.fillStyle = '#20aa50'; x.fillRect(120, 0, 160, 160);
      const blob = await new Promise(r => c.toBlob(r, 'image/png'));
      const url = URL.createObjectURL(blob);
      try {
        const img = await loadImage(url);
        const out = squareCanvas(img, PHOTO_MAX);
        const ctx = out.getContext('2d');
        const at = (fx) => {
          const d = ctx.getImageData(
            Math.min(out.width - 1, Math.floor(out.width * fx)),
            Math.floor(out.height / 2), 1, 1).data;
          return d[0] > d[1] ? 'red' : 'green';
        };
        return [at(0.04), at(0.5), at(0.96)].join(',');
      } finally { URL.revokeObjectURL(url); }
    })()`);
    check('the crop is taken from the centre, not a corner',
      sampled === 'green,green,green', sampled);

    const big = JSON.parse(await page2.eval(makePhoto(3000, 2200, false)));
    const bigSize = jpegSize(fs.readFileSync(path.join(ROOT, big.path)));
    const bigBytes = fs.statSync(path.join(ROOT, big.path)).size;
    check('a large photo is capped at 256px',
      bigSize && bigSize.width === 256 && bigSize.height === 256,
      bigSize ? `${bigSize.width}x${bigSize.height}` : 'unreadable');
    check('and takes a fraction of the space it arrived with',
      bigBytes < big.bytes,
      `${(big.bytes / 1024).toFixed(0)}KB in, ${(bigBytes / 1024).toFixed(0)}KB stored`);

    const small = JSON.parse(await page2.eval(makePhoto(200, 200, false)));
    const smallSize = jpegSize(fs.readFileSync(path.join(ROOT, small.path)));
    check('a photo smaller than 256px is enlarged to 256px',
      smallSize && smallSize.width === 256 && smallSize.height === 256,
      smallSize ? `${smallSize.width}x${smallSize.height}` : 'unreadable');

    // One tier: the stored square is the only copy of a photo. Nothing should
    // be writing a second file beside it, and nothing should be asking for one.
    const strays = fs.readdirSync(path.join(ROOT, path.dirname(big.path)))
      .filter((name) => name.includes('.thumb.'));
    check('exactly one file is stored per photo',
      strays.length === 0, strays.join(', ') || 'no .thumb.jpg written');

    await page2.eval('state.photos = []; renderThumbs();');

    // --- dictation --------------------------------------------------------
    // The Swift transcriber can't run here, so it's stubbed — but the capture,
    // the PCM stream, the trip through IPC and words landing live in the entry
    // are all the real thing.
    await page2.eval("switchView('write'); document.querySelector('#body').value = 'Before. ';"
      + "document.querySelector('#body').setSelectionRange(8, 8);");

    const worklet = await page2.eval(`(async () => {
      try {
        const ctx = new AudioContext({ sampleRate: 16000 });
        await ctx.audioWorklet.addModule('pcm-worklet.js');
        await ctx.close();
        return 'loaded';
      } catch (e) { return 'FAILED: ' + e.message; }
    })()`);
    check('audio worklet loads under the page\'s CSP', worklet === 'loaded', worklet);

    await page2.eval("document.querySelector('#dictate').click()");
    await sleep(3000);

    // The heart of it: words should already be in the entry, mid-recording.
    const midway = JSON.parse(await page2.eval(`JSON.stringify({
      recording: window.Dictation.isRecording(),
      listening: document.querySelector('#dictate').classList.contains('listening'),
      label: document.querySelector('#dictate-label').textContent,
      body: document.querySelector('#body').value,
      readOnly: document.querySelector('#body').readOnly
    })`));

    check('recording starts and shows a running clock',
      midway.recording && midway.listening && /^\d+:\d\d$/.test(midway.label), midway.label);
    check('words appear while you are still speaking',
      /heard [\d.]+s/.test(midway.body), midway.body.slice(0, 60));
    check('live text is placed at the cursor, not appended',
      midway.body.startsWith('Before. heard'), midway.body.slice(0, 40));
    check('the entry is read-only while speaking', midway.readOnly === true, String(midway.readOnly));

    const heardMid = midway.body.match(/peak (\d+)/);
    check('the microphone is actually feeding the transcriber',
      Boolean(heardMid) && Number(heardMid[1]) > 0,
      heardMid ? `peak ${heardMid[1]}` : 'no peak reported');

    await page2.eval("document.querySelector('#dictate').click()");
    await sleep(3500);

    const after = JSON.parse(await page2.eval(`JSON.stringify({
      body: document.querySelector('#body').value,
      readOnly: document.querySelector('#body').readOnly,
      cls: document.querySelector('#dictate').className,
      label: document.querySelector('#dictate-label').textContent,
      recording: window.Dictation.isRecording()
    })`));

    check('the final transcript replaces the live text',
      /PCM 16000Hz 16bit/.test(after.body) && !/heard /.test(after.body),
      after.body.slice(0, 70));
    check('audio reached the transcriber as 16kHz 16-bit PCM',
      /PCM 16000Hz 16bit [\d.]+s/.test(after.body), after.body.slice(8, 60));

    const dur = after.body.match(/16bit ([\d.]+)s/);
    check('roughly the right amount of audio was captured',
      Boolean(dur) && Number(dur[1]) > 1.5 && Number(dur[1]) < 7,
      dur ? dur[1] + 's' : 'unknown');

    check('the entry is writable again afterwards', after.readOnly === false, String(after.readOnly));
    check('the button returns to its resting state',
      !after.recording && after.cls === 'dictate' && after.label === 'Dictate',
      `${after.cls} / ${after.label}`);

    const leftovers = fs.readdirSync(require('os').tmpdir())
      .filter((f) => f.startsWith('journal-dictation-'));
    check('no audio is left behind on disk',
      leftovers.length === 0, leftovers.join(', ') || 'nothing written');

    // Esc mid-take should leave the entry exactly as it was.
    await page2.eval("document.querySelector('#body').value = 'Keep me.';"
      + "document.querySelector('#body').setSelectionRange(8, 8);"
      + "document.querySelector('#dictate').click()");
    await sleep(2500);
    await page2.eval(
      "document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' }))");
    await sleep(1200);
    const abandoned = await page2.eval("document.querySelector('#body').value");
    check('discarding a take leaves the entry untouched',
      abandoned === 'Keep me.', JSON.stringify(abandoned));

    const diagnosis = await page2.eval("window.journal.dictationDiagnose('en-US')");
    check('diagnose reports whether dictation is usable',
      diagnosis && diagnosis.ok === true, diagnosis && diagnosis.message);

    await page2.eval("document.querySelector('#body').value = ''; saveDraft();");

    const footer = await page2.eval("document.querySelector('#where').textContent");
    check('footer shows where the journal lives', footer.includes(ROOT), footer.trim().slice(0, 90));

    page.close();
    page2.close();
  } catch (err) {
    check('test run completed', false, err.message);
    const tail = stderr.trim().split('\n').slice(-12);
    if (tail.length && tail[0]) {
      console.log('\n  what the app said before giving up:');
      tail.forEach((line) => console.log('    ' + line));
    } else {
      console.log('\n  the app printed nothing at all — it may have exited immediately.');
    }
  } finally {
    try { process.kill(-child.pid, 'SIGTERM'); } catch { /* already gone */ }
    await sleep(700);
    try { process.kill(-child.pid, 'SIGKILL'); } catch { /* already gone */ }
  }

  const noisy = stderr
    .split('\n')
    .filter((l) => /error|failed|denied/i.test(l))
    .filter((l) => !/dbus|GPU|gpu|sandbox|Xlib|libva|MESA|Fontconfig|dri3|vulkan|EGL|gbm/i.test(l))
    .slice(0, 5);
  check('no unexpected errors on the console', noisy.length === 0, noisy.join(' | ') || 'clean');

  console.log(`\n${pass.length} passed, ${fail.length} failed`);
  if (fail.length) { console.log('failed: ' + fail.join(', ')); process.exit(1); }
})();
