/**
 * Recording a ramble.
 *
 * Captures the microphone as 16 kHz mono PCM and streams it out in small
 * batches while you're still talking, so words can come back live rather than
 * after a wait. Nothing is written to disk: the samples pass through memory,
 * become text, and are gone.
 *
 * 16-bit signed little-endian is what the Swift helper reads, and 16 kHz is
 * what speech recognition wants.
 */

'use strict';

const SAMPLE_RATE = 16000;
const BATCH_SECONDS = 0.25;   // four sends a second: live enough, not chatty

const Dictation = (() => {
  let stream = null;
  let context = null;
  let node = null;
  let source = null;
  let pending = [];           // Float32Arrays waiting to be sent
  let pendingLength = 0;
  let total = 0;
  let listeners = {};
  let sending = false;

  const isRecording = () => Boolean(context);

  /** Float samples in [-1, 1] → signed 16-bit little-endian bytes. */
  function toPcm16(blocks, length) {
    const bytes = new Uint8Array(length * 2);
    const view = new DataView(bytes.buffer);
    let offset = 0;
    for (const block of blocks) {
      for (let i = 0; i < block.length; i++) {
        const clamped = Math.max(-1, Math.min(1, block[i]));
        view.setInt16(offset, clamped < 0 ? clamped * 0x8000 : clamped * 0x7fff, true);
        offset += 2;
      }
    }
    return bytes;
  }

  /** Hand a batch to the transcriber. Never let sends pile up on each other. */
  async function flush() {
    if (sending || pendingLength === 0) return;
    const blocks = pending;
    const length = pendingLength;
    pending = [];
    pendingLength = 0;

    sending = true;
    try {
      await window.journal.dictationAudio(toPcm16(blocks, length));
    } catch (err) {
      if (listeners.onError) listeners.onError(err);
    } finally {
      sending = false;
    }
  }

  async function start(handlers = {}) {
    if (isRecording()) return;
    listeners = handlers;
    pending = [];
    pendingLength = 0;
    total = 0;

    stream = await navigator.mediaDevices.getUserMedia({
      audio: {
        channelCount: 1,
        echoCancellation: true,
        noiseSuppression: true,
        autoGainControl: true
      }
    });

    context = new AudioContext({ sampleRate: SAMPLE_RATE });
    await context.audioWorklet.addModule('pcm-worklet.js');

    source = context.createMediaStreamSource(stream);
    node = new AudioWorkletNode(context, 'pcm-collector', { numberOfOutputs: 0 });

    const batchSize = Math.round(context.sampleRate * BATCH_SECONDS);

    node.port.onmessage = ({ data }) => {
      pending.push(data.samples);
      pendingLength += data.samples.length;
      total += data.samples.length;

      if (listeners.onLevel) listeners.onLevel(data.level);
      if (listeners.onTime) listeners.onTime(total / context.sampleRate);

      if (pendingLength >= batchSize) flush();
    };

    source.connect(node);
  }

  /** Stop capturing and send whatever is left. Returns how long was recorded. */
  async function stop() {
    if (!isRecording()) return null;

    const rate = context.sampleRate;
    const seconds = total / rate;

    try { node.port.postMessage('stop'); } catch { /* already gone */ }
    source.disconnect();
    node.disconnect();
    stream.getTracks().forEach((track) => track.stop());
    await context.close();

    stream = context = node = source = null;
    listeners = {};

    await flush();              // the last fraction of a second
    total = 0;

    return { seconds };
  }

  /** Abandon the take without transcribing it. */
  async function cancel() {
    if (!isRecording()) return;
    try { node.port.postMessage('stop'); } catch { /* already gone */ }
    try { source.disconnect(); node.disconnect(); } catch { /* already gone */ }
    stream.getTracks().forEach((track) => track.stop());
    await context.close();
    stream = context = node = source = null;
    pending = [];
    pendingLength = 0;
    total = 0;
    listeners = {};
  }

  return { start, stop, cancel, isRecording, toPcm16, SAMPLE_RATE };
})();

window.Dictation = Dictation;
