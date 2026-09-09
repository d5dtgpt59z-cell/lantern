# Lantern

A native local chat app for this Mac, using Qwen 3.5 9B through Ollama.

## Use

Open Lantern from Applications or click its Dock icon. It starts the local engine automatically. When the status says Ready, type a message and click Send, or press Command–Return. Return adds a new line. Click New conversation to change topics. Copy buttons are available on answers and code blocks. Stop interrupts a reply.

Chats are saved on this Mac in `~/Library/Application Support/Lantern/conversations.json`. The model lives in `~/.ollama/models`. Keep Ollama installed in Applications; Lantern uses its engine without requiring its chat window.

The downloaded model runs without internet or a cloud account. Chat mode has no tools. Choose a specific project folder to enable project tools: list, read and search ordinary text files; propose a file replacement; request a shell command. Every file write and command requires its own approval. Rejecting an action stops that run. File replacements retain a backup in Lantern's Application Support/Backups folder. Commands can modify or delete project files and are not automatically undoable.

Reads block hidden and common credential filenames, path traversal and symlinks escaping the selected project. Commands use macOS sandbox-exec with restricted filesystem access, no network, a stripped environment, 30-second timeout, and 64 KB output cap. Commands cannot modify .git metadata. Some development tools will not work with these restrictions. This is a constrained local helper, not a security-audited VM or full Codex equivalent. It does not inherit Codex history or browse the web. Project access is cleared on relaunch; switching to a conversation from another project disables tools. Its answers can be less capable than large cloud models.

Configured with an 8,192-token context, thinking disabled for responsive replies, and a 3,072-token response limit. Start a fresh chat for a new topic. The model is released from memory after five idle minutes by Ollama. Quit heavy apps if memory gets tight.

## Build

Run `./script/build_and_run.sh` to build and launch. Requires Apple’s Swift toolchain. The resulting app is in `dist/Lantern.app`. It is locally ad-hoc signed for this Mac, not notarized for public distribution.

## Pip

Pip is Lantern's in-app animated moth companion. Click to greet, drag to reposition, right-click to hide or reset, or use the paw button. Dragging uses a fixed window coordinate space, a lifted appearance and hand cursor, then gently snaps to an 8-point grid. Its position is remembered between launches and adapts to window resizing. Right-click and choose Back to perch to reset. It reacts to generation and approval states and respects macOS Reduce Motion. It stays within Lantern's window.

## Verification

Qwen 3.5 9B ran with 100% GPU use and an 8K context on this M5 / 16 GB Mac. A 204-token coding response measured about 19.45 tokens/second (one sample, not a general benchmark). Live UI tests covered reading a file, approving a replacement, approving a harmless command, and rejecting a new file. Restriction checks covered out-of-project reads/writes, symlink escapes, hidden secrets, network access, another process's environment, output limits, stale approvals, unapproved writes, and command timeout.

Pip uses 32 distinct transparent PNG animation frames: 8 each for idle, working, happy and waiting. Each frame is 256 × 256 pixels with a common (128, 128) anchor. The accompanying atlas is an evenly spaced 8 × 4 grid. Artwork was generated using the built-in image tool and cut out locally with Apple Vision plus edge cleanup, as approved. Frame poses are deterministic layered animation from that canonical artwork.

### Photos and files
Use **Attach** in the composer or drop files onto it. Supports photos, UTF-8 text/code, and PDFs with selectable text. Up to four attachments per message, 20 MB per source file, and 12,000 extracted document characters total. Images are resized locally to a maximum 1280-pixel edge. Attachments are stored with local conversations and sent only to the local model. Scanned PDFs should be supplied as page images. Attaching a file does not enable tools or authorize changing its original.


## Local images

The Image button beside Attach opens the local image studio. It connects only to Draw Things at `127.0.0.1:7860`; HTTP redirects and non-local-model identifiers are rejected. In Draw Things, choose Settings → Advanced → API Server. Select HTTP, enable Server Online, use port 7860 and IP 127.0.0.1, and keep Bridge Mode off. Select a downloaded local model.

The panel sends the entered prompt directly, generates one square PNG, saves it under `~/Library/Application Support/Lantern/Images`, and offers Save PNG, Show in Finder, and Attach to chat. Chat models are unloaded before rendering to free unified memory. LoRAs, controls, upscaling and refiners are cleared for these requests; other sampling settings come from Draw Things. No prompt-content filter is added by Lantern. Model behavior is not guaranteed unrestricted.

Verification: release build and installed image-panel UI checked. A 512 × 512 PNG was generated through the installed Lantern image panel using local FLUX.1 Schnell, displayed successfully, and saved to the Images folder. The Draw Things listener was verified bound to 127.0.0.1:7860 with Bridge Mode off.


## Chat model picker

Use Model beneath the conversation title to choose Qwen or RPMax. The selection is remembered across launches and each new assistant reply records the answering model. Switching does not erase the conversation. Only one chat model is kept loaded.

Qwen uses qwen3.5:9b and supports photos and project tools. RPMax uses Mistral Nemo 12B ArliAI RPMax v1.2 Q4_K_M, with a 4096-token context to fit the 16 GB Mac. RPMax is text-only in Lantern: file text can be attached, photos need Qwen, and project tools run only with Qwen. The Image panel uses Draw Things independently of either chat model.

## License

Lantern is open source under the [MIT License](LICENSE). Model weights and third-party applications such as Ollama and Draw Things are not included and retain their own licenses.
