# PAIGE

Lantern is now PAIGE — Personal AI Guide & Engineer. The current direct-distribution build adds approved internet, browser, Mac-control and self-development tools. See [PAIGE capabilities](release/PAIGE.md) and [current verification](release/PAIGE_CHECKS.md). Legacy internal names and storage paths remain for compatibility.

# Lantern

A free, open-source Mac assistant with local chat, documents, image generation, approved project tools, and Pip the animated moth.

**Standalone 1.0 release candidate.** Apple Silicon · macOS 15+ · 16 GB memory minimum. Public signed/notarized downloads are pending. Source builds and local test packages are available; do not treat an ad-hoc signature as a production installer.

## Everyday use

Open Lantern, download the recommended Qwen model, and start chatting. The inference engine is included: users do not need Ollama, Python, Terminal, or an account. Internet is needed for model downloads and optional update checks. Chat works offline after setup.

- **Manage models:** download/resume, pause, select, or remove models. The app checks available storage and remembers the selected model. Existing Ollama downloads are reused when found at first launch. Shared models remain shared: removing one also removes it from Ollama.
- **Quick / Think:** Qwen can answer directly or spend longer reasoning. Think may take substantially longer.
- **Attach:** UTF-8 text/code or PDFs with selectable text; four attachments, 20 MB each, 12,000 extracted document characters total. The uncensored chat model cannot inspect photos or scanned pages. Local image generation remains available separately.
- **Projects:** select a specific folder. Reads are scoped to it; every file replacement and shell command needs approval. Rejecting stops that action. File replacements retain local backups. Commands can modify/delete files and are not automatically undoable.
- **Pip:** click, drag, hide, or reset the companion. Motion respects Reduce Motion and dragging snaps to an 8-point grid.
- **Updates:** Manage models → Check for updates. Downloads are offered through GitHub Releases; replacing the app preserves local data. No automatic updater is included.

## Models

| Model | Download | Capabilities in Lantern |
|---|---:|---|
| Qwen 3.8 9B Distill Uncensored Heretic Q4_K_M | ~5.8 GB | Text, documents, project tools, Quick/Think; 8K context |

The [installed community model](https://huggingface.co/mradermacher/Qwen3.8-9B-Distill-uncensored-heretic-GGUF) is a distilled, uncensored derivative distributed under the Qwen 3.8 name; it is not an official Qwen 3.8 release. This text-only checkpoint does not inspect photos. DreamShaper image generation is a separate local model.

Model files require additional working memory. Keep other large models and image-generation workloads unloaded on 16 GB Macs. Each model retains its upstream license; no model weights are included in this repository.

## Optional images

PAIGE can make new images directly in a conversation: ask "Make an image of a red fox in a snowy forest", use `/image` followed by a description, or select the Image toggle and type a prompt. The installed local backend uses DreamShaper 8 through stable-diffusion.cpp, with no Draw Things dependency or hosted image service. The chat model unloads before each render; the native renderer exits afterward to release its memory. Stop terminates rendering before another model may start. Generated PNGs and prompt metadata are saved under `~/Library/Application Support/Lantern/Images` and remain visible in the saved conversation, with Save PNG and Finder actions.

Image-engine files are installed separately under `~/Library/Application Support/Lantern/ImageEngine`: `bin/sd-cli`, its native library, and the DreamShaper 8 model checkpoint. The installation manifest records upstream revisions and checksums. This machine uses the smaller Stable Diffusion 1.5 model at 512 pixels by default for its 16 GB unified memory. Model files are not bundled into the app or this source repository. The local rendering path adds no content-filter stage or language-model refusal gate; output behavior depends on the image model's training and the prompt. DreamShaper retains its creator’s terms and the underlying Stable Diffusion CreativeML OpenRAIL-M license; see the installed provenance and license files.

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

The build downloads Ollama v0.40.8 from its official GitHub release and verifies the pinned SHA-256. This runtime includes llama-server support for the model's MTP layers. An outdated runtime is replaced as a complete directory, with the previous payload retained under `work/engine-backups` for rollback. Runtime binaries are ignored by Git. Third-party notices are in `Resources/ThirdParty`. To regenerate the Xcode project after changing `project.yml`, run `xcodegen generate`.

## License

Lantern is [MIT licensed](LICENSE). The bundled Ollama engine and its dependencies retain their licenses in `Resources/ThirdParty`. Model weights and optional third-party applications retain their own licenses. Pip artwork is AI-generated with locally authored animation; 32 transparent PNG frames use a common anchor and evenly spaced atlas.

## GitHub source snapshot

Downloaded inference binaries, model weights and local release artifacts are omitted. See [SOURCE-RESTORE.md](SOURCE-RESTORE.md) for the pinned, checksum-verified runtime restoration path before building.
