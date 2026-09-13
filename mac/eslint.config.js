'use strict';

/**
 * Just enough linting to catch what has actually gone wrong in this codebase:
 * bindings left behind by a refactor, and names that quietly shadow something
 * important — a `state` parameter hiding the global `state` object, say.
 */

const nodeGlobals = {
  require: 'readonly',
  module: 'writable',
  exports: 'writable',
  process: 'readonly',
  console: 'readonly',
  Buffer: 'readonly',
  __dirname: 'readonly',
  __filename: 'readonly',
  setTimeout: 'readonly',
  clearTimeout: 'readonly',
  setInterval: 'readonly',
  clearInterval: 'readonly',
  URL: 'readonly',
  Response: 'readonly',
  fetch: 'readonly',
  TextDecoder: 'readonly',
  TextEncoder: 'readonly'
};

const browserGlobals = {
  window: 'readonly',
  document: 'readonly',
  navigator: 'readonly',
  localStorage: 'readonly',
  setTimeout: 'readonly',
  clearTimeout: 'readonly',
  console: 'readonly',
  Image: 'readonly',
  FileReader: 'readonly',
  URL: 'readonly',
  Blob: 'readonly',
  File: 'readonly',
  AudioContext: 'readonly',
  AudioWorkletNode: 'readonly',
  AudioWorkletProcessor: 'readonly',
  registerProcessor: 'readonly',
  DataView: 'readonly',
  Uint8Array: 'readonly',
  Float32Array: 'readonly',
  KeyboardEvent: 'readonly',
  Dictation: 'readonly'
};

const rules = {
  'no-unused-vars': ['error', { args: 'none', caughtErrors: 'none' }],
  'no-undef': 'error',
  'no-shadow': 'error',
  'no-var': 'error',
  eqeqeq: ['error', 'smart']
};

module.exports = [
  {
    ignores: ['node_modules/**', 'dist/**', 'native/**', 'build/**']
  },
  {
    files: ['src/main.js', 'src/preload.js', 'src/journal.js', 'tools/**/*.js'],
    languageOptions: {
      ecmaVersion: 2022,
      sourceType: 'commonjs',
      globals: nodeGlobals
    },
    rules
  },
  {
    files: ['src/renderer/**/*.js'],
    languageOptions: {
      ecmaVersion: 2022,
      sourceType: 'script',
      globals: browserGlobals
    },
    rules
  }
];
