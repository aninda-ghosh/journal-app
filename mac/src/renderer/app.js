/* Journal — local photo journal
   The interface. It has no filesystem and no network of its own: everything
   reaches disk through `window.journal`, the small bridge in preload.js.
   No accounts, no analytics, nothing listening on a port. */

'use strict';

// ---------------------------------------------------------------- state

const state = {
  entries: [],
  view: 'calendar',
  calYear: new Date().getFullYear(),
  calMonth: new Date().getMonth(),
  search: '',
  activeTags: new Set(),
  dayFilter: null,       // 'YYYY-MM-DD' when you click a calendar day
  editingId: null,
  photos: []             // [{ path, url, pending }]
};

const $ = (sel) => document.querySelector(sel);
const el = (tag, props) => Object.assign(document.createElement(tag), props || {});

// ------------------------------------------------------------- utilities

function escapeHtml(str) {
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function pad(n) { return String(n).padStart(2, '0'); }

function todayKey() {
  const d = new Date();
  return d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate());
}

/** 'YYYY-MM-DD' for an entry (its id or date always starts with the date). */
function dayKeyOf(entry) {
  if (entry.id && /^\d{4}-\d{2}-\d{2}/.test(entry.id)) {
    return entry.id.slice(0, 10);
  }
  if (entry.date && /^\d{4}-\d{2}-\d{2}/.test(entry.date)) {
    return entry.date.slice(0, 10);
  }
  return (entry.id || entry.date || '').slice(0, 10);
}

/**
 * Which photo represents a day on the calendar.
 *
 * A day can hold several entries. Rather than showing whichever came first,
 * show the photo from the entry you had the most to say about — the length of
 * the writing is a decent stand-in for which moment mattered. Ties go to the
 * earlier entry, so the choice is stable as the day fills up.
 */
function dayPhoto(dayEntries) {
  let lead = null;
  for (const entry of dayEntries) {
    if (!entry.photos.length) continue;
    if (!lead) { lead = entry; continue; }
    const size = entry.body.trim().length;
    const best = lead.body.trim().length;
    if (size > best || (size === best && entry.id < lead.id)) lead = entry;
  }
  return lead ? lead.photos[0] : null;
}

function formatLongDate(dateStr) {
  const d = new Date(dateStr.replace(' ', 'T'));
  if (isNaN(d)) return dateStr;
  return d.toLocaleDateString(undefined, {
    weekday: 'long', year: 'numeric', month: 'long', day: 'numeric'
  }) + ' · ' + d.toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' });
}

/** A stored path -> a URL this window is allowed to load. */
const src = (relPath) => window.journal.mediaUrl(relPath);

function toast(message) {
  const existing = $('.toast');
  if (existing) existing.remove();
  const node = el('div', { className: 'toast', textContent: message });
  document.body.appendChild(node);
  setTimeout(() => node.remove(), 2400);
}

// ------------------------------------------------- a small markdown pass

