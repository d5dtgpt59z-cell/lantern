# Bundled runtime notices

PAIGE bundles the complete official Ollama v0.40.8 macOS runtime payload, including its llama-server and llama-quantize helpers. The release archive is [ollama-darwin.tgz](https://github.com/ollama/ollama/releases/download/v0.40.8/ollama-darwin.tgz), SHA-256 `29fce20c736f62aa8885b1e83552c5fd8dcc63edc5ffc1b47f2de591a06cde44`.

The component license and notice files here were supplied with that release. `OLLAMA_LICENSE` comes from the [v0.40.8 source license](https://github.com/ollama/ollama/blob/v0.40.8/LICENSE). The existing `METAL_CPP_LICENSE.txt` notice is also retained. Ollama pins llama.cpp to `b11738` in this release; its license and bundled dependency notices are included separately.

The local application build signs the runtime executables and libraries for its app bundle. Model weights are installed separately and retain their own upstream licenses.
