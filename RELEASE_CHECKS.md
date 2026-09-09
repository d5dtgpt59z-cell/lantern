# 1.0 standalone release candidate

Verified locally on an M5 Mac with 16 GB memory:

- Swift release build and Xcode Release build with signing disabled.
- Bundled, checksum-pinned Ollama v0.22.0 launches on loopback port 11435; no dependency on `/Applications/Ollama.app`.
- A real Qwen reply through the installed bundled-engine UI.
- Existing conversation decoding and existing model discovery.
- First-run model-manager UI using a separate test model manifest directory.
- In-app model download progress, pause, and resume.
- Engine startup pruning is disabled to protect shared model caches.
- Native engine supervisor terminates the engine when Lantern exits.
- Model selection and manual update check; no-release response shown correctly.
- Native command helper: ordinary commands, credential denial, network denial, protected Git metadata, output cap, timeout, cancellation of descendants.
- Disk-image packaging and local signature verification.

Still required before a public binary release:

- Developer ID signing, notarization, and stapling using the owner's Apple Developer account.
- End-to-end installation on a separate supported Mac without developer tools or Ollama. Local isolated-storage checks are not a substitute for that machine.
- Verify the final signed package's chat, attachments, commands, quit/relaunch, and update replacement.

The source is open source. The locally generated DMG is a release candidate, not a notarized installer. Optional Draw Things image generation still has a separate setup. Updates are checked manually; there is no automatic installer.
