import Foundation
@main struct ConversationChecks {
    @MainActor static func main() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("paige-chat-check-" + UUID().uuidString)
        let store = ChatStore(storageDirectory: dir)
        let first = store.selected!
        store.conversations[0].messages.append(Message(role: "user", content: "Disposable test"))
        store.generating = true
        store.newChat()
        precondition(!store.generating && store.selected != first && store.conversations.count == 2)
        store.deleteConversation(first)
        precondition(store.conversations.count == 1 && !store.conversations.contains { $0.id == first })
        let restored = ChatStore(storageDirectory: dir)
        precondition(restored.conversations.count == 1 && restored.selected == store.selected)
        restored.deleteConversation(restored.selected!)
        precondition(restored.conversations.count == 1 && restored.current!.messages.isEmpty)
        let readOnlyNames = AgentTools.schemas(for: .readOnly).compactMap { ($0["function"] as? [String: Any])?["name"] as? String }
        precondition(readOnlyNames == ["list_files", "read_file", "search_files"])
        precondition(AgentTools.schemas(for: .askFirst).count == 7)
        precondition(AgentTools.schemas(for: .fullProject).count == 7)
        print("PASS: new chat cancels busy state; delete persists; deleting last chat leaves a fresh conversation")
        print("PASS: read-only hides mutation tools; ask-first and full-project expose the complete project tool set")
    }
}