function renderMarkdown(markdown) {
  const lines = escapeHtml(markdown).split('\n');
  const out = [];
  let paragraph = [];
  let list = null; // 'ul' | 'ol'

  const flushParagraph = () => {
    if (paragraph.length) {
      out.push('<p>' + inline(paragraph.join('<br>')) + '</p>');
      paragraph = [];
    }
  };
  const closeList = () => {
    if (list) { out.push('</' + list + '>'); list = null; }
  };

  const inline = (text) => text
    .replace(/`([^`]+)`/g, '<code>$1</code>')
    .replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>')
    .replace(/(^|\W)\*([^*\n]+)\*/g, '$1<em>$2</em>')
    .replace(/(^|\W)_([^_\n]+)_/g, '$1<em>$2</em>')
    .replace(/\[([^\]]+)\]\((https?:\/\/[^)\s]+)\)/g,
      '<a href="$2" target="_blank" rel="noopener noreferrer">$1</a>');

  for (const raw of lines) {
    const line = raw.trimEnd();

    if (!line.trim()) { flushParagraph(); closeList(); continue; }

    let m;
    if ((m = line.match(/^(#{1,3})\s+(.*)$/))) {
      flushParagraph(); closeList();
      const level = m[1].length;
      out.push(`<h${level}>${inline(m[2])}</h${level}>`);
      continue;
    }
    if (/^(---+|\*\*\*+)$/.test(line.trim())) {
      flushParagraph(); closeList();
      out.push('<hr>');
      continue;
    }
    if ((m = line.match(/^>\s?(.*)$/))) {
      flushParagraph(); closeList();
      out.push('<blockquote>' + inline(m[1]) + '</blockquote>');
      continue;
    }
    if ((m = line.match(/^\s*[-*+]\s+(.*)$/))) {
      flushParagraph();
      if (list !== 'ul') { closeList(); out.push('<ul>'); list = 'ul'; }
      out.push('<li>' + inline(m[1]) + '</li>');
      continue;
    }
    if ((m = line.match(/^\s*\d+[.)]\s+(.*)$/))) {
      flushParagraph();
      if (list !== 'ol') { closeList(); out.push('<ol>'); list = 'ol'; }
      out.push('<li>' + inline(m[1]) + '</li>');
      continue;
    }

    closeList();
    paragraph.push(line);
  }

  flushParagraph();
  closeList();
  return out.join('\n');
}

// ------------------------------------------------------------ data layer

async function loadEntries() {
  state.entries = await window.journal.list();
  render();
}

async function saveEntry() {
  const body = $('#body').value;
  if (!body.trim() && state.photos.length === 0) {
    toast('Write something, or add a photo.');
    return;
  }
  if (state.photos.some((p) => p.pending)) {
    toast('Still saving photos — one moment.');
    return;
  }

  const editing = state.editingId
    ? state.entries.find((e) => e.id === state.editingId)
    : null;

  const payload = {
    id: state.editingId,
    // Keep the entry's own timestamp when editing. Anything else quietly
    // restamps a years-old entry with today's date.
    date: editing ? editing.date : $('#date').value,
    title: $('#title').value,
    body,
    tags: currentTags(),
    photos: state.photos.map((p) => p.path)
  };

  const wasEditing = Boolean(state.editingId);

  try {
    await window.journal.save(payload);
  } catch (err) {
    toast(err.message || 'Could not save.');
    return;
  }

  toast(wasEditing ? 'Entry updated' : 'Entry saved');
  clearComposer();
  await loadEntries();
  switchView('entries');
}

async function deleteEntry(id) {
  if (!(await window.journal.confirmDelete())) return;
  try {
    await window.journal.remove(id);
  } catch (err) {
    toast(err.message || 'Could not delete.');
    return;
  }
  toast('Entry deleted');
  await loadEntries();
}

// --------------------------------------------------------------- photos

function loadImage(url) {
  return new Promise((resolve, reject) => {
    const img = new Image();
    img.onload = () => resolve(img);
    img.onerror = () => reject(new Error('Could not decode image'));
    img.src = url;
  });
}

function fileToDataUrl(file) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(reader.result);
    reader.onerror = () => reject(reader.error);
    reader.readAsDataURL(file);
  });
}

/* Photos are squared, shrunk and re-encoded on the way in, and the result is
   the only copy kept — the file you chose is never written to disk as it came.
   The trade is real and permanent: the sides of every frame are gone, and so
   is any detail beyond 256px. What it buys is a journal small enough to sync
   over iCloud and to keep forever — a year of daily photographs is tens of
   megabytes rather than several gigabytes. This is the one place the app
   destroys something you can't get back, so it is worth knowing about. */

const PHOTO_MAX = 256;    // the stored photo, 256px square

/** Centre-crop to a square and scale to 256px. */
function squareCanvas(img, size = PHOTO_MAX) {
  const side = Math.min(img.naturalWidth, img.naturalHeight);
  const left = (img.naturalWidth - side) / 2;
  const top = (img.naturalHeight - side) / 2;

  const canvas = el('canvas', { width: size, height: size });
  const ctx = canvas.getContext('2d');

  // JPEG has no transparency; without this, a transparent PNG turns black.
  ctx.fillStyle = '#ffffff';
  ctx.fillRect(0, 0, size, size);
  ctx.imageSmoothingEnabled = true;
  ctx.imageSmoothingQuality = 'high';
  ctx.drawImage(img, left, top, side, side, 0, 0, size, size);

  return canvas;
}

/**
 * Turn a chosen file into what actually gets stored: one 256px square JPEG at
 * 82% quality. Returns null if the browser can't decode it — some cameras and
 * phones write formats Chromium won't open, and losing the photo would be far
 * worse than storing it at full size.
 */
async function prepareImage(file) {
  const url = URL.createObjectURL(file);
  try {
    const img = await loadImage(url);
    if (!img.naturalWidth || !img.naturalHeight) return null;
    return {
      photo: squareCanvas(img, PHOTO_MAX).toDataURL('image/jpeg', 0.82),
      size: PHOTO_MAX
    };
  } catch {
    return null;
  } finally {
    URL.revokeObjectURL(url);
  }
}

async function addPhotos(files) {
  for (const file of files) {
    if (!file.type.startsWith('image/') && !/\.(heic|heif)$/i.test(file.name)) continue;

    const slot = { path: null, url: URL.createObjectURL(file), pending: true };
    state.photos.push(slot);
    renderThumbs();

    try {
      const ready = await prepareImage(file);
      const stored = ready
        ? await window.journal.saveMedia({
            name: file.name, photo: ready.photo, processed: true
          })
        : await window.journal.saveMedia({
            name: file.name, photo: await fileToDataUrl(file), processed: false
          });

      if (!ready) toast(`Couldn't resize ${file.name} — kept it as it came.`);

      slot.path = stored.path;
      slot.pending = false;
    } catch (err) {
      toast('Could not add ' + file.name);
      state.photos.splice(state.photos.indexOf(slot), 1);
    } finally {
      // The preview blob has done its job either way; without this every photo
      // added in a session stays in memory until the window closes.
      URL.revokeObjectURL(slot.url);
      slot.url = null;
    }
    renderThumbs();
  }
  saveDraft();
}

