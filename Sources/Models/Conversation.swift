import Foundation
struct Message: Codable, Identifiable {
    var id = UUID()
    var role: String
    var content: String
    var attachments: [Attachment]? = nil
    var tool_calls: [ToolCall]? = nil
    var tool_name: String? = nil
    var modelName: String? = nil
}
struct Conversation: Codable, Identifiable {
    var id = UUID()
    var title = "New conversation"
    var messages: [Message] = []
    var updated = Date()
    var workspacePath: String? = nil
}
