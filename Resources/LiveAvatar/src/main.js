import { createClient, AnamEvent } from '@anam-ai/js-sdk';
import { createPaigeAvatar } from './bridge-core.js';
const video = document.getElementById('avatar');
const status = document.getElementById('status');
const play = document.getElementById('play');
let fetchSignal = null;
const originalFetch = globalThis.fetch.bind(globalThis);
// Closing a session aborts SDK requests still starting. The subsequent SDK stop
// call is allowed so established server sessions are explicitly closed.
globalThis.fetch = (input, init = {}) => {
  if (!fetchSignal) return originalFetch(input, init);
  const controller = new AbortController();
  const signals = [fetchSignal, init.signal].filter(Boolean);
  for (const signal of signals) {
    if (signal.aborted) controller.abort();
    else signal.addEventListener('abort', () => controller.abort(), { once: true });
  }
  return originalFetch(input, { ...init, signal: controller.signal });
};
function emit(event) {
  if (event.type === 'ready') status.textContent = '';
  if (event.type === 'closed') status.textContent = event.message ?? 'Live connection ended.';
  if (event.type === 'error') status.textContent = event.message;
  globalThis.webkit?.messageHandlers?.paigeLive?.postMessage(event);
}
const avatar = createPaigeAvatar({ createClient, AnamEvent, video, emit,
  setFetchSignal: signal => { fetchSignal = signal; } });
globalThis.paigeAvatar = {
  async start(token) { status.textContent = 'Connecting to Paige…'; return avatar.start(token); },
  sendAudio: audio => avatar.sendAudio(audio),
  interrupt: () => avatar.interrupt(),
  interruptAndWait: () => avatar.interruptAndWait(),
  stop: () => avatar.stop(),
};
video.addEventListener('play', () => play.classList.remove('visible'));
video.addEventListener('pause', () => { if (video.srcObject) play.classList.add('visible'); });
play.addEventListener('click', async () => { try { await video.play(); play.classList.remove('visible'); } catch { emit({ type: 'error', message: 'Live audio could not play. End Live and try again.' }); } });
window.addEventListener('pagehide', () => { void avatar.stop(); });
emit({ type: 'page-ready' });
