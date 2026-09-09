import SwiftUI
import AppKit
@MainActor final class ChatStore: ObservableObject {
    @Published var conversations: [Conversation] = []
    @Published var selected: UUID? { didSet { if oldValue != selected { attachments = [] }; if current?.workspacePath != workspace?.path { workspace = nil } } }
    @Published var model: ChatModel = ChatModel(rawValue: UserDefaults.standard.string(forKey: "chatModel") ?? "") ?? .qwen
    @Published var switchingModel = false
    @Published var draft = ""
    @Published var attachments: [Attachment] = []
    @Published var ready = false
    @Published var status = "Starting local engine…"
    @Published var error: String?
    @Published var generating = false
    @Published var workspace: URL?
    @Published var approval: ApprovalRequest?
    @Published var activity = ""
    private var approvalReply: CheckedContinuation<Bool, Never>?
    private let engine = LocalEngine()
    private var generation: Task<Void, Never>?
    private var connecting = false
    private let file: URL
    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Lantern")
        file = dir.appendingPathComponent("conversations.json")
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: file.path) { conversations = try JSONDecoder().decode([Conversation].self, from: Data(contentsOf: file)) }
        } catch { self.error = "Saved chats could not be loaded: \(error.localizedDescription)" }
        selected = conversations.first?.id
        if conversations.isEmpty { newChat() }
    }
    var current: Conversation? { conversations.first { $0.id == selected } }
    func save() {
        do { try JSONEncoder().encode(conversations).write(to: file, options: .atomic) }
        catch { self.error = "Your chats could not be saved: \(error.localizedDescription)" }
    }
    func newChat() {
        guard !generating else { return }
        error = nil
        if let empty = conversations.first(where: { $0.messages.isEmpty && $0.workspacePath == workspace?.path }) { selected = empty.id; draft = ""; return }
        let chat = Conversation(workspacePath: workspace?.path); conversations.insert(chat, at: 0); selected = chat.id; draft = ""; save()
    }
    func connect() async {
        guard !connecting else { return }; connecting = true; defer { connecting = false }
        ready = false; status = "Starting local engine…"
        do {
            if !(await engine.available()) { try engine.start() }
            for _ in 0..<30 {
                if await engine.available() {
                    if try await engine.hasModel(model) { ready = true; status = "Ready · runs on this Mac"; return }
                    status = "\(model.title) is not installed"; error = "The selected model is not downloaded yet. Choose Qwen while RPMax finishes installing."; return
                }
                try await Task.sleep(for: .seconds(2))
            }
            status = "Model is still preparing"; error = "The first model download is still running. Click Retry connection in a moment."
        } catch { status = "Engine needs attention"; self.error = error.localizedDescription }
    }
    func selectModel(_ next: ChatModel) {
        guard !generating, !switchingModel, !connecting, next != model else { return }
        model = next; UserDefaults.standard.set(next.rawValue, forKey: "chatModel")
        ready = false; switchingModel = true; error = nil; status = "Switching to \(next.title)…"
        Task {
            defer { switchingModel = false }
            do { try await engine.unloadOtherModels(than: next); await connect() }
            catch { self.error = error.localizedDescription; status = "Model needs attention" }
        }
    }
    func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ready, !generating, (!text.isEmpty || !attachments.isEmpty), let id = selected, let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        if !model.supportsImages && attachments.contains(where: { $0.imageData != nil }) {
            error = "RPMax is text-only. Choose Qwen to discuss photos, or remove the attached image."; return
        }
        let modelAtStart = model
        error = nil; draft = ""; generating = true
        if conversations[index].messages.isEmpty { conversations[index].title = String((text.isEmpty ? attachments.first!.name : text).prefix(48)) }
        conversations[index].messages.append(Message(role: "user", content: text.isEmpty ? "Please describe or summarize these attachments." : text, attachments: attachments.isEmpty ? nil : attachments))
        attachments = []
        let workspaceAtStart = modelAtStart.supportsTools ? workspace : nil
        save()
        generation = Task {
            defer { generating = false; activity = ""; save() }
            do {
                try await engine.unloadOtherModels(than: modelAtStart)
                var usedTools = 0
                for _ in 0..<7 {
                    try Task.checkCancellation()
                    guard let i = conversations.firstIndex(where: { $0.id == id }) else { break }
                    let history = conversations[i].messages
                    let answer = Message(role: "assistant", content: "", modelName: modelAtStart.title)
                    conversations[i].messages.append(answer)
                    activity = "Thinking on your Mac…"
                    let calls = try await engine.stream(messages: history, model: modelAtStart, agent: workspaceAtStart != nil) { [weak self] token in
                        guard let self, let i = self.conversations.firstIndex(where: { $0.id == id }), let j = self.conversations[i].messages.firstIndex(where: { $0.id == answer.id }) else { return }
                        self.conversations[i].messages[j].content += token
                    }
                    if let i = conversations.firstIndex(where: { $0.id == id }), let j = conversations[i].messages.firstIndex(where: { $0.id == answer.id }), !calls.isEmpty { conversations[i].messages[j].tool_calls = calls }
                    guard !calls.isEmpty else { break }
                    guard let workspaceAtStart else { throw AgentTools.fail("Tools are disabled. Choose a project folder first.") }
                    let tools = AgentTools(root: workspaceAtStart)
                    for call in calls {
                        try Task.checkCancellation()
                        usedTools += 1
                        guard usedTools <= 8 else { throw AgentTools.fail("Stopped at the 8-action limit. Review the results, then ask me to continue.") }
                        var result: String
                        do {
                            let request = try tools.inspect(call)
                            if let request {
                                activity = "Waiting for your approval"
                                let allowed = await withCheckedContinuation { continuation in
                                    approvalReply = continuation; approval = request
                                }
                                try Task.checkCancellation()
                                guard allowed else {
                                    append(Message(role: "tool", content: "Declined by user. No action taken. Do not retry this action.", tool_name: call.function.name), to: id)
                                    append(Message(role: "assistant", content: "No problem—that action wasn’t run."), to: id)
                                    return
                                }
                            }
                            activity = "Using " + call.function.name.replacingOccurrences(of: "_", with: " ")
                            result = try await tools.perform(call, approval: request)
                        } catch {
                            if Task.isCancelled { throw CancellationError() }
                            result = "Tool did not complete: " + error.localizedDescription
                            if result.contains("Action declined") { throw error }
                        }
                        append(Message(role: "tool", content: String(result.prefix(12000)), tool_name: call.function.name), to: id)
                        save()
                    }
                }
            } catch {
                if !Task.isCancelled { self.error = error.localizedDescription }
            }
        }
    }
    private func append(_ message: Message, to id: UUID) {
        guard let i = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[i].messages.append(message)
    }
    func chooseAttachments() {
        guard !generating else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = true
        panel.message = "Attach photos, text/code files, or PDFs with selectable text. Up to 4 files; 12,000 document characters total."
        panel.prompt = "Attach"
        if panel.runModal() == .OK { addAttachments(panel.urls) }
    }
    func addAttachments(_ urls: [URL]) {
        guard !generating else { return }
        do {
            guard attachments.count + urls.count <= 4 else { throw Attachment.failure("Attach up to 4 files per message.") }
            let added = try urls.map { try Attachment.read($0) }
            guard (attachments + added).reduce(0, { $0 + ($1.text?.count ?? 0) }) <= 12000 else { throw Attachment.failure("Keep attached document text under 12,000 characters per message.") }
            attachments += added
        } catch { self.error = error.localizedDescription }
    }
    func chooseWorkspace() {
        guard !generating else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.message = "Choose one project folder. Lantern can read its ordinary files. Every edit and command needs your approval."
        panel.prompt = "Use this project"
        if panel.runModal() == .OK, let url = panel.url {
            guard AgentTools.permittedRoot(url) else { error = "Choose a specific project folder inside your home folder, rather than your entire home, Documents, Desktop, Downloads or Library."; return }
            workspace = url.resolvingSymlinksInPath().standardizedFileURL
            newChat()
        }
    }
    func answerApproval(_ allowed: Bool) {
        approval = nil
        let reply = approvalReply; approvalReply = nil; reply?.resume(returning: allowed)
    }
    func stop() { generation?.cancel(); answerApproval(false) }
}