// -------------------------------------------------------------- composer

function currentTags() {
  return Array.from($('#tag-field').querySelectorAll('.chip'))
    .map((chip) => chip.dataset.tag);
}

function addTag(value) {
  const tag = value.trim().toLowerCase().replace(/^#/, '').replace(/,/g, '');
  if (!tag || currentTags().includes(tag)) return;
  const chip = el('span', { className: 'chip' });
  chip.dataset.tag = tag;
  chip.append(tag);
  const remove = el('button', { type: 'button', textContent: '×', title: 'Remove tag' });
  remove.addEventListener('click', () => { chip.remove(); saveDraft(); });
  chip.append(remove);
  $('#tag-field').insertBefore(chip, $('#tag-input'));
  saveDraft();
}

function renderThumbs() {
  const box = $('#thumbs');
  box.innerHTML = '';
  state.photos.forEach((photo, index) => {
    const wrap = el('div', { className: 'thumb' + (photo.pending ? ' pending' : '') });
    wrap.append(el('img', {
      src: photo.pending ? photo.url : src(photo.path),
      alt: ''
    }));
    if (photo.pending) {
      wrap.append(el('div', { className: 'spinner' }));
    } else {
      const remove = el('button', { className: 'remove', textContent: '×', title: 'Remove photo' });
      remove.addEventListener('click', () => {
        state.photos.splice(index, 1);
        renderThumbs();
        saveDraft();
      });
      wrap.append(remove);
    }
    box.append(wrap);
  });
}

function clearComposer() {
  state.editingId = null;
  state.photos = [];
  $('#title').value = '';
  $('#body').value = '';
  $('#date').value = todayKey();
  $('#tag-field').querySelectorAll('.chip').forEach((chip) => chip.remove());
  $('#editing-badge').hidden = true;
  $('#cancel-edit').hidden = true;
  $('#date').disabled = false;
  renderThumbs();
  localStorage.removeItem('journal.draft');
}

function editEntry(id) {
  const entry = state.entries.find((e) => e.id === id);
  if (!entry) return;
  state.editingId = id;
  state.photos = entry.photos.map((p) => ({ path: p, pending: false }));
  $('#title').value = entry.title || '';
  $('#body').value = entry.body || '';
  $('#date').value = dayKeyOf(entry);
  $('#date').disabled = true;
  $('#tag-field').querySelectorAll('.chip').forEach((chip) => chip.remove());
  entry.tags.forEach(addTag);
  $('#editing-badge').hidden = false;
  $('#cancel-edit').hidden = false;
  renderThumbs();
  switchView('write');
  $('#body').focus();
}

/* An unsaved draft survives a closed window. Thoughts shouldn't evaporate. */
function saveDraft() {
  if (state.editingId) return;
  const draft = {
    title: $('#title').value,
    body: $('#body').value,
    date: $('#date').value,
    tags: currentTags(),
    photos: state.photos.filter((p) => !p.pending)
  };
  const isEmpty = !draft.title && !draft.body.trim() && draft.photos.length === 0;
  try {
    if (isEmpty) localStorage.removeItem('journal.draft');
    else localStorage.setItem('journal.draft', JSON.stringify(draft));
  } catch { /* storage disabled — the draft just won't persist */ }
}

function restoreDraft() {
  let draft;
  try {
    draft = JSON.parse(localStorage.getItem('journal.draft') || 'null');
  } catch { return; }
  if (!draft) return;
  $('#title').value = draft.title || '';
  $('#body').value = draft.body || '';
  if (draft.date) $('#date').value = draft.date;
  (draft.tags || []).forEach(addTag);
  state.photos = draft.photos || [];
  renderThumbs();
}

// ------------------------------------------------------------- filtering

function visibleEntries() {
  const query = state.search.trim().toLowerCase();
  return state.entries.filter((entry) => {
    if (state.dayFilter && dayKeyOf(entry) !== state.dayFilter) return false;
    for (const tag of state.activeTags) {
      if (!entry.tags.includes(tag)) return false;
    }
    if (query) {
      const haystack = (entry.title + ' ' + entry.body + ' ' + entry.tags.join(' ')).toLowerCase();
      if (!haystack.includes(query)) return false;
    }
    return true;
  });
}

function allTags() {
  const counts = new Map();
  for (const entry of state.entries) {
    for (const tag of entry.tags) counts.set(tag, (counts.get(tag) || 0) + 1);
  }
  return Array.from(counts.entries()).sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]));
}

