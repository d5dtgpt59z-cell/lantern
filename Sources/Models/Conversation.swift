import Foundation
struct Message: Codable, Identifiable {
    var id = UUID()
    var role: String
    var content: String
    var attachments: [Attachment]? = nil
    var tool_calls: [ToolCall]? = nil
    var tool_name: String? = nil
    var modelName: String? = nil
    var generatedImage: GeneratedImage? = nil
}
struct GeneratedImage: Codable {
    var fileName: String
    var prompt: String
    var model: String
    var width: Int
    var height: Int
    var url: URL? {
        guard !fileName.isEmpty, fileName != ".", fileName != "..",
              URL(fileURLWithPath: fileName).lastPathComponent == fileName else { return nil }
        return Personalization.directory.appendingPathComponent("Images", isDirectory: true).appendingPathComponent(fileName)
    }
}
struct Conversation: Codable, Identifiable {
    var id = UUID()
    var title = "New conversation"
    var messages: [Message] = []
    var updated = Date()
    var workspacePath: String? = nil
}
