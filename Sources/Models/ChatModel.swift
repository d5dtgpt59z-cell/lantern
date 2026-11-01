import Foundation

enum ChatModel: String, CaseIterable, Identifiable {
    case qwen
    var downloadGB: Double { 5.8 }
    var summary: String { "Local agent · text, documents, tools and drawing" }
    var id: String { rawValue }
    var title: String { "Qwen 3.8 Uncensored" }
    var subtitle: String { "Qwen 3.8 · 9B Uncensored" }
    var ollamaName: String { "hf.co/mradermacher/Qwen3.8-9B-Distill-uncensored-heretic-GGUF:Q4_K_M" }
    var supportsTools: Bool { true }
    var supportsImages: Bool { false }
    var contextLength: Int { 8192 }
}
