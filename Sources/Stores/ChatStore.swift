import SwiftUI
import AppKit
@MainActor final class ChatStore: ObservableObject {
    @Published var conversations: [Conversation] = []
    @Published var selected: UUID? { didSet { if oldValue != selected { attachments = [] }; if current?.workspacePath != workspace?.path { workspace = nil } } }
    @Published var model: ChatModel = ChatModel(rawValue: UserDefaults.standard.string(forKey: "chatModel") ?? "") ?? .qwen
    @Published var showModels = false
    @Published var thinking = UserDefaults.standard.bool(forKey: "thinking") { didSet { UserDefaults.standard.set(thinking, forKey: "thinking") } }
    @Published var installed = Set<String>()
    @Published var downloading: ChatModel?
    @Published var downloadProgress: Double?
    @Published var downloadStatus = ""
    @Published var modelError: String?
    @Published var freeGB: Double = 0
    @Published var updateStatus = ""
    @Published var checkingUpdate = false
    private var lastStorageCheck = Date.distantPast
    private var downloadTask: Task<Void, Never>?
    var supportedHardware: Bool { ProcessInfo.processInfo.physicalMemory >= 16 * 1024 * 1024 * 1024 }
    func refreshStorage() {
        let values = try? LocalEngine.modelDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        freeGB = Double(values?.volumeAvailableCapacityForImportantUsage ?? 0) / 1_000_000_000
    }
    func download(_ target: ChatModel) {
        guard downloading == nil, !generating else { return }
        refreshStorage()
        guard supportedHardware else { modelError = "This release requires an Apple Silicon Mac with at least 16 GB of memory."; return }
        let resuming = UserDefaults.standard.bool(forKey: "partial-" + target.rawValue)
        guard freeGB > (resuming ? 2 : target.downloadGB + 2) else { modelError = "Free at least \(Int(target.downloadGB + 3)) GB, then retry. Partial downloads are kept for resuming."; return }
        UserDefaults.standard.set(true, forKey: "partial-" + target.rawValue)
        downloading = target; downloadStatus = "Connecting…"; modelError = nil
        downloadTask = Task {
            defer { downloading = nil; downloadProgress = nil; refreshStorage() }
            do {
                guard await engine.available() else { throw Attachment.failure("The engine is not ready. Close this panel, retry the connection, then resume.") }
                try await engine.pull(target) { [weak self] status, progress in self?.downloadStatus = status.hasPrefix("pulling") ? "Downloading model files…" : status.hasPrefix("verifying") ? "Checking download…" : status == "success" ? "Ready to chat" : "Preparing your model…"; self?.downloadProgress = progress
                    if let self, Date().timeIntervalSince(self.lastStorageCheck) > 2 {
                        self.lastStorageCheck = Date(); self.refreshStorage()
                        if self.freeGB < 1.5 { self.modelError = "Download paused because storage is running low. Free some space, then resume."; self.pauseDownload() }
                    }
                }
                installed = try await engine.installedModels()
                UserDefaults.standard.removeObject(forKey: "partial-" + target.rawValue)
                downloadStatus = "Download complete"
                await connect()
            } catch {
                if Task.isCancelled { downloadStatus = "Paused. Resume to continue." }
                else { modelError = error.localizedDescription; downloadStatus = "Download needs attention" }
            }
        }
    }
    func pauseDownload() { downloadTask?.cancel() }
    func removeModel(_ target: ChatModel) async {
        guard downloading == nil, !generating else { return }
        do { try await engine.remove(target); installed = try await engine.installedModels(); await connect(); refreshStorage() }
        catch { modelError = error.localizedDescription }
    }
    func shutdown() { stop(); pauseDownload(); engine.shutdown() }
    func checkUpdate() async {
        guard !checkingUpdate else { return }; checkingUpdate = true; defer { checkingUpdate = false }
        do {
            let url = URL(string: "https://api.github.com/repos/d5dtgpt59z-cell/lantern/releases/latest")!
            var req = URLRequest(url: url); req.timeoutInterval = 15
            let (data, response) = try await URLSession.shared.data(for: req)
            if (response as? HTTPURLResponse)?.statusCode == 404 { updateStatus = "No public release is available yet."; return }
            guard (response as? HTTPURLResponse)?.statusCode == 200, let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any], let tag = obj["tag_name"] as? String else { throw Attachment.failure("Update check failed. Try again later.") }
            let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
            updateStatus = tag.trimmingCharacters(in: CharacterSet(charactersIn: "v")).compare(current, options: .numeric) == .orderedDescending ? "Version \(tag) is available on Releases." : "You're up to date (\(current))."
        } catch { updateStatus = "Could not check for updates. Your local chats still work offline." }
    }
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
    private var canSaveChats = true
    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Lantern")
        file = dir.appendingPathComponent("conversations.json")
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: file.path) { conversations = try JSONDecoder().decode([Conversation].self, from: Data(contentsOf: file)) }
        } catch { canSaveChats = false; self.error = "Saved chats could not be loaded: \(error.localizedDescription)" }
        selected = conversations.first?.id
        if conversations.isEmpty && canSaveChats { newChat() }
    }
    var current: Conversation? { conversations.first { $0.id == selected } }
    func save() {
        guard canSaveChats else { return }
        do { try JSONEncoder().encode(conversations).write(to: file, options: .atomic) }
        catch { self.error = "Your chats could not be saved: \(error.localizedDescription)" }
    }
    func newChat() {
        guard !generating, canSaveChats else { return }
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
                    installed = try await engine.installedModels(); refreshStorage()
                    if installed.contains(model.ollamaName) { ready = true; status = "Ready · runs on this Mac"; return }
                    status = "\(model.title) is not installed"; showModels = true; return
                }
                try await Task.sleep(for: .seconds(2))
            }
            status = "Engine needs attention"; error = "The local engine did not start. Retry the connection or download a fresh copy of Lantern."
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
    func retryAnswer() {
        guard ready, !generating, current?.messages.contains(where: { $0.role == "user" }) == true else { return }
        draft = "Please continue my previous request. Check the existing tool results before proposing any action again."
        send()
    }
    func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ready, !generating, (!text.isEmpty || !attachments.isEmpty), let id = selected, let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        if !model.supportsImages && attachments.contains(where: { $0.imageData != nil }) {
            error = "RPMax is text-only. Choose Qwen to discuss photos, or remove the attached image."; return
        }
        let modelAtStart = model
        let thinkingAtStart = thinking && model == .qwen
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
                    let calls = try await engine.stream(messages: history, model: modelAtStart, agent: workspaceAtStart != nil, thinking: thinkingAtStart) { [weak self] token in
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
