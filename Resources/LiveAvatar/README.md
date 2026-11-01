# PAIGE live video renderer

`index.html` and `avatar.js` are bundled inside PAIGE, not loaded from a CDN. The compiled bundle uses `@anam-ai/js-sdk` **4.29.1**. Dependencies and bundler are pinned in `package-lock.json`.

Run `./script/build_live_avatar.sh` from the PAIGE project to rebuild the JavaScript and run its behavioral tests. Build dependencies live in `.build/live-avatar/dependencies`. Include `index.html`, `avatar.js`, and `THIRD-PARTY-NOTICES.txt` in `Contents/Resources/LiveAvatar`.

The native bridge accepts an ephemeral Anam session token and PCM16 little-endian mono speech at 24 kHz. It never receives API keys, microphone audio, Qwen's endpoint, conversation history, or tool access. Microphone capture is disabled in both SDK configuration and the WebKit capture-permission delegate.

The native app controls transcription, Qwen, TTS and session settings. JavaScript independently closes the session at 180 seconds. Ending a session aborts in-flight SDK requests, stops the server session, releases media tracks, and clears the video. No automatic new session is created.

Audio passthrough has no dedicated reliable SDK playback-end event. The bridge watches the returned audio and waits at least the uploaded PCM duration plus a silent tail before telling the native app to listen again. It closes the session on missing/stalled playback. This is conservative turn-taking; acoustic echo cancellation and hands-free interruptions still require runtime verification.