// --------------------------------------------------------------- calendar

function renderCalendar() {
  const grid = $('#cal-grid');
  grid.innerHTML = '';

  const { calYear: year, calMonth: month } = state;
  const first = new Date(year, month, 1);
  const daysInMonth = new Date(year, month + 1, 0).getDate();

  $('#cal-title').textContent = first.toLocaleDateString(undefined, {
    month: 'long', year: 'numeric'
  });

  // Bucket entries by day for this month.
  const byDay = new Map();
  for (const entry of state.entries) {
    const key = dayKeyOf(entry);
    if (!byDay.has(key)) byDay.set(key, []);
    byDay.get(key).push(entry);
  }

  for (let i = 0; i < first.getDay(); i++) {
    grid.append(el('div', { className: 'day blank' }));
  }

  let daysWritten = 0;

  for (let day = 1; day <= daysInMonth; day++) {
    const key = year + '-' + pad(month + 1) + '-' + pad(day);
    const dayEntries = byDay.get(key) || [];
    const photo = dayPhoto(dayEntries);

    const cell = el('button', { className: 'day', type: 'button' });
    const dayLabel = new Date(year, month, day).toLocaleDateString(undefined, {
      weekday: 'long', month: 'long', day: 'numeric', year: 'numeric'
    });
    cell.setAttribute('aria-label', dayEntries.length
      ? `${dayLabel} — ${dayEntries.length} ${dayEntries.length === 1 ? 'entry' : 'entries'}`
      : `${dayLabel} — nothing written`);
    if (dayEntries.length) { cell.classList.add('has-entry'); daysWritten++; }
    if (photo) cell.classList.add('has-photo');
    if (key === todayKey()) cell.classList.add('today');

    if (photo) {
      cell.append(el('img', { src: src(photo), alt: '', loading: 'lazy' }));
    }

    cell.append(el('span', { className: 'num', textContent: String(day) }));

    if (dayEntries.length && !photo) cell.append(el('span', { className: 'dot' }));
    if (dayEntries.length > 1) {
      cell.append(el('span', { className: 'count', textContent: dayEntries.length }));
    }

    cell.addEventListener('click', () => {
      if (dayEntries.length) {
        state.dayFilter = key;
        state.search = '';
        state.activeTags.clear();
        $('#search').value = '';
        switchView('entries');
        render();
      } else {
        clearComposer();
        $('#date').value = key;
        switchView('write');
        $('#body').focus();
      }
    });

    grid.append(cell);
  }

  const total = state.entries.length;
  $('#cal-summary').textContent = daysWritten
    ? `${daysWritten} ${daysWritten === 1 ? 'day' : 'days'} written this month · ${total} ${total === 1 ? 'entry' : 'entries'} in all`
    : total
      ? `Nothing this month yet · ${total} ${total === 1 ? 'entry' : 'entries'} in all`
      : '';
}

