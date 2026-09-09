# Lantern

A free, open-source Mac assistant with local chat, photos and files, approved project tools, and Pip the animated moth.

**Standalone 1.0 release candidate.** Apple Silicon · macOS 15+ · 16 GB memory minimum. Public signed/notarized downloads are pending. Source builds and local test packages are available; do not treat an ad-hoc signature as a production installer.

## Everyday use

Open Lantern, download the recommended Qwen model, and start chatting. The inference engine is included: users do not need Ollama, Python, Terminal, or an account. Internet is needed for model downloads and optional update checks. Chat works offline after setup.

- **Manage models:** download/resume, pause, select, or remove models. The app checks available storage and remembers the selected model. Existing Ollama downloads are reused when found at first launch. Shared models remain shared: removing one also removes it from Ollama.
- **Quick / Think:** Qwen can answer directly or spend longer reasoning. Think may take substantially longer. RPMax remains a text-only creative option.
- **Attach:** photos, UTF-8 text/code, or PDFs with selectable text; four attachments, 20 MB each, 12,000 extracted document characters total. Images are resized locally. Scanned PDFs can be attached as page images.
- **Projects:** select a specific folder. Reads are scoped to it; every file replacement and shell command needs approval. Rejecting stops that action. File replacements retain local backups. Commands can modify/delete files and are not automatically undoable.
- **Pip:** click, drag, hide, or reset the companion. Motion respects Reduce Motion and dragging snaps to an 8-point grid.
- **Updates:** Manage models → Check for updates. Downloads are offered through GitHub Releases; replacing the app preserves local data. No automatic updater is included.

## Models

| Model | Download | Capabilities in Lantern |
|---|---:|---|
| Qwen 3.5 9B Q4_K_M | ~6.6 GB | Recommended; text, images, project tools; 8K context |
| ArliAI RPMax Nemo 12B v1.2 Q4_K_M | ~7.5 GB | Optional creative text chat; 4K context |

Model files require additional working memory. Keep other large models and image-generation workloads unloaded on 16 GB Macs. Each model retains its upstream license; no model weights are included in this repository.

## Optional images

The Image panel is an optional integration requiring a separate Draw Things installation and downloaded image model. In Draw Things, enable its HTTP API at `127.0.0.1:7860`, with Bridge Mode off. The panel releases Lantern's chat model before rendering. Image generation is not part of the standalone first-run setup.

## Privacy and constraints

Conversations and attachments are stored in `~/Library/Application Support/Lantern/conversations.json`; images and backups are under the same application-support folder. App updates preserve those files. If saved chats cannot be decoded, Lantern refuses to overwrite them.

The bundled engine listens only on `127.0.0.1:11435`, with cloud features disabled and a separate engine home. New installations store models under Lantern's application-support folder; existing Ollama models can be reused. Prompts and attachments are sent to loopback only, with redirects rejected. Model downloads contact the model registry/provider; manual update checks contact GitHub.

Tools block path escapes and common credential filenames. The native command supervisor uses macOS sandbox-exec, a stripped environment, no network, a 30-second timeout, a 64 KB output cap, and process-group cancellation. Git metadata writes are blocked. This is a constrained helper, not a security-audited VM; review commands before approving them. Tool use remains Qwen-only in this release.

## Build and sign

Open `Lantern.xcodeproj` in Xcode and select your team. See [SIGNING.md](SIGNING.md) for archive, Developer ID, notarization, and distribution steps.

For a local build using Apple's Swift tools:

```sh
./script/build_and_run.sh
# Build only:
./script/build_and_run.sh --build
# Package the local test app:
./script/package_dmg.sh
```

The build downloads Ollama v0.22.0 from its official GitHub release and verifies the pinned SHA-256. Runtime binaries are ignored by Git. Third-party notices are in `Resources/ThirdParty`. To regenerate the Xcode project after changing `project.yml`, run `xcodegen generate`.

## License

Lantern is [MIT licensed](LICENSE). The bundled Ollama engine and its dependencies retain their licenses in `Resources/ThirdParty`. Model weights and optional third-party applications retain their own licenses. Pip artwork is AI-generated with locally authored animation; 32 transparent PNG frames use a common anchor and evenly spaced atlas.
