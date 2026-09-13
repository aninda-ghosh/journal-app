/**
 * Recording a ramble.
 *
 * Captures the microphone as 16 kHz mono PCM and streams it out in small
 * batches while you're still talking, so words can come back live rather than
 * after a wait. Nothing is written to disk: the samples pass through memory,
 * become text, and are gone.
 *
 * 16-bit signed little-endian is what the transcriber reads, and 16 kHz is
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
  let sending = null;         // the send in flight, so batches queue rather than drop

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

  /**
   * Hand a batch to the transcriber.
   *
   * Sends are chained rather than skipped: an earlier version returned early
   * while a send was in flight, which quietly dropped whatever had been said
   * since — including, at `stop()`, the last quarter-second of the sentence.
   */
  function flush() {
    if (pendingLength === 0) return sending || Promise.resolve();

    const blocks = pending;
    const length = pendingLength;
    pending = [];
    pendingLength = 0;

    const handlers = listeners;
    sending = (sending || Promise.resolve())
      .then(() => window.journal.dictationAudio(toPcm16(blocks, length)))
      .catch((err) => { if (handlers.onError) handlers.onError(err); });

    return sending;
  }

  /** Let go of the microphone and the audio graph, however we got here. */
  async function release() {
    try { if (node) node.port.postMessage('stop'); } catch { /* already gone */ }
    try { if (source) source.disconnect(); } catch { /* already gone */ }
    try { if (node) node.disconnect(); } catch { /* already gone */ }
    if (stream) stream.getTracks().forEach((track) => track.stop());
    if (context && context.state !== 'closed') {
      try { await context.close(); } catch { /* already closing */ }
    }
    stream = context = node = source = null;
  }

  async function start(handlers = {}) {
    if (isRecording()) return;
    listeners = handlers;
    pending = [];
    pendingLength = 0;
    total = 0;
    sending = null;

    let audioConstraints = {
      channelCount: 1,
      echoCancellation: true,
      noiseSuppression: true,
      autoGainControl: true
    };

    // If AirPods or a Bluetooth microphone is connected to macOS, prioritize it
    // over the built-in mic.
    try {
      if (navigator.mediaDevices && navigator.mediaDevices.enumerateDevices) {
        const devices = await navigator.mediaDevices.enumerateDevices();
        const btMic = devices.find(
          (d) => d.kind === 'audioinput' && /airpod|bluetooth|headset|wireless/i.test(d.label)
        );
        if (btMic && btMic.deviceId) {
          audioConstraints.deviceId = { ideal: btMic.deviceId };
        }
      }
    } catch {
      // Fallback cleanly to default input device
    }

    stream = await navigator.mediaDevices.getUserMedia({ audio: audioConstraints });

    // From here the microphone is live, so any failure has to give it back.
    // Half-started is worse than not started at all: the recording light stays
    // on, and isRecording() would say we're listening when nothing is.
    try {
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
    } catch (err) {
      await release();
      listeners = {};
      throw err;
    }
  }

  /** Stop capturing and send whatever is left. Returns how long was recorded. */
  async function stop() {
    if (!isRecording()) return null;

    const seconds = total / context.sampleRate;

    await release();
    await flush();              // the last fraction of a second

    listeners = {};
    pending = [];
    pendingLength = 0;
    total = 0;
    sending = null;

    return { seconds };
  }

  /** Abandon the take without transcribing it. */
  async function cancel() {
    if (!isRecording()) return;
    await release();
    pending = [];
    pendingLength = 0;
    total = 0;
    sending = null;
    listeners = {};
  }

  return { start, stop, cancel, isRecording, toPcm16, SAMPLE_RATE };
})();

window.Dictation = Dictation;
