import Foundation
struct ToolCall: Codable {
    struct Function: Codable { var name: String; var arguments: [String: String] }
    var function: Function
}
struct ApprovalRequest: Identifiable {
    let id = UUID()
    let call: ToolCall
    let title: String
    let detail: String
    let before: String?
    let after: String?
}
