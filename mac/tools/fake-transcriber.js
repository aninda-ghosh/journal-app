#!/usr/bin/env node
/**
 * Stands in for the Swift transcriber during tests.
 *
 * Apple's Speech framework can't run in CI or on Linux, but everything leading
 * up to it can: capturing the microphone, streaming PCM out, and words landing
 * live in the entry.
 *
 * Rather than inventing a transcript, this describes the audio it's actually
 * being fed — so a wrong sample rate, a silent microphone or a broken stream
 * fails the test instead of passing quietly.
 *
 * Speaks the same line protocol as the real helper.
 */

'use strict';

const SAMPLE_RATE = 16000;

const say = (payload) => process.stdout.write(JSON.stringify(payload) + '\n');

// Same argv shape as the real helper: mode, model path, language.
const [mode, model = '', locale = 'en'] = process.argv.slice(2);

if (mode === '--diagnose' || mode === '--check') {
  say({ type: 'ready', code: 'ok', model, threads: 1, locale,
        message: 'Stub transcriber: the speech model loaded and is ready.' });
  process.exit(0);
}

if (mode !== '--stream') {
  say({ type: 'error', code: 'bad_usage', message: 'Usage: --stream | --diagnose' });
  process.exit(1);
}

let samples = 0;
let peak = 0;
let spare = null;          // a trailing odd byte, waiting for its other half
let lastSpoken = 0;

say({ type: 'ready' });

process.stdin.on('data', (chunk) => {
  let buf = chunk;
  if (spare) { buf = Buffer.concat([spare, chunk]); spare = null; }
  if (buf.length % 2) { spare = buf.subarray(buf.length - 1); buf = buf.subarray(0, buf.length - 1); }

  for (let i = 0; i + 1 < buf.length; i += 2) {
    peak = Math.max(peak, Math.abs(buf.readInt16LE(i)));
  }
  samples += buf.length / 2;

  // Report roughly twice a second, the way real partial results arrive.
  const seconds = samples / SAMPLE_RATE;
  if (seconds - lastSpoken >= 0.5) {
    lastSpoken = seconds;
    say({ type: 'partial', text: `heard ${seconds.toFixed(1)}s peak ${peak}` });
  }
});

process.stdin.on('end', () => {
  const seconds = samples / SAMPLE_RATE;
  say({
    type: 'final',
    text: `PCM ${SAMPLE_RATE}Hz 16bit ${seconds.toFixed(1)}s peak ${peak}`
  });
  process.exit(0);
});
