import Foundation

// Compile this harness with the production LiveController.swift only. These
// doubles keep every test away from real microphones, chats, keys and providers.
@MainActor final class ManualGate<Value> {
    private var continuation: CheckedContinuation<Value, Never>?
    private var resolved: Value?
    func wait() async -> Value {
        if let resolved { return resolved }
        return await withCheckedContinuation { continuation = $0 }
    }
    func resolve(_ value: Value) {
        resolved = value
        let pending = continuation
        continuation = nil
        pending?.resume(returning: value)
    }
}

@MainActor final class LiveAccount {
    static var tokenGate: ManualGate<String>?
    var hasAnamKey = true
    var avatarID = "test-avatar"
    var hasElevenKey = true
    var elevenVoiceID = "test-voice"
    private(set) var tokenRequests = 0
    private(set) var spokenTexts: [String] = []
    func makeSessionToken() async throws -> String {
        tokenRequests += 1
        if let gate = Self.tokenGate { return await gate.wait() }
        return "test-session-token"
    }
    func synthesizeEleven(_ text: String) async throws -> Data {
        spokenTexts.append(text)
        return Data([0, 0, 1, 0])
    }
}

@MainActor final class LiveAvatarBridge {
    var onReady: (() -> Void)?
    var onClosed: ((String?) -> Void)?
    var onSpeechEnded: (() -> Void)?
    var onError: ((String) -> Void)?
    private(set) var startTokens: [String] = []
    private(set) var sentAudio: [Data] = []
    private(set) var interruptCount = 0
    private(set) var stopCount = 0
    func start(sessionToken: String) async throws { startTokens.append(sessionToken); onReady?() }
    func sendAudio(_ data: Data) async throws { sentAudio.append(data) }
    func interrupt() { interruptCount += 1 }
    func interruptAndWait() async throws { interruptCount += 1 }
    func stop() async { stopCount += 1 }
}

@MainActor final class LiveSpeechListener {
    static var denyPermissions = false
    static var latest: LiveSpeechListener?
    var onTranscript: ((String) -> Void)?
    var onError: ((String) -> Void)?
    var onPartial: ((String) -> Void)?
    private(set) var permissionRequests = 0
    private(set) var startCount = 0
    private(set) var stopCount = 0
    init() { Self.latest = self }
    func requestPermissions() async throws {
        permissionRequests += 1
        if Self.denyPermissions {
            throw NSError(domain: "LiveControllerChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: "Test microphone permission unavailable."])
        }
    }
    func start() throws { startCount += 1 }
    func stop() { stopCount += 1 }
}

@MainActor final class ChatStore {
    var ready = true
    var generating = false
    var selected: UUID? = UUID()
    var onStopLive: (() -> Void)?
    var replyGate: ManualGate<String>?
    private(set) var requests: [(String, UUID)] = []
    private(set) var stopCount = 0
    func liveReply(to text: String, conversationID: UUID) async throws -> String {
        requests.append((text, conversationID))
        if let replyGate { return await replyGate.wait() }
        return "Qwen says: \(text)"
    }
    func stop() { stopCount += 1; generating = false }
}

@main struct LiveControllerChecks {
    @MainActor static func eventually(_ description: String, _ predicate: () -> Bool) async throws {
        for _ in 0..<200 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw NSError(domain: "LiveControllerChecks", code: 2, userInfo: [NSLocalizedDescriptionKey: "Timed out: \(description)"])
    }

