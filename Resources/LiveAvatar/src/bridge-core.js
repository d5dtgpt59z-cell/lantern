// Only a short-lived Anam session token crosses the native/web boundary.
// Qwen, transcription, credential storage, and TTS remain native app services.
export function createPaigeAvatar({ createClient, AnamEvent, video, emit, setFetchSignal = () => {},
  makeMeter = createAudioMeter, clock = () => performance.now(),
  setIntervalFn = setInterval, clearIntervalFn = clearInterval,
  setTimeoutFn = setTimeout, clearTimeoutFn = clearTimeout }) {
  let current = null;
  let generation = 0;
  const report = (type, message) => emit({ type, ...(message ? { message } : {}) });
  const isCurrent = record => current === record && record.generation === generation;
  const schedule = (record, callback, milliseconds) => {
    const timer = setTimeoutFn(() => { record.timers.delete(timer); callback(); }, milliseconds);
    record.timers.add(timer);
    return timer;
  };
  async function dispose(record) {
    for (const timer of record.timers) clearTimeoutFn(timer);
    record.timers.clear();
    if (record.monitorTimer !== null) clearIntervalFn(record.monitorTimer);
    record.turn = null;
    record.cancelStartup?.(new Error("Live connection was cancelled."));
    record.abort.abort();
    // stopStreaming uses the native-minted session token to end the session.
    // Pending SDK fetches are aborted, but this final stop request must be allowed.
    setFetchSignal(null);
    try { await record.meter?.close(); } catch {}
    const tracks = video.srcObject?.getTracks?.() ?? [];
    video.pause?.();
    video.srcObject = null;
    let stopTimer;
    try {
      await Promise.race([
        Promise.resolve(record.client?.stopStreaming()),
        new Promise(resolve => { stopTimer = setTimeoutFn(resolve, 2500); }),
      ]);
    } catch {} finally { if (stopTimer !== undefined) clearTimeoutFn(stopTimer); }
    for (const track of tracks) track.stop();
  }
  async function stop(notify = true, message = null) {
    const record = current;
    current = null;
    generation += 1;
    if (record) await dispose(record);
    if (notify && record) report('closed', message);
  }
  async function fail(record, message) {
    if (!isCurrent(record)) return;
    await stop(false);
    report('error', message);
  }
  function finishTurn(record) {
    if (!isCurrent(record) || !record.turn) return;
    record.turn = null;
    report('speech-ended');
  }
  function sampleAudio(record) {
    if (!isCurrent(record) || !record.turn) return;
    const turn = record.turn;
    const now = clock();
    const energy = record.meter?.energy() ?? 0;
    if (energy > 0.003) {
      turn.lastSound = now;
      if (turn.firstSound === null) {
        turn.firstSound = now;
        report('speech-started');
      }
    }
    // Audio passthrough has no reliable SDK end-of-speech event. Use the known
    // PCM duration plus silence in the *returned* stream, never upload completion.
    if (turn.firstSound !== null && now - turn.firstSound >= turn.duration + 250 && now - turn.lastSound >= 450) {
      finishTurn(record);
    } else if (turn.firstSound === null && now - turn.sentAt > 15000) {
      void fail(record, 'Paige’s audio did not arrive. The live connection has ended; try again.');
    } else if (turn.firstSound !== null && now - turn.firstSound > turn.duration + 15000) {
      void fail(record, 'Paige’s audio stopped responding. The live connection has ended.');
    }
  }
  async function start(sessionToken) {
    if (typeof sessionToken !== 'string' || sessionToken.length < 20 || sessionToken.length > 16384) {
      throw new Error('A valid Anam session token is required.');
    }
    if (current) await stop(false);
    const record = { generation: ++generation, abort: new AbortController(), client: null,
      timers: new Set(), monitorTimer: null, meter: null, turn: null, ready: false, audioStream: null };
    current = record;
    setFetchSignal(record.abort.signal);
    // Independent of native UI state: no page can remain live past the free cap.
    schedule(record, () => { if (isCurrent(record)) void stop(true, 'The free three-minute session has ended.'); }, 180000);
    let rejectStartup;
    const startupFailure = new Promise((_, reject) => { rejectStartup = reject; });
    record.cancelStartup = rejectStartup;
    let sessionReady = false;
    let videoReady = false;
    let resolveReady;
    const ready = new Promise(resolve => { resolveReady = resolve; });
    const checkReady = () => { if (isCurrent(record) && sessionReady && videoReady) resolveReady(); };
    try {
      record.client = createClient(sessionToken, {
        disableInputAudio: true,
        metrics: { disableClientMetrics: true },
      });
      record.client.addListener(AnamEvent.SESSION_READY, () => { sessionReady = true; checkReady(); });
      record.client.addListener(AnamEvent.AUDIO_STREAM_STARTED, stream => { record.audioStream = stream; });
      record.client.addListener(AnamEvent.CONNECTION_CLOSED, () => {
        if (!isCurrent(record)) return;
        rejectStartup(new Error('Anam closed the connection.'));
        void stop(true, 'Anam ended the live connection.');
      });
      record.client.addListener(AnamEvent.TALK_STREAM_INTERRUPTED, () => finishTurn(record));
      schedule(record, () => rejectStartup(new Error('Anam connection timed out.')), 30000);
      await Promise.race([
        (async () => {
          await record.client.streamToVideoElement(video.id);
          if (!isCurrent(record)) throw new Error('Live connection was cancelled.');
          videoReady = true; checkReady();
          await ready;
        })(),
        startupFailure,
      ]);
      if (!isCurrent(record)) throw new Error('Live connection was cancelled.');
      const stream = record.audioStream ?? video.srcObject;
      if (!stream?.getAudioTracks?.().length) throw new Error('Anam did not return an audio stream.');
      record.meter = await Promise.race([makeMeter(stream, record.abort.signal), startupFailure]);
      if (!isCurrent(record)) { await record.meter?.close(); throw new Error('Live connection was cancelled.'); }
      record.monitorTimer = setIntervalFn(() => sampleAudio(record), 100);
      record.ready = true;
      video.muted = false;
      report('ready');
      return true;
    } catch (error) {
      if (isCurrent(record)) await stop(false);
      else { try { await record.client?.stopStreaming(); } catch {} }
      // Do not forward SDK error payloads: they can contain request credentials.
      throw new Error(error?.message === 'Live connection was cancelled.' ? error.message : 'Could not open Anam’s live connection. Check your connection, avatar, and free minutes.');
    }
  }
  async function sendAudio(base64) {
    const record = current;
    if (!record?.ready || !isCurrent(record)) throw new Error('The live avatar is not connected.');
    if (record.interrupting) throw new Error('Wait until Paige’s interruption finishes.');
    if (record.turn) throw new Error('Wait until Paige finishes speaking.');
    if (typeof base64 !== 'string' || !/^[A-Za-z0-9+/]*={0,2}$/.test(base64)) throw new Error('Invalid speech audio.');
    const binary = atob(base64);
    if (binary.length < 2 || binary.length % 2 || binary.length > 2880000) throw new Error('Speech audio must be PCM16 mono, no longer than 60 seconds.');
    const bytes = Uint8Array.from(binary, character => character.charCodeAt(0));
    const stream = record.client.createAgentAudioInputStream({ encoding: 'pcm_s16le', sampleRate: 24000, channels: 1 });
    record.turn = { sentAt: clock(), firstSound: null, lastSound: 0, duration: bytes.length / 48 };
    try {
      for (let offset = 0; offset < bytes.length; offset += 4800) stream.sendAudioChunk(bytes.subarray(offset, offset + 4800));
      stream.endSequence();
    } catch {
      await fail(record, 'Could not send Paige’s speech. The live connection has ended.');
      throw new Error('Could not send speech to Anam.');
    }
    return true;
  }
  function interrupt() {
    const record = current;
    if (!record?.ready) return;
    record.client.interruptPersona();
    finishTurn(record);
  }
  async function interruptAndWait() {
    const record = current;
    if (!record?.ready || !isCurrent(record)) return true;
    record.interrupting = true;
    record.turn = null;
    video.muted = true;
    record.client.interruptPersona();
    const started = clock();
    let lastSound = started;
    while (isCurrent(record)) {
      const now = clock();
      if ((record.meter?.energy() ?? 0) > 0.003) lastSound = now;
      if (now - lastSound >= 450) {
        record.interrupting = false;
        video.muted = false;
        return true;
      }
      if (now - started >= 4000) {
        await fail(record, 'Paige’s interrupted audio did not stop. The live connection has ended.');
        throw new Error('Interrupted audio did not stop.');
      }
      await new Promise(resolve => setTimeoutFn(resolve, 75));
    }
    throw new Error('Live connection was cancelled.');
  }
  return { start, sendAudio, interrupt, interruptAndWait, stop: () => stop(true) };
}

async function createAudioMeter(stream, signal) {
  const AudioContextType = globalThis.AudioContext ?? globalThis.webkitAudioContext;
  if (!AudioContextType) throw new Error('Live audio monitoring is unavailable.');
  const context = new AudioContextType();
  const abort = () => { void context.close().catch(() => {}); };
  signal?.addEventListener("abort", abort, { once: true });
  try {
    await context.resume();
    const source = context.createMediaStreamSource(stream);
    const analyser = context.createAnalyser();
    analyser.fftSize = 1024;
    const silentGain = context.createGain();
    silentGain.gain.value = 0;
    source.connect(analyser); analyser.connect(silentGain); silentGain.connect(context.destination);
    const samples = new Float32Array(analyser.fftSize);
    return {
      energy() {
        analyser.getFloatTimeDomainData(samples);
        let sum = 0;
        for (const sample of samples) sum += sample * sample;
        return Math.sqrt(sum / samples.length);
      },
      async close() { signal?.removeEventListener("abort", abort); source.disconnect(); analyser.disconnect(); silentGain.disconnect(); await context.close(); },
    };
  } catch (error) { signal?.removeEventListener("abort", abort); await context.close(); throw error; }
}