// ---------------------------------------------------------------- entries

function renderFilters() {
  const box = $('#filters');
  box.innerHTML = '';

  if (state.dayFilter) {
    const label = new Date(state.dayFilter + 'T12:00:00')
      .toLocaleDateString(undefined, { month: 'long', day: 'numeric', year: 'numeric' });
    const chip = el('span', { className: 'chip on' });
    chip.append(label);
    const clear = el('button', { type: 'button', textContent: '×' });
    clear.addEventListener('click', () => { state.dayFilter = null; render(); });
    chip.append(clear);
    box.append(chip);
  }

  for (const [tag, count] of allTags()) {
    const chip = el('span', {
      className: 'chip' + (state.activeTags.has(tag) ? ' on' : ''),
      textContent: `${tag} ${count}`
    });
    chip.addEventListener('click', () => {
      state.activeTags.has(tag) ? state.activeTags.delete(tag) : state.activeTags.add(tag);
      render();
    });
    box.append(chip);
  }
}

function renderEntryList() {
  const list = $('#entry-list');
  list.innerHTML = '';
  const entries = visibleEntries();

  if (!entries.length) {
    const empty = el('div', { className: 'empty' });
    if (state.entries.length === 0) {
      empty.append(el('h2', { textContent: 'Nothing written yet' }));
      empty.append(el('p', { textContent: 'Your first entry is one click away — try “New entry”.' }));
    } else {
      empty.append(el('h2', { textContent: 'No entries match' }));
      empty.append(el('p', { textContent: 'Try a different search, or clear the filters above.' }));
    }
    list.append(empty);
    return;
  }

  for (const entry of entries) {
    const article = el('article', { className: 'entry' });

    const head = el('div', { className: 'entry-head' });
    head.append(el('span', { className: 'entry-date', textContent: formatLongDate(entry.date) }));

    const actions = el('div', { className: 'entry-actions' });
    const edit = el('button', { textContent: 'Edit' });
    edit.addEventListener('click', () => editEntry(entry.id));
    const del = el('button', { className: 'del', textContent: 'Delete' });
    del.addEventListener('click', () => deleteEntry(entry.id));
    actions.append(edit, del);
    head.append(actions);
    article.append(head);

    if (entry.title) article.append(el('h3', { textContent: entry.title }));

    const content = el('div', {
      className: 'entry-content' + (entry.photos.length ? ' has-media' : '')
    });

    if (entry.photos.length) {
      const n = entry.photos.length;
      const gallery = el('div', {
        className: 'gallery ' + (n === 1 ? 'n1' : n === 2 ? 'n2' : n === 3 ? 'n3' : 'many')
      });
      for (const photo of entry.photos) {
        const img = el('img', { src: src(photo), alt: '', loading: 'lazy' });
        img.addEventListener('click', () => openLightbox(src(photo)));
        gallery.append(img);
      }
      content.append(gallery);
    }

    const main = el('div', { className: 'entry-main' });
    if (entry.body.trim()) {
      const prose = el('div', { className: 'prose' });
      prose.innerHTML = renderMarkdown(entry.body);
      main.append(prose);
    }

    if (entry.tags.length) {
      const tags = el('div', { className: 'entry-tags' });
      for (const tag of entry.tags) {
        const chip = el('span', { className: 'chip', textContent: tag });
        chip.addEventListener('click', () => {
          state.activeTags.add(tag);
          state.dayFilter = null;
          render();
        });
        tags.append(chip);
      }
      main.append(tags);
    }

    if (main.hasChildNodes()) {
      content.append(main);
    }

    if (content.hasChildNodes()) {
      article.append(content);
    }

    list.append(article);
  }
}

