/**
 * The only bridge between the interface and the rest of the machine.
 *
 * The renderer gets these functions and nothing else — no filesystem, no Node,
 * no network. Every call is answered by the main process.
 */

'use strict';

const { contextBridge, ipcRenderer } = require('electron');

/** Unwrap the {ok, data, error} envelope the main process replies with. */
async function call(channel, payload) {
  const result = await ipcRenderer.invoke(channel, payload);
  if (!result || !result.ok) throw new Error((result && result.error) || 'Something went wrong');
  return result.data;
}

const MENU_ACTIONS = new Set([
  'new-entry', 'save-entry', 'focus-search',
  'view-calendar', 'view-write', 'view-entries'
]);

contextBridge.exposeInMainWorld('journal', {
  info: () => call('journal:info'),
  list: () => call('journal:list'),
  save: (entry) => call('journal:save', entry),
  remove: (id) => call('journal:remove', id),
  saveMedia: (payload) => call('journal:saveMedia', payload),
  chooseFolder: () => call('journal:chooseFolder'),
  openFolder: () => call('journal:openFolder'),
  confirmDelete: () => call('journal:confirmDelete'),

  /**
   * Dictation. Audio goes in while you talk and words come back as you talk,
   * all on this Mac.
   */
  micAccess: () => call('journal:micAccess'),
  dictationStart: (locale) => call('journal:dictationStart', locale),
  dictationAudio: (chunk) => call('journal:dictationAudio', chunk),
  dictationStop: () => call('journal:dictationStop'),
  dictationCancel: () => call('journal:dictationCancel'),
  dictationDiagnose: (locale) => call('journal:dictationDiagnose', locale),

  /** Words recognised so far, delivered while the writer is still speaking. */
  onPartial: (handler) => {
    ipcRenderer.on('dictation:partial', (_event, text) => handler(String(text || '')));
  },

  /** Turn a stored `media/…` path into something an <img> can load. */
  mediaUrl: (relPath) => 'journal://media/' + String(relPath)
    .replace(/^\/*media\//, '')
    .split('/')
    .map(encodeURIComponent)
    .join('/'),

  /** Menu commands, forwarded to the interface. */
  onMenu: (handler) => {
    ipcRenderer.on('menu', (_event, action) => {
      if (MENU_ACTIONS.has(action)) handler(action);
    });
  },

  /** Fired when the journal folder has been moved. */
  onMoved: (handler) => {
    ipcRenderer.on('journal:moved', (_event, root) => handler(root));
  },

  /** Fired when entries on disk have been added, modified, or removed. */
  onChanged: (handler) => {
    ipcRenderer.on('journal:changed', () => handler());
  },

  platform: process.platform
});
