import test from 'node:test';
import assert from 'node:assert/strict';
import { createPaigeAvatar } from './bridge-core.js';

function harness({ delayedStart = false } = {}) {
  const events = [];
  const callbacks = new Map();
  const timeouts = new Map();
  const intervals = new Map();
  let now = 0, timer = 0, energy = 0, stopped = 0, ended = 0, options, token;
  let resolveStart;
  const audioTrack = { stop() {} };
  const stream = { getAudioTracks: () => [audioTrack], getTracks: () => [audioTrack] };
  const video = { id: 'avatar', srcObject: stream, pause() {} };
  const client = {
    addListener: (type, fn) => callbacks.set(type, fn),
    async streamToVideoElement() {
      if (delayedStart) await new Promise(resolve => { resolveStart = resolve; });
      callbacks.get('audio')?.(stream);
      callbacks.get('session')?.('test-session');
    },
    async stopStreaming() { stopped++; callbacks.get('closed')?.('normal'); },
    createAgentAudioInputStream(config) {
      assert.deepEqual(config, { encoding: 'pcm_s16le', sampleRate: 24000, channels: 1 });
      return { sendAudioChunk(bytes) { assert.ok(bytes.length <= 4800); }, endSequence() { ended++; } };
    },
    interruptPersona() {},
  };
  const avatar = createPaigeAvatar({
    createClient: (value, opts) => { token = value; options = opts; return client; },
    AnamEvent: { SESSION_READY: 'session', AUDIO_STREAM_STARTED: 'audio', CONNECTION_CLOSED: 'closed', TALK_STREAM_INTERRUPTED: 'interrupt' },
    video, emit: event => events.push(event), clock: () => now,
    makeMeter: async () => ({ energy: () => energy, async close() {} }),
    setTimeoutFn: (fn, ms) => { const id = ++timer; timeouts.set(id, { fn, ms }); return id; },
    clearTimeoutFn: id => timeouts.delete(id),
    setIntervalFn: fn => { const id = ++timer; intervals.set(id, fn); return id; },
    clearIntervalFn: id => intervals.delete(id),
  });
  return { avatar, events, callbacks, timeouts, video, get stopped() { return stopped; }, get ended() { return ended; },
    get options() { return options; }, get token() { return token; },
    sample(time, value) { now = time; energy = value; for (const fn of intervals.values()) fn(); },
    finishStartup() { resolveStart(); },
  };
}
const token = 'an-ephemeral-session-token-value';
test('audio-only configuration never enables browser microphone or exposes an API key', async () => {
  const h = harness(); await h.avatar.start(token);
  assert.equal(h.token, token);
  assert.deepEqual(h.options, { disableInputAudio: true, metrics: { disableClientMetrics: true } });
  assert.deepEqual(h.events, [{ type: 'ready' }]);
  await h.avatar.stop();
});
test('speech completes after returned playback duration plus silence, never after upload', async () => {
  const h = harness(); await h.avatar.start(token);
  await h.avatar.sendAudio(Buffer.alloc(48000).toString('base64'));
  assert.equal(h.ended, 1);
  assert.equal(h.events.some(event => event.type === 'speech-ended'), false);
  h.sample(100, .1); h.sample(200, .1); h.sample(900, 0);
  assert.equal(h.events.some(event => event.type === 'speech-ended'), false);
  h.sample(1400, 0);
  assert.equal(h.events.filter(event => event.type === 'speech-ended').length, 1);
  await h.avatar.stop();
});
test('end during startup prevents a late ready event and closes the client', async () => {
  const h = harness({ delayedStart: true });
  const starting = h.avatar.start(token);
  const rejection = assert.rejects(starting, /cancelled/);
  await h.avatar.stop(); h.finishStartup(); await rejection;
  assert.equal(h.events.some(event => event.type === 'ready'), false);
  assert.ok(h.stopped >= 1);
});
test('independent 180-second guard ends the session without another connection', async () => {
  const h = harness(); await h.avatar.start(token);
  const guard = [...h.timeouts.values()].find(value => value.ms === 180000);
  guard.fn(); await new Promise(resolve => setImmediate(resolve));
  assert.ok(h.stopped >= 1);
  assert.ok(h.events.some(event => event.type === 'closed' && /three-minute/.test(event.message)));
  await assert.rejects(h.avatar.sendAudio('AAAA'), /not connected/);
});
test('malformed PCM and overlapping turns are rejected', async () => {
  const h = harness(); await h.avatar.start(token);
  await assert.rejects(h.avatar.sendAudio('!!'), /Invalid speech/);
  await assert.rejects(h.avatar.sendAudio(Buffer.alloc(3).toString('base64')), /PCM16/);
  await h.avatar.sendAudio(Buffer.alloc(4800).toString('base64'));
  await assert.rejects(h.avatar.sendAudio('AAAA'), /finishes speaking/);
  h.avatar.interrupt();
  assert.equal(h.events.filter(event => event.type === 'speech-ended').length, 1);
  await h.avatar.stop();
});
test('silent or lost returned audio fails closed, preserving microphone turn safety', async () => {
  const h = harness(); await h.avatar.start(token);
  await h.avatar.sendAudio(Buffer.alloc(4800).toString('base64'));
  h.sample(16000, 0); await new Promise(resolve => setImmediate(resolve));
  assert.ok(h.events.some(event => event.type === 'error' && /did not arrive/.test(event.message)));
  assert.equal(h.events.some(event => event.type === 'speech-ended'), false);
  assert.ok(h.stopped >= 1);
});
test('interruption mutes output and waits for returned silence without auto-rearming mic', async () => {
  const h = harness(); await h.avatar.start(token);
  await h.avatar.sendAudio(Buffer.alloc(48000).toString('base64'));
  h.sample(100, .1);
  const ending = h.avatar.interruptAndWait();
  assert.equal(h.video.muted, true);
  await assert.rejects(h.avatar.sendAudio('AAAA'), /interruption finishes/);
  h.sample(200, .1);
  let poll = [...h.timeouts.values()].find(value => value.ms === 75); poll.fn();
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(h.video.muted, true);
  h.sample(700, 0);
  poll = [...h.timeouts.values()].filter(value => value.ms === 75).at(-1); poll.fn();
  await ending;
  assert.equal(h.video.muted, false);
  assert.equal(h.events.filter(event => event.type === 'speech-ended').length, 0);
  await h.avatar.stop();
});
