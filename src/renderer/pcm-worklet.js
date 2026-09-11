/**
 * Collects raw microphone samples off the main thread.
 *
 * A long ramble is a lot of audio, and doing this on the main thread would make
 * the interface stutter exactly while you're talking. The worklet just forwards
 * every block of samples, plus a loudness reading so the interface can show
 * that it's actually hearing you.
 */

class PCMCollector extends AudioWorkletProcessor {
  constructor() {
    super();
    this.running = true;
    this.port.onmessage = (event) => {
      if (event.data === 'stop') this.running = false;
    };
  }

  process(inputs) {
    const channel = inputs[0] && inputs[0][0];
    if (!channel) return this.running;

    // Copy: the underlying buffer is reused by the audio engine.
    const samples = new Float32Array(channel);

    let sum = 0;
    for (let i = 0; i < samples.length; i++) sum += samples[i] * samples[i];

    this.port.postMessage({
      samples,
      level: Math.sqrt(sum / samples.length)
    }, [samples.buffer]);

    return this.running;
  }
}

registerProcessor('pcm-collector', PCMCollector);
