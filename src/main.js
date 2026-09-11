/**
 * Journal — main process.
 *
 * Owns the window, the menu, and the journal folder. Nothing here listens on a
 * network port; the interface talks to the filesystem over IPC, so the app is
 * genuinely offline rather than merely private.
 */

'use strict';

const { app, BrowserWindow, Menu, dialog, ipcMain, shell, protocol, net, nativeTheme,
        systemPreferences, session } = require('electron');
const fs = require('fs');
const fsp = fs.promises;
const path = require('path');
const os = require('os');
const crypto = require('crypto');
const { execFile, spawn } = require('child_process');
const { pathToFileURL } = require('url');

const journal = require('./journal');

const IS_MAC = process.platform === 'darwin';

let win = null;
let config = { root: null, window: null };

// ------------------------------------------------------------------ config

function configPath() {
  return path.join(app.getPath('userData'), 'config.json');
}

async function loadConfig() {
  try {
    config = { ...config, ...JSON.parse(await fsp.readFile(configPath(), 'utf8')) };
  } catch { /* first run, or a config we can't read — defaults are fine */ }
}

async function saveConfig() {
  try {
    await fsp.mkdir(path.dirname(configPath()), { recursive: true });
    await fsp.writeFile(configPath(), JSON.stringify(config, null, 2), 'utf8');
  } catch (err) {
    console.error('Could not save settings:', err.message);
  }
}

/**
 * Where the writing lives. Defaults to ~/Documents/Journal without asking —
 * you can move it later from the Journal menu. If a previously chosen folder
 * has vanished, fall back to the default rather than refusing to start.
 */
async function resolveRoot() {
  // Tests pin this explicitly. macOS resolves "documents" from the real account
  // rather than $HOME, so without an override a test run would happily write
  // into someone's actual journal.
  if (process.env.JOURNAL_ROOT) {
    const pinned = path.resolve(process.env.JOURNAL_ROOT);
    journal.setRoot(pinned);
    await journal.ensureDirs();
    return pinned;
  }

  let root = config.root;

  if (root) {
    try {
      const stat = await fsp.stat(root);
      if (!stat.isDirectory()) root = null;
    } catch { root = null; }
  }

  if (!root) {
    root = path.join(app.getPath('documents'), 'Journal');
    config.root = root;
    await saveConfig();
  }

  journal.setRoot(root);
  await journal.ensureDirs();
  return root;
}

// ---------------------------------------------------------------- protocol

/**
 * Photos are served over a `journal://` scheme rather than file://, so the
 * renderer can only ever reach files inside the journal's media folder.
 */
function registerProtocol() {
  protocol.handle('journal', (request) => {
    // This is a *standard* scheme, so journal://media/2026/09/x.jpg parses
    // "media" as the host and "/2026/09/x.jpg" as the path. Glue them back
    // together to recover the stored relative path.
    const url = new URL(request.url);
    const rel = decodeURIComponent(url.host + url.pathname).replace(/^\/+/, '');
    const file = journal.resolveMedia(rel);
    if (!file) return new Response('Not found', { status: 404 });
    return net.fetch(pathToFileURL(file).toString());
  });
}

// ------------------------------------------------------------------ window