function openLightbox(url) {
  const box = el('div', { className: 'lightbox' });
  box.append(el('img', { src: url, alt: '' }));
  const close = el('button', { className: 'close', textContent: '×' });
  box.append(close);
  const dismiss = () => { box.remove(); document.removeEventListener('keydown', onKey); };
  const onKey = (e) => { if (e.key === 'Escape') dismiss(); };
  box.addEventListener('click', dismiss);
  document.addEventListener('keydown', onKey);
  document.body.append(box);
}

// ------------------------------------------------------------ view logic

function switchView(name) {
  state.view = name;
  document.querySelectorAll('.view').forEach((section) => {
    section.classList.toggle('active', section.id === 'view-' + name);
  });
  document.querySelectorAll('nav button').forEach((button) => {
    button.setAttribute('aria-current', String(button.dataset.view === name));
  });
  window.scrollTo({ top: 0 });
}

function render() {
  renderCalendar();
  renderFilters();
  renderEntryList();
}

// ---------------------------------------------------------------- wiring

document.querySelectorAll('nav button').forEach((button) => {
  button.addEventListener('click', () => {
    if (button.dataset.view === 'entries' && state.dayFilter) {
      state.dayFilter = null;
      render();
    }
    switchView(button.dataset.view);
  });
});

$('#new-entry').addEventListener('click', () => {
  if (state.editingId) clearComposer();
  switchView('write');
  $('#body').focus();
});

$('#save').addEventListener('click', saveEntry);
$('#cancel-edit').addEventListener('click', () => { clearComposer(); switchView('entries'); });

$('#search').addEventListener('input', (e) => {
  state.search = e.target.value;
  state.dayFilter = null;
  if (state.view !== 'entries') switchView('entries');
  render();
});

$('#prev-month').addEventListener('click', () => {
  if (--state.calMonth < 0) { state.calMonth = 11; state.calYear--; }
  renderCalendar();
});
$('#next-month').addEventListener('click', () => {
  if (++state.calMonth > 11) { state.calMonth = 0; state.calYear++; }
  renderCalendar();
});
$('#this-month').addEventListener('click', () => {
  const now = new Date();
  state.calYear = now.getFullYear();
  state.calMonth = now.getMonth();
  renderCalendar();
});

// tags
$('#tag-field').addEventListener('click', () => $('#tag-input').focus());
$('#tag-input').addEventListener('keydown', (e) => {
  if (e.key === 'Enter' || e.key === ',' || e.key === 'Tab') {
    if (e.target.value.trim()) {
      e.preventDefault();
      addTag(e.target.value);
      e.target.value = '';
    }
  } else if (e.key === 'Backspace' && !e.target.value) {
    const chips = $('#tag-field').querySelectorAll('.chip');
    if (chips.length) { chips[chips.length - 1].remove(); saveDraft(); }
  }
});
$('#tag-input').addEventListener('blur', (e) => {
  if (e.target.value.trim()) { addTag(e.target.value); e.target.value = ''; }
});

// photos
$('#dropzone').addEventListener('click', () => $('#file-input').click());
$('#file-input').addEventListener('change', (e) => {
  addPhotos(Array.from(e.target.files));
  e.target.value = '';
});

['dragenter', 'dragover'].forEach((type) => {
  $('#dropzone').addEventListener(type, (e) => {
    e.preventDefault();
    $('#dropzone').classList.add('over');
  });
});
['dragleave', 'drop'].forEach((type) => {
  $('#dropzone').addEventListener(type, (e) => {
    e.preventDefault();
    $('#dropzone').classList.remove('over');
  });
});
$('#dropzone').addEventListener('drop', (e) => {
  addPhotos(Array.from(e.dataTransfer.files));
});

