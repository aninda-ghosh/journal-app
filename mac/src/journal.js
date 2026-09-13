/**
 * Journal storage.
 *
 * Every entry is a Markdown file. Every photo is an image file. There is no
 * database and no server — this module just reads and writes your folder.
 *
 *   Journal/
 *     entries/2026/09/2026-09-08-143000.md
 *     media/2026/09/<id>.jpg          your original photo, untouched
 *     media/2026/09/<id>.thumb.jpg    small copy, for fast browsing
 *
 * The frontmatter is deliberately dumb — flat `key: value` lines, lists as
 * comma-separated values. It stays readable and editable by hand, and needs
 * no YAML library to parse.
 */

'use strict';

const fs = require('fs');
const fsp = fs.promises;
const path = require('path');
const crypto = require('crypto');

let root = null;

function setRoot(dir) { root = path.resolve(dir); }
function getRoot() { return root; }
function entriesDir() { return path.join(root, 'entries'); }
function mediaDir() { return path.join(root, 'media'); }

async function ensureDirs() {
  await fsp.mkdir(entriesDir(), { recursive: true });
  await fsp.mkdir(mediaDir(), { recursive: true });
}

// ------------------------------------------------------------------ dates

const pad = (n) => String(n).padStart(2, '0');

/** Local-time stamp, e.g. 2026-09-08T14:30:00. No timezone games. */
function localStamp(d) {
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}` +
         `T${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
}

/** Entry id: 2026-09-08-143000 — sorts correctly as a plain string. */
function idFromStamp(stamp) {
  return stamp.slice(0, 10) + '-' + stamp.slice(11).replace(/:/g, '');
}

function isValidId(id) {
  return typeof id === 'string' && /^\d{4}-\d{2}-\d{2}-\d{6}$/.test(id);
}

function entryPath(id) {
  return path.join(entriesDir(), id.slice(0, 4), id.slice(5, 7), id + '.md');
}

// ------------------------------------------------------- entry file format

function serialize(entry) {
  return [
    '---',
    'id: ' + entry.id,
    'date: ' + entry.date,
    'title: ' + (entry.title || ''),
    'tags: ' + (entry.tags || []).join(', '),
    'photos: ' + (entry.photos || []).join(', '),
    '---',
    '',
    entry.body || '',
    ''
  ].join('\n');
}

function parse(raw, fallbackId) {
  const entry = { id: fallbackId, date: '', title: '', tags: [], photos: [], body: '' };
  const text = raw.replace(/\r\n/g, '\n');

  if (!text.startsWith('---\n')) {
    entry.body = text.trim();
    return entry;
  }
  const end = text.indexOf('\n---', 4);
  if (end === -1) {
    entry.body = text.trim();
    return entry;
  }

  entry.body = text.slice(end + 4).replace(/^\n+/, '').replace(/\s+$/, '');

  for (const line of text.slice(4, end).split('\n')) {
    const sep = line.indexOf(':');
    if (sep === -1) continue;
    const key = line.slice(0, sep).trim();
    const value = line.slice(sep + 1).trim();
    if (key === 'tags' || key === 'photos') {
      entry[key] = value.split(',').map((s) => s.trim()).filter(Boolean);
    } else if (key in entry) {
      entry[key] = value;
    }
  }
  return entry;
}

// --------------------------------------------------------------- reading

async function walk(dir, match, out = []) {
  let items;
  try {
    items = await fsp.readdir(dir, { withFileTypes: true });
  } catch (err) {
    if (err.code === 'ENOENT') return out;
    throw err;
  }
  for (const item of items) {
    const full = path.join(dir, item.name);
    if (item.isDirectory()) await walk(full, match, out);
    else if (match(item.name)) out.push(full);
  }
  return out;
}

async function readAll() {
  if (!root) return [];
  const files = await walk(entriesDir(), (name) => name.endsWith('.md'));
  const entries = [];

  for (const file of files) {
    try {
      const raw = await fsp.readFile(file, 'utf8');
      const id = path.basename(file, '.md');
      const entry = parse(raw, id);
      if (!entry.id) entry.id = id;
      if (!entry.date) entry.date = id.slice(0, 10) + 'T00:00:00';
      entries.push(entry);
    } catch (err) {
      // One unreadable file should never take down the whole journal.
      console.error('Skipping unreadable entry:', file, err.message);
    }
  }

  entries.sort((a, b) => (a.id < b.id ? 1 : a.id > b.id ? -1 : 0));
  return entries;
}