    @MainActor static func typedConversationWithoutMicrophone() async throws {
        LiveSpeechListener.denyPermissions = true
        LiveAccount.tokenGate = nil
        let store = ChatStore()
        let controller = LiveController()
        controller.bind(to: store)
        controller.goLive()
        try await eventually("typed-only live connection") { controller.phase == .listening }
        precondition(controller.microphonePaused, "Denied microphone must leave typed mode available")
        precondition(controller.notice?.contains("You can type") == true)
        precondition(controller.avatar.startTokens.count == 1)
        precondition(controller.clock == "3:00", "Free-plan session begins with a three-minute cap")
        controller.goLive()
        precondition(controller.account.tokenRequests == 1, "Repeated Go Live must not start a second session")

        controller.sendTyped("First typed question")
        try await eventually("first avatar reply") { controller.phase == .speaking && controller.avatar.sentAudio.count == 1 }
        precondition(controller.lastReply == "Qwen says: First typed question")
        controller.avatar.onSpeechEnded?()
        precondition(controller.phase == .listening, "Playback ending must restore listening phase even when microphone is paused")
        precondition(controller.microphonePaused)
        precondition(LiveSpeechListener.latest?.startCount == 0, "Typed-only mode must not start microphone capture")

        controller.sendTyped("Second typed question")
        try await eventually("second avatar reply") { controller.phase == .speaking && controller.avatar.sentAudio.count == 2 }
        precondition(store.requests.map(\.0) == ["First typed question", "Second typed question"])
        precondition(store.requests.allSatisfy { $0.1 == store.selected }, "Both spoken turns use the bound chat")
        controller.avatar.onSpeechEnded?()
        precondition(controller.phase == .listening)
        controller.end()
        try await eventually("End Live closes avatar") { controller.phase == .idle && controller.avatar.stopCount == 1 }
        precondition(!controller.active && controller.avatar.interruptCount == 1)
        precondition((LiveSpeechListener.latest?.stopCount ?? 0) > 0)
        print("PASS: denied microphone supports two typed turns; playback restores listening; duplicate Go Live is ignored; End Live stops the session")
    }

    @MainActor static func endCancelsPendingReply() async throws {
        LiveSpeechListener.denyPermissions = true
        LiveAccount.tokenGate = nil
        let store = ChatStore()
        let controller = LiveController()
        controller.bind(to: store)
        controller.goLive()
        try await eventually("reply-cancellation session") { controller.phase == .listening }
        let gate = ManualGate<String>()
        store.replyGate = gate
        controller.sendTyped("Pending question")
        try await eventually("pending Qwen reply") { controller.phase == .thinking && store.requests.count == 1 }
        controller.end()
        try await eventually("End Live while thinking") { controller.phase == .idle }
        precondition(store.stopCount == 1, "End Live must cancel the in-flight local reply")
        precondition(controller.avatar.stopCount == 1)
        gate.resolve("A deliberately late Qwen answer")
        try await Task.sleep(for: .milliseconds(30))
        precondition(controller.account.spokenTexts.isEmpty, "Cancelled reply must not generate paid voice audio")
        precondition(controller.avatar.sentAudio.isEmpty, "Late reply must never be sent to a closed avatar")
        precondition(controller.phase == .idle)
        print("PASS: End Live cancels pending Qwen work and discards late replies before TTS or avatar audio")
    }

    @MainActor static func endDuringStartupPreventsLateSession() async throws {
        LiveSpeechListener.denyPermissions = false
        let tokenGate = ManualGate<String>()
        LiveAccount.tokenGate = tokenGate
        defer { LiveAccount.tokenGate = nil }
        let store = ChatStore()
        let controller = LiveController()
        controller.bind(to: store)
        controller.goLive()
        try await eventually("pending session token") { controller.phase == .connecting && controller.account.tokenRequests == 1 }
        controller.end()
        try await eventually("End Live during startup") { controller.phase == .idle && controller.avatar.stopCount == 1 }
        tokenGate.resolve("late-session-token")
        try await Task.sleep(for: .milliseconds(30))
        precondition(controller.avatar.startTokens.isEmpty, "A late token must not open an avatar after End Live")
        precondition(controller.phase == .idle && !controller.active)
        precondition(LiveSpeechListener.latest?.startCount == 0)
        print("PASS: End Live during pending startup prevents late session creation and microphone capture")
    }

    @MainActor static func main() async {
        do {
            try await typedConversationWithoutMicrophone()
            try await endCancelsPendingReply()
            try await endDuringStartupPreventsLateSession()
        } catch {
            fputs("FAIL: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}
