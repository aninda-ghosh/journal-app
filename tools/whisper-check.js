#!/usr/bin/env node
/**
 * Prove the speech engine actually transcribes — on a real Mac.
 *
 * whisper.cpp ships a recording of a well-known speech, so we know exactly what
 * should come back. This streams that audio into the transcriber the same way
 * the app does (16 kHz mono PCM on stdin, in real-time-sized chunks) and checks
 * that recognisable words come out the other end.
 *
 * This is the one part of dictation that can't be verified without Apple
 * Silicon and the real model, so it's a script rather than part of `npm test`.
 *
 *   npm run check-dictation
 */

'use strict';

const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');
const HELPER = path.join(ROOT, 'native', 'build', 'transcriber');
const SAMPLE = path.join(ROOT, 'native', 'whisper.cpp', 'samples', 'jfk.wav');

// The sample is a fragment of Kennedy's 1961 inaugural address.
const EXPECTED = ['country', 'ask not', 'fellow americans'];

function findModel() {
  const dir = path.join(ROOT, 'native', 'models');
  try {
    const found = fs.readdirSync(dir).filter((f) => /^ggml-.*\.bin$/.test(f)).sort();
    if (found.length) return path.join(dir, found[0]);
  } catch { /* nothing downloaded */ }
  return null;
}

/** Strip a WAV header and hand back raw 16-bit samples. */
function readWavPcm(file) {
  const buf = fs.readFileSync(file);
  if (buf.toString('ascii', 0, 4) !== 'RIFF') throw new Error('Not a WAV file');

  const rate = buf.readUInt32LE(24);
  const channels = buf.readUInt16LE(22);
  const bits = buf.readUInt16LE(34);

  // Find the data chunk rather than assuming a 44-byte header.
  let at = 12;
  while (at + 8 < buf.length) {
    const id = buf.toString('ascii', at, at + 4);
    const size = buf.readUInt32LE(at + 4);
    if (id === 'data') return { pcm: buf.subarray(at + 8, at + 8 + size), rate, channels, bits };
    at += 8 + size;
  }
  throw new Error('No audio found in the WAV');
}

const missing = [];
if (!fs.existsSync(HELPER)) missing.push('the transcriber (native/build/transcriber)');
if (!fs.existsSync(SAMPLE)) missing.push('the sample recording (native/whisper.cpp/samples/jfk.wav)');
const MODEL = findModel();
if (!MODEL) missing.push('a speech model (native/models/ggml-*.bin)');

if (missing.length) {
  console.log('Can\'t run the check yet — missing:');
  missing.forEach((m) => console.log('  · ' + m));
  console.log('\nRun build.command first; it fetches and builds all of these.');
  process.exit(1);
}

const { pcm, rate, channels, bits } = readWavPcm(SAMPLE);
const seconds = pcm.length / (rate * channels * (bits / 8));

console.log(`model    ${path.basename(MODEL)}`);
console.log(`sample   ${rate}Hz ${channels}ch ${bits}bit, ${seconds.toFixed(1)}s\n`);

const child = spawn(HELPER, ['--stream', MODEL, 'en'], { stdio: ['pipe', 'pipe', 'inherit'] });

const started = Date.now();
let buffer = '';
let final = null;
let partials = 0;
let ready = null;          // resolves when the engine says it can listen

child.stdout.on('data', (chunk) => {
  buffer += chunk.toString();
  const lines = buffer.split('\n');
  buffer = lines.pop();

  for (const line of lines.filter(Boolean)) {
    let message;
    try { message = JSON.parse(line); } catch { continue; }
    const at = ((Date.now() - started) / 1000).toFixed(1).padStart(5);

    if (message.type === 'ready') {
      console.log(`${at}s  ready`);
      if (ready) ready();
    } else if (message.type === 'partial') {
      partials++;
      console.log(`${at}s  partial  ${message.text.slice(-72)}`);
    } else if (message.type === 'final') {
      final = message.text;
      console.log(`${at}s  final    ${message.text}`);
    } else if (message.type === 'error') {
      console.log(`${at}s  ERROR    ${message.message}`);
    }
  }
});

// Wait to be told it's listening, then feed at the pace a person actually
// speaks. The app does exactly this — starting to talk before the engine is
// ready would test something that never happens.
(async () => {
  await new Promise((resolve) => {
    ready = resolve;
    setTimeout(resolve, 60000);       // don't hang forever if it never speaks up
  });

  const step = Math.round(rate * 0.25) * 2;
  for (let at = 0; at < pcm.length; at += step) {
    child.stdin.write(pcm.subarray(at, at + step));
    await new Promise((r) => setTimeout(r, 250));
  }
  child.stdin.end();
})();

child.on('close', () => {
  const heard = (final || '').toLowerCase();
  const found = EXPECTED.filter((phrase) => heard.includes(phrase));

  // Two separate questions: does it transcribe correctly, and does it do so
  // while you're still talking? Only the first decides pass or fail — live
  // partials are a nicety, and conflating them once reported a working engine
  // as broken.
  const transcribes = found.length >= 2;
  const live = partials > 0;

  console.log('\n' + '-'.repeat(60));
  console.log(`transcription : ${found.length}/${EXPECTED.length} phrases` +
              (found.length ? `  (${found.join(', ')})` : ''));
  console.log(`live partials : ${partials}` +
              (live ? '' : '  — words only appeared at the end'));

  if (transcribes && live) {
    console.log('\n✓ Dictation works. Real words, arriving live.');
    process.exit(0);
  }

  if (transcribes) {
    console.log('\n✓ Dictation works — the transcript is correct.');
    console.log('  But nothing appeared until you stopped talking, so text will');
    console.log('  arrive in one lump rather than building as you speak.');
    process.exit(0);   // it transcribes; that's the thing that matters
  }

  if (!final) {
    console.log('\n✗ Nothing came back at all. The engine started but produced no text.');
  } else {
    console.log('\n✗ Text came back, but not the expected words:');
    console.log(`    ${final}`);
    console.log('  The model may be the wrong one, or damaged.');
  }
  process.exit(1);
});