// --------------------------------------------------------------- writing

async function save(input) {
  const hasBody = (input.body || '').trim().length > 0;
  const hasPhotos = Array.isArray(input.photos) && input.photos.length > 0;
  if (!hasBody && !hasPhotos) {
    throw new Error('An entry needs some words or a photo.');
  }

  let id = input.id;
  let date = input.date;

  if (!isValidId(id)) {
    const now = new Date();
    if (typeof input.date === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(input.date)) {
      // Backdated to a day picked in the calendar — keep the current time.
      date = localStamp(new Date(
        Number(input.date.slice(0, 4)),
        Number(input.date.slice(5, 7)) - 1,
        Number(input.date.slice(8, 10)),
        now.getHours(), now.getMinutes(), now.getSeconds()
      ));
    } else {
      date = localStamp(now);
    }
    id = idFromStamp(date);
  }

  const entry = {
    id,
    date: date || localStamp(new Date()),
    title: String(input.title || '').replace(/[\r\n]+/g, ' ').trim(),
    tags: (Array.isArray(input.tags) ? input.tags : [])
      .map((t) => String(t).replace(/[,\r\n]/g, ' ').trim().toLowerCase())
      .filter(Boolean)
      .filter((t, i, arr) => arr.indexOf(t) === i),
    photos: (Array.isArray(input.photos) ? input.photos : [])
      .map((p) => String(p).trim())
      .filter((p) => p.startsWith('media/')),
    body: String(input.body || '')
  };

  const file = entryPath(entry.id);
  await fsp.mkdir(path.dirname(file), { recursive: true });
  await fsp.writeFile(file, serialize(entry), 'utf8');
  return entry;
}

async function remove(id) {
  if (!isValidId(id)) throw new Error('Bad entry id');
  try {
    await fsp.unlink(entryPath(id));
  } catch (err) {
    if (err.code !== 'ENOENT') throw err;
  }
  // Photos are deliberately left alone — deleting an entry should never
  // destroy a picture you can't get back.
  return true;
}

/**
 * Store a photo.
 *
 * `photo` is normally a square JPEG the renderer has already cropped and
 * scaled down — that squaring is deliberate and lossy, and it's what keeps a
 * journal of daily photographs to a few hundred megabytes a year rather than
 * several gigabytes.
 *
 * When `processed` is false the renderer couldn't decode the file, so it's
 * written exactly as it arrived. Storing a large photo is much better than
 * losing one.
 */
async function saveMedia({ name, photo, thumb, processed = true }) {
  if (!photo) throw new Error('No image data');

  const now = new Date();
  const year = String(now.getFullYear());
  const month = pad(now.getMonth() + 1);
  const dir = path.join(mediaDir(), year, month);
  await fsp.mkdir(dir, { recursive: true });

  let ext = '.jpg';   // what the renderer produces
  if (!processed) {
    const given = path.extname(String(name || '')).toLowerCase();
    if (/^\.(jpg|jpeg|png|gif|webp|avif|heic|heif|tif|tiff)$/.test(given)) ext = given;
  }

  const id = now.getTime().toString(36) + '-' + crypto.randomBytes(4).toString('hex');

  await fsp.writeFile(
    path.join(dir, id + ext),
    Buffer.from(String(photo).split(',').pop(), 'base64')
  );

  // Single-thumbnail pipeline: only store the single optimized file
  return { path: `media/${year}/${month}/${id}${ext}`, thumb: null };
}

/** Resolve a stored `media/...` path to a real file, refusing anything else. */
function resolveMedia(relPath) {
  const clean = String(relPath).replace(/^\/+/, '');
  if (!clean.startsWith('media/')) return null;
  const full = path.resolve(root, clean);
  const rel = path.relative(root, full);
  if (rel.startsWith('..') || path.isAbsolute(rel)) return null;
  return full;
}

module.exports = {
  setRoot, getRoot, ensureDirs,
  readAll, save, remove, saveMedia, resolveMedia,
  // exported for tests
  _internals: { parse, serialize, localStamp, idFromStamp, isValidId }
};
