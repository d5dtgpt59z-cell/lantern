# Restoring the local inference runtime

This GitHub snapshot contains PAIGE's application source, helper source, scripts, UI resources and third-party license notices. The downloaded runtime binaries under `Vendor/Engine/`, model weights and local build/release artifacts are omitted. This source snapshot is not a signed installer.

The existing `script/prepare_engine.sh` restores the complete runtime from the official Ollama macOS release. It pins version `0.40.8`, verifies SHA-256 `29fce20c736f62aa8885b1e83552c5fd8dcc63edc5ffc1b47f2de591a06cde44`, checks that both `ollama` and `llama-server` exist, and replaces the runtime directory atomically. The download cache and rollback copies remain under the ignored `work/` directory. Do not substitute a partial set of copied libraries.

On Apple Silicon macOS with Xcode command line tools:

```sh
./script/prepare_engine.sh
./script/build_and_run.sh --build
```

The normal Xcode post-build step runs `script/embed_runtime.sh`, which invokes the same preparation script, embeds the complete runtime and builds the Swift command, inference and image supervisor helpers. Select your signing team as described in `SIGNING.md` for distribution work. Model weights install separately through the app; the optional local image engine also installs separately as described in `README.md`.

Local `release/` documentation, signed packages and historical verification captures were omitted from this filtered snapshot. Historical links to those artifacts in the README describe the original local workspace. Restoring the runtime and compiling this snapshot were not executed as part of the GitHub upload preparation.