function createWindow() {
  const saved = config.window || {};

  win = new BrowserWindow({
    width: saved.width || 1080,
    height: saved.height || 760,
    x: saved.x,
    y: saved.y,
    minWidth: 620,
    minHeight: 520,
    show: false,
    title: 'Journal',
    titleBarStyle: IS_MAC ? 'hiddenInset' : 'default',
    backgroundColor: nativeTheme.shouldUseDarkColors ? '#17161a' : '#faf8f5',
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      spellcheck: true
    }
  });

  win.loadFile(path.join(__dirname, 'renderer', 'index.html'));
  win.once('ready-to-show', () => win.show());

  const remember = () => {
    if (!win || win.isDestroyed() || win.isMinimized() || win.isFullScreen()) return;
    const [width, height] = win.getSize();
    const [x, y] = win.getPosition();
    config.window = { width, height, x, y };
    saveConfig();
  };
  win.on('resized', remember);
  win.on('moved', remember);
  win.on('closed', () => { win = null; });

  // Links to the outside world open in the real browser, not in the journal.
  win.webContents.setWindowOpenHandler(({ url }) => {
    if (/^https?:\/\//.test(url)) shell.openExternal(url);
    return { action: 'deny' };
  });
  win.webContents.on('will-navigate', (event, url) => {
    if (!url.startsWith('file://')) {
      event.preventDefault();
      if (/^https?:\/\//.test(url)) shell.openExternal(url);
    }
  });

  nativeTheme.on('updated', () => {
    if (win && !win.isDestroyed()) {
      win.setBackgroundColor(nativeTheme.shouldUseDarkColors ? '#17161a' : '#faf8f5');
    }
  });
}

function toRenderer(channel, payload) {
  if (win && !win.isDestroyed()) win.webContents.send(channel, payload);
}

// -------------------------------------------------------------- moving the
// journal folder

async function chooseFolder() {
  const result = await dialog.showOpenDialog(win, {
    title: 'Choose where your journal lives',
    message: 'Pick a folder. Journal will keep your writing and photos in a folder called Journal inside it.',
    properties: ['openDirectory', 'createDirectory'],
    buttonLabel: 'Use This Folder'
  });
  if (result.canceled || !result.filePaths.length) return null;

  const picked = result.filePaths[0];
  const target = path.basename(picked) === 'Journal' ? picked : path.join(picked, 'Journal');
  const current = journal.getRoot();

  if (path.resolve(target) === path.resolve(current)) return current;

  try {
    const targetExists = fs.existsSync(target);

    if (targetExists && fs.readdirSync(target).length > 0) {
      // There's already a journal there — adopt it rather than overwrite.
      const { response } = await dialog.showMessageBox(win, {
        type: 'question',
        buttons: ['Use That Journal', 'Cancel'],
        defaultId: 0,
        cancelId: 1,
        message: 'There\'s already a journal in that folder.',
        detail: `Journal can switch to using:\n${target}\n\nYour current journal stays exactly where it is — nothing is deleted or merged.`
      });
      if (response !== 0) return null;
    } else {
      // Move the existing journal over, so nothing is left behind.
      await fsp.mkdir(path.dirname(target), { recursive: true });
      try {
        await fsp.rename(current, target);
      } catch (err) {
        if (err.code !== 'EXDEV') throw err;
        // Different volume — copy, then remove the original.
        await fsp.cp(current, target, { recursive: true });
        await fsp.rm(current, { recursive: true, force: true });
      }
    }

    config.root = target;
    await saveConfig();
    journal.setRoot(target);
    await journal.ensureDirs();
    toRenderer('journal:moved', target);
    return target;
  } catch (err) {
    await dialog.showMessageBox(win, {
      type: 'error',
      message: 'Couldn\'t move your journal.',
      detail: err.message + '\n\nNothing was changed — your writing is still in:\n' + current
    });
    return null;
  }
}

// ------------------------------------------------------------- dictation
//
// Speech becomes text on this Mac, through a small helper that runs Whisper
// locally via whisper.cpp — Metal-accelerated on Apple Silicon. Audio streams
// into it while the writer is talking and words stream back out.
//
// Whisper works on windows of audio rather than word by word, so the tail of
// what you've said is re-transcribed every couple of seconds and the guess
// settles. Nothing is written to disk and nothing leaves the machine.

/** Where the compiled helper lives, packaged or in development. */
function transcriberPath() {
  if (process.env.JOURNAL_TRANSCRIBER) return process.env.JOURNAL_TRANSCRIBER;
  return app.isPackaged
    ? path.join(process.resourcesPath, 'transcriber')
    : path.join(__dirname, '..', 'native', 'build', 'transcriber');
}

/** The Whisper weights. Shipped inside the app, so dictation works offline. */
function modelPath() {
  if (process.env.JOURNAL_MODEL) return process.env.JOURNAL_MODEL;

  const dir = app.isPackaged
    ? path.join(process.resourcesPath, 'models')
    : path.join(__dirname, '..', 'native', 'models');

  try {
    // Whichever ggml model was built in; the size is a build-time choice.
    const found = fs.readdirSync(dir).filter((f) => /^ggml-.*\.bin$/.test(f)).sort();
    if (found.length) return path.join(dir, found[0]);
  } catch { /* no models folder at all */ }

  return path.join(dir, 'ggml-small.en-q5_1.bin');
}

const NOT_BUILT =
  'Dictation isn\'t built into this copy of Journal. Run build.command again — it '
  + 'compiles the speech engine and downloads the model.';

const NO_MODEL =
  'The speech model is missing from this copy of Journal. Run build.command again to '
  + 'download it.';

let dictation = null;

/** Tear down whatever is running, for any reason. */
function endSession(reason) {
  if (!dictation) return;
  const dying = dictation;
  dictation = null;
  clearTimeout(dying.readyTimer);
  clearTimeout(dying.finalTimer);
  if (dying.rejectReady) dying.rejectReady(new Error(reason || 'Dictation stopped.'));
  if (dying.rejectFinal) dying.rejectFinal(new Error(reason || 'Dictation stopped.'));
  try { dying.child.kill('SIGTERM'); } catch { /* already gone */ }
}

/**
 * Start listening. Resolves once the helper says it's ready, which may take a
 * moment the first time because macOS asks the writer for permission.
 */
function dictationStart(locale) {
  return new Promise((resolve, reject) => {
    endSession('Restarted.');

    const helper = transcriberPath();
    const model = modelPath();
    if (!fs.existsSync(helper)) return reject(new Error(NOT_BUILT));
    if (!fs.existsSync(model)) return reject(new Error(NO_MODEL));

    // Whisper wants a bare language code; the browser hands us en-GB and such.
    const language = String(locale || 'en').split('-')[0].toLowerCase();

    const child = spawn(helper, ['--stream', model, language], {
      stdio: ['pipe', 'pipe', 'pipe']
    });

    const current = {
      child,
      out: '',
      err: '',
      text: '',
      resolveReady: resolve,
      rejectReady: reject,
      resolveFinal: null,
      rejectFinal: null,
      readyTimer: null,
      finalTimer: null
    };
    dictation = current;

    const settleReady = (err) => {
      clearTimeout(current.readyTimer);
      const ok = current.resolveReady;
      const no = current.rejectReady;
      current.resolveReady = current.rejectReady = null;
      if (err) { if (no) no(err); } else if (ok) ok({ ok: true });
    };

    const settleFinal = (err, text) => {
      clearTimeout(current.finalTimer);
      const ok = current.resolveFinal;
      const no = current.rejectFinal;
      current.resolveFinal = current.rejectFinal = null;
      if (err) { if (no) no(err); } else if (ok) ok({ text: text || '' });
    };

    current.handleLine = (line) => {
      let message;
      try { message = JSON.parse(line); } catch { return; }

      switch (message.type) {
        case 'ready':
          settleReady(null);
          break;
        case 'partial':
          current.text = message.text || '';
          if (win && !win.isDestroyed()) {
            win.webContents.send('dictation:partial', current.text);
          }
          break;
        case 'final':
          current.text = message.text || current.text;
          settleReady(null);              // in case it ended before saying ready
          settleFinal(null, current.text);
          break;
        case 'error': {
          const failure = new Error(message.message || 'Transcription failed.');
          settleReady(failure);
          settleFinal(failure);
          break;
        }
      }
    };

    child.stdout.on('data', (chunk) => {
      current.out += chunk.toString();
      const lines = current.out.split('\n');
      current.out = lines.pop();          // keep the unfinished tail
      lines.filter(Boolean).forEach(current.handleLine);
    });

    child.stderr.on('data', (chunk) => { current.err += chunk.toString(); });

    child.on('error', (err) => {
      const failure = new Error(
        err.code === 'ENOENT' ? NOT_BUILT : 'Couldn\'t start dictation: ' + err.message);
      settleReady(failure);
      settleFinal(failure);
      if (dictation === current) dictation = null;
    });

    child.on('close', () => {
      const detail = current.err.trim().split('\n')[0];
      const failure = new Error(detail || 'Dictation stopped unexpectedly.');
      settleReady(failure);
      // Closing without a final line still hands back whatever was heard.
      if (current.resolveFinal) settleFinal(null, current.text);
      else settleFinal(failure);
      if (dictation === current) dictation = null;
    });

    // Loading the model off disk is the slow case; longer than this is a hang.
    current.readyTimer = setTimeout(() => {
      settleReady(new Error(
        'The speech engine didn\'t start. Use Journal → Check Dictation… to see why.'));
      endSession('Timed out starting.');
    }, 60 * 1000);
  });
}

/** Feed audio in while the writer talks. */
function dictationAudio(chunk) {
  if (!dictation || !dictation.child.stdin.writable) return false;
  dictation.child.stdin.write(Buffer.from(chunk));
  return true;
}

/** Stop listening and wait for the finished sentence. */
function dictationStop() {
  if (!dictation) return Promise.resolve({ text: '' });
  const current = dictation;

  return new Promise((resolve, reject) => {
    current.resolveFinal = resolve;
    current.rejectFinal = reject;

    try { current.child.stdin.end(); } catch { /* already closed */ }

    // Finishing up after the audio stops should take a moment, not minutes.
    current.finalTimer = setTimeout(() => {
      const text = current.text;
      endSession('Finishing timed out.');
      // Better to hand back the partial text than to lose the whole ramble.
      resolve({ text });
    }, 45 * 1000);
  }).finally(() => {
    if (dictation === current) dictation = null;
    try { current.child.kill('SIGTERM'); } catch { /* already gone */ }
  });
}

function dictationCancel() {
  endSession('Discarded.');
  return true;
}

/** Ask the helper what's working. Surfaced in the Journal menu. */
function dictationDiagnose(locale) {
  return new Promise((resolve) => {
    const helper = transcriberPath();
    const model = modelPath();
    if (!fs.existsSync(helper)) return resolve({ ok: false, message: NOT_BUILT });
    if (!fs.existsSync(model)) return resolve({ ok: false, message: NO_MODEL });

    execFile(helper, ['--diagnose', model], { timeout: 60 * 1000 },
      (error, stdout, stderr) => {
        const line = String(stdout || '').trim().split('\n').filter(Boolean).pop();
        let reply = null;
        try { reply = line ? JSON.parse(line) : null; } catch { /* not JSON */ }
        if (reply) return resolve({ ok: reply.type === 'ready', ...reply });
        resolve({
          ok: false,
          message: String(stderr || '').trim().split('\n')[0]
            || (error ? error.message : 'The transcriber gave no answer.')
        });
      });
  });
}

/** Ask macOS for the microphone, once. */
async function ensureMicrophone() {
  if (!IS_MAC) return true;
  const status = systemPreferences.getMediaAccessStatus('microphone');
  if (status === 'granted') return true;
  if (status === 'denied' || status === 'restricted') {
    throw new Error(
      'Journal isn\'t allowed to use the microphone. Turn it on in System Settings → '
      + 'Privacy & Security → Microphone.');
  }
  const granted = await systemPreferences.askForMediaAccess('microphone');
  if (!granted) throw new Error('Journal needs the microphone to take dictation.');
  return true;
}

app.on('before-quit', () => endSession('Quitting.'));

// -------------------------------------------------------------------- menu

function buildMenu() {
  const send = (action) => () => toRenderer('menu', action);

  const template = [
    ...(IS_MAC ? [{
      label: 'Journal',
      submenu: [
        { role: 'about' },
        { type: 'separator' },
        { role: 'services' },
        { type: 'separator' },
        { role: 'hide' },
        { role: 'hideOthers' },
        { role: 'unhide' },
        { type: 'separator' },
        { role: 'quit' }
      ]
    }] : []),
    {
      label: 'File',
      submenu: [
        { label: 'New Entry', accelerator: 'CmdOrCtrl+N', click: send('new-entry') },
        { label: 'Save Entry', accelerator: 'CmdOrCtrl+S', click: send('save-entry') },
        { type: 'separator' },
        IS_MAC ? { role: 'close' } : { role: 'quit' }
      ]
    },
    {
      label: 'Edit',
      submenu: [
        { role: 'undo' }, { role: 'redo' },
        { type: 'separator' },
        { role: 'cut' }, { role: 'copy' }, { role: 'paste' },
        { role: 'selectAll' },
        { type: 'separator' },
        { label: 'Find in Journal', accelerator: 'CmdOrCtrl+F', click: send('focus-search') }
      ]
    },
    {
      label: 'View',
      submenu: [
        { label: 'Calendar', accelerator: 'CmdOrCtrl+1', click: send('view-calendar') },
        { label: 'Write', accelerator: 'CmdOrCtrl+2', click: send('view-write') },
        { label: 'Entries', accelerator: 'CmdOrCtrl+3', click: send('view-entries') },
        { type: 'separator' },
        { role: 'resetZoom' }, { role: 'zoomIn' }, { role: 'zoomOut' },
        { type: 'separator' },
        { role: 'togglefullscreen' },
        { role: 'toggleDevTools' }
      ]
    },
    {
      label: 'Journal',
      submenu: [
        {
          label: 'Open Journal Folder',
          accelerator: 'CmdOrCtrl+Shift+O',
          click: () => shell.openPath(journal.getRoot())
        },
        { label: 'Move Journal Folder…', click: () => chooseFolder() },
        { type: 'separator' },
        {
          label: 'Check Dictation…',
          click: async () => {
            const result = await dictationDiagnose('en-US');
            await dialog.showMessageBox(win, {
              type: result.ok ? 'info' : 'warning',
              message: result.ok ? 'Dictation is ready.' : 'Dictation isn\'t working.',
              detail: (result.message || '')
                + (result.model ? `\n\nModel: ${path.basename(result.model)}` : '')
                + (result.threads ? `\nThreads: ${result.threads}` : '')
            });
          }
        },
        {
          label: 'Reveal Today\'s Entries',
          click: () => {
            const now = new Date();
            const dir = path.join(
              journal.getRoot(), 'entries',
              String(now.getFullYear()),
              String(now.getMonth() + 1).padStart(2, '0')
            );
            shell.openPath(fs.existsSync(dir) ? dir : journal.getRoot());
          }
        }
      ]
    },
    {
      label: 'Window',
      submenu: IS_MAC
        ? [{ role: 'minimize' }, { role: 'zoom' }, { type: 'separator' }, { role: 'front' }]
        : [{ role: 'minimize' }, { role: 'close' }]
    }
  ];

  Menu.setApplicationMenu(Menu.buildFromTemplate(template));
}

// -------------------------------------------------------------------- IPC

function registerIpc() {
  const guard = (fn) => async (...args) => {
    try {
      return { ok: true, data: await fn(...args) };
    } catch (err) {
      return { ok: false, error: err.message };
    }
  };

  ipcMain.handle('journal:info', guard(async () => ({
    root: journal.getRoot(),
    platform: process.platform,
    version: app.getVersion()
  })));

  ipcMain.handle('journal:list', guard(() => journal.readAll()));
  ipcMain.handle('journal:save', guard((_e, entry) => journal.save(entry)));
  ipcMain.handle('journal:remove', guard((_e, id) => journal.remove(id)));
  ipcMain.handle('journal:saveMedia', guard((_e, payload) => journal.saveMedia(payload)));
  ipcMain.handle('journal:chooseFolder', guard(() => chooseFolder()));
  ipcMain.handle('journal:openFolder', guard(() => shell.openPath(journal.getRoot())));

  ipcMain.handle('journal:micAccess', guard(() => ensureMicrophone()));
  ipcMain.handle('journal:dictationStart', guard((_e, locale) => dictationStart(locale)));
  ipcMain.handle('journal:dictationAudio', guard((_e, chunk) => dictationAudio(chunk)));
  ipcMain.handle('journal:dictationStop', guard(() => dictationStop()));
  ipcMain.handle('journal:dictationCancel', guard(() => dictationCancel()));
  ipcMain.handle('journal:dictationDiagnose', guard((_e, locale) => dictationDiagnose(locale)));

  ipcMain.handle('journal:confirmDelete', guard(async () => {
    const { response } = await dialog.showMessageBox(win, {
      type: 'warning',
      buttons: ['Delete Entry', 'Cancel'],
      defaultId: 1,
      cancelId: 1,
      message: 'Delete this entry?',
      detail: 'The writing is removed. Its photos stay on disk, so nothing you can\'t replace is lost.'
    });
    return response === 0;
  }));
}

// ------------------------------------------------------------------- start

protocol.registerSchemesAsPrivileged([
  { scheme: 'journal', privileges: { standard: true, secure: true, supportFetchAPI: true, stream: true } }
]);

// One journal at a time — a second copy just focuses the first.
if (!app.requestSingleInstanceLock()) {
  app.quit();
} else {
  app.on('second-instance', () => {
    if (win) { if (win.isMinimized()) win.restore(); win.focus(); }
  });

  app.whenReady().then(async () => {
    await loadConfig();
    await resolveRoot();

    // The window may ask for the microphone, and nothing else.
    session.defaultSession.setPermissionRequestHandler((_wc, permission, callback) => {
      callback(permission === 'media' || permission === 'audioCapture');
    });

    registerProtocol();
    registerIpc();
    buildMenu();
    createWindow();

    app.on('activate', () => {
      if (BrowserWindow.getAllWindows().length === 0) createWindow();
    });
  });

  app.on('window-all-closed', () => {
    if (!IS_MAC) app.quit();
  });
}