// paste a photo straight into the entry
$('#body').addEventListener('paste', (e) => {
  const files = Array.from(e.clipboardData.files || []);
  if (files.length) { e.preventDefault(); addPhotos(files); }
});

// drafts + shortcuts
['#title', '#body', '#date'].forEach((sel) => {
  $(sel).addEventListener('input', saveDraft);
});

document.addEventListener('keydown', (e) => {
  if ((e.metaKey || e.ctrlKey) && e.key === 'Enter') {
    e.preventDefault();
    if (state.view === 'write') saveEntry();
  }
  if ((e.metaKey || e.ctrlKey) && e.key === 'k') {
    e.preventDefault();
    $('#search').focus();
    $('#search').select();
  }
});

// ------------------------------------------------------------- dictation
//
// Words appear while you're still saying them. The text being spoken lives in
// a "live region" of the entry — a stretch between two offsets that gets
// replaced wholesale each time the transcriber revises what it heard.

const dictate = {
  button: $('#dictate'),
  label: $('#dictate-label'),
  meter: $('#dictate-level')
};

/** The stretch of the entry currently being spoken into. */
const live = { start: 0, length: 0, prefix: 0, active: false };

function setDictateState(phase, label) {
  dictate.button.classList.toggle('listening', phase === 'listening');
  dictate.button.classList.toggle('working', phase === 'working');
  dictate.button.disabled = phase === 'working';
  dictate.label.textContent = label;
}

function clock(seconds) {
  const whole = Math.floor(seconds);
  return Math.floor(whole / 60) + ':' + pad(whole % 60);
}

/** Replace the live region with the latest guess at what was said. */
function showSpoken(text) {
  if (!live.active) return;
  const field = $('#body');
  const before = field.value.slice(0, live.start);
  const after = field.value.slice(live.start + live.length);

  field.value = before + text + after;
  live.length = text.length;

  const caret = live.start + text.length;
  field.setSelectionRange(caret, caret);
  field.scrollTop = field.scrollHeight;
}

/** Open a live region at the cursor, spaced sensibly against what's there. */
function openLiveRegion() {
  const field = $('#body');
  const at = field.selectionStart;
  const prefix = at > 0 && !/\s$/.test(field.value.slice(0, at)) ? ' ' : '';

  field.value = field.value.slice(0, at) + prefix + field.value.slice(at);
  live.start = at + prefix.length;
  live.length = 0;
  live.prefix = prefix.length;   // remembered so it can be taken back out again
  live.active = true;

  // While speaking, the entry is not also a typing surface — keeping it
  // read-only means the live region's offsets can't drift underneath us.
  field.readOnly = true;
  field.classList.add('dictating');
  field.focus();
}

/**
 * Close the live region. If the take was discarded — or nothing was heard —
 * take out the spoken text *and* the space that was opened to hold it, so an
 * abandoned recording leaves the entry exactly as it was found.
 */
function closeLiveRegion({ discard = false } = {}) {
  const field = $('#body');

  if (discard || live.length === 0) {
    const from = live.start - live.prefix;
    field.value = field.value.slice(0, from) + field.value.slice(live.start + live.length);
    live.start = from;
    live.length = 0;
  }

  live.active = false;
  live.prefix = 0;
  field.readOnly = false;
  field.classList.remove('dictating');

  const caret = live.start + live.length;
  field.setSelectionRange(caret, caret);
  saveDraft();
}

function resetDictateButton() {
  setDictateState('idle', 'Dictate');
  dictate.meter.style.setProperty('--level', '0%');
}

window.journal.onPartial(showSpoken);

// The engine can fall over after it has said it's ready — it loads the model
// while you're already talking. Close the take rather than leaving the button
// spinning, and keep any words that did make it in.
window.journal.onFailed((message) => {
  if (!window.Dictation.isRecording() && !live.active) return;
  window.Dictation.cancel().catch(() => {});
  if (live.active) closeLiveRegion();
  resetDictateButton();
  toast(message || 'Dictation stopped.');
});

