import Foundation

enum ChatModel: String, CaseIterable, Identifiable {
    case qwen, rpmax
    var id: String { rawValue }
    var title: String { self == .qwen ? "Qwen" : "RPMax" }
    var subtitle: String { self == .qwen ? "Qwen 3.5 · 9B" : "RPMax · Mistral Nemo 12B" }
    var ollamaName: String { self == .qwen ? "qwen3.5:9b" : "hf.co/ArliAI/Mistral-Nemo-12B-ArliAI-RPMax-v1.2-GGUF:Q4_K_M" }
    var supportsTools: Bool { self == .qwen }
    var supportsImages: Bool { self == .qwen }
    var contextLength: Int { self == .qwen ? 8192 : 4096 }
}