async function startDictation() {
  try {
    await window.journal.micAccess();
  } catch (err) {
    toast(err.message);
    return;
  }

  // The very first run can sit here while macOS asks for permission.
  setDictateState('working', 'Starting…');

  try {
    await window.journal.dictationStart(navigator.language || 'en-US');
  } catch (err) {
    resetDictateButton();
    toast(err.message);
    return;
  }

  openLiveRegion();

  try {
    await window.Dictation.start({
      onTime: (seconds) => { dictate.label.textContent = clock(seconds); },
      onLevel: (level) => {
        // A soft curve reads better than raw amplitude, which barely moves.
        const shown = Math.min(100, Math.round(Math.sqrt(level) * 190));
        dictate.meter.style.setProperty('--level', shown + '%');
      },
      onError: (err) => toast(err.message)
    });
    setDictateState('listening', '0:00');
  } catch (err) {
    window.journal.dictationCancel().catch(() => {});
    closeLiveRegion({ discard: true });
    resetDictateButton();
    toast(err.name === 'NotAllowedError'
      ? 'Journal needs permission to use the microphone.'
      : 'Couldn\'t start recording: ' + err.message);
  }
}

async function finishDictation() {
  setDictateState('working', 'Finishing…');

  let recorded = null;
  try {
    recorded = await window.Dictation.stop();
  } catch (err) {
    toast('Recording stopped unexpectedly: ' + err.message);
  }

  try {
    const { text } = await window.journal.dictationStop();
    if (text) showSpoken(text.trim());
    else if (!live.length) toast('Nothing was said, as far as the transcriber could tell.');
  } catch (err) {
    // Whatever was heard along the way is already in the entry; keep it.
    toast(err.message);
  } finally {
    if (live.length && recorded) toast(`Transcribed ${clock(recorded.seconds)}`);
    closeLiveRegion();
    resetDictateButton();
  }
}

async function abandonDictation() {
  await window.Dictation.cancel();
  window.journal.dictationCancel().catch(() => {});
  closeLiveRegion({ discard: true });
  resetDictateButton();
  toast('Recording discarded');
}

dictate.button.addEventListener('click', () => {
  if (dictate.button.disabled) return;
  window.Dictation.isRecording() ? finishDictation() : startDictation();
});

document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape' && window.Dictation.isRecording()) abandonDictation();
});

// ------------------------------------------------------------ menu bar

window.journal.onMenu((action) => {
  switch (action) {
    case 'new-entry':
      if (state.editingId) clearComposer();
      switchView('write');
      $('#body').focus();
      break;
    case 'save-entry':
      if (state.view === 'write') saveEntry();
      break;
    case 'focus-search':
      switchView('entries');
      $('#search').focus();
      $('#search').select();
      break;
    case 'view-calendar': switchView('calendar'); break;
    case 'view-write': switchView('write'); break;
    case 'view-entries':
      if (state.dayFilter) { state.dayFilter = null; render(); }
      switchView('entries');
      break;
  }
});

window.journal.onMoved(async (root) => {
  toast('Journal moved');
  await showLocation(root);
  await loadEntries();
});

window.journal.onChanged(async () => {
  await loadEntries();
});

// ------------------------------------------------------------------ boot

/** A quiet reminder of where the writing actually lives, and a way to move it. */
async function showLocation(root) {
  const footer = $('#where');
  footer.textContent = '';
  if (!root) return;

  footer.append('Your entries and photos are plain files in ');

  const link = el('button', { className: 'path-link', textContent: root, title: 'Open in Finder' });
  link.addEventListener('click', () => window.journal.openFolder());
  footer.append(link);

  const move = el('button', { className: 'path-move', textContent: 'Move…' });
  move.addEventListener('click', () => window.journal.chooseFolder());
  footer.append(move);
}

if (window.journal.platform === 'darwin') {
  document.body.classList.add('mac');
}

$('#date').value = todayKey();
restoreDraft();

loadEntries().catch((err) => toast(err.message || 'Could not read your journal.'));

window.journal.info()
  .then((info) => showLocation(info.root))
  .catch(() => { /* not important enough to complain about */ });
