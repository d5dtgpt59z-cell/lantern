import SwiftUI

@MainActor final class LiveController: ObservableObject {
    enum Phase: String {
        case idle, preparing, connecting, listening, thinking, speaking, ending
        var title: String {
            switch self {
            case .idle: "Ready for a live conversation"
            case .preparing: "Preparing microphone…"
            case .connecting: "Connecting to Anam…"
            case .listening: "Listening to you"
            case .thinking: "Qwen is thinking…"
            case .speaking: "Paige is speaking"
            case .ending: "Ending live connection…"
            }
        }
    }
    @Published private(set) var phase = Phase.idle
    @Published private(set) var secondsRemaining = 180
    @Published var showPanel = false
    @Published var showSettings = false
    @Published private(set) var partial = ""
    @Published private(set) var lastHeard = ""
    @Published private(set) var lastReply = ""
    @Published private(set) var notice: String?
    @Published private(set) var microphonePaused = false
    let account = LiveAccount()
    let avatar = LiveAvatarBridge()
    private let listener = LiveSpeechListener()
    private weak var store: ChatStore?
    private var conversationID: UUID?
    private var operationID = UUID()
    private var startTask: Task<Void, Never>?
    private var responseTask: Task<Void, Never>?
    private var limitTask: Task<Void, Never>?
    var active: Bool { phase != .idle }
    var statusTitle: String { phase == .listening && microphonePaused ? "Microphone paused · type to Paige" : phase.title }
    var clock: String { String(format: "%d:%02d", secondsRemaining / 60, secondsRemaining % 60) }

    init() {
        listener.onPartial = { [weak self] in self?.partial = $0 }
        listener.onTranscript = { [weak self] in self?.reply(to: $0) }
        listener.onError = { [weak self] message in
            guard let self, self.active, self.phase != .ending else { return }
            self.microphonePaused = true; self.notice = message
        }
        avatar.onClosed = { [weak self] message in
            guard let self, self.active, self.phase != .ending else { return }
            self.end(message: message ?? "Live connection ended.")
        }
        avatar.onError = { [weak self] message in
            guard let self, self.active, self.phase != .ending else { return }
            self.end(message: message)
        }
        avatar.onSpeechEnded = { [weak self] in
            guard let self, self.phase == .speaking else { return }
            self.listen()
        }
    }

    func bind(to store: ChatStore) {
        self.store = store
        store.onStopLive = { [weak self] in self?.end() }
    }

    func goLive() {
        guard !active else { return }
        notice = nil; showPanel = true
        guard account.hasAnamKey, !account.avatarID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              account.hasElevenKey, !account.elevenVoiceID.isEmpty else {
            showSettings = true; return
        }
        guard let store, store.ready, !store.generating, let chat = store.selected else {
            notice = "Wait for Qwen to be ready and finish the current response, then press Go Live."; return
        }
        conversationID = chat; lastHeard = ""; lastReply = ""; partial = ""
        microphonePaused = false; secondsRemaining = 180
        let id = UUID(); operationID = id; phase = .preparing
        startTask = Task { [weak self] in
            guard let self else { return }
            do {
                do { try await listener.requestPermissions() }
                catch {
                    try Task.checkCancellation()
                    microphonePaused = true
                    notice = error.localizedDescription + " You can type to Paige below."
                }
                try Task.checkCancellation()
                guard operationID == id else { return }
                phase = .connecting
                let token = try await account.makeSessionToken()
                try Task.checkCancellation()
                guard operationID == id else { return }
                // Start the cap before opening media, so connecting time never extends free sessions.
                startLimit(id: id)
                try await avatar.start(sessionToken: token)
                try Task.checkCancellation()
                guard operationID == id else { return }
                startTask = nil; phase = .listening; listen()
            } catch {
                guard operationID == id, !Task.isCancelled else { return }
                end(message: error.localizedDescription)
            }
        }
    }

    private func startLimit(id: UUID) {
        limitTask?.cancel()
        let clock = ContinuousClock(); let deadline = clock.now.advanced(by: .seconds(180))
        limitTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, operationID == id else { return }
                let duration = clock.now.duration(to: deadline)
                let remaining = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
                secondsRemaining = max(0, Int(ceil(remaining)))
                if remaining <= 0 { end(message: "Three-minute free session finished. Press Go Live for another session if your Anam allowance remains."); return }
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
    }

    private func listen() {
        guard active, phase != .ending else { return }
        phase = .listening; partial = ""
        guard !microphonePaused else { return }
        do { try listener.start() }
        catch { microphonePaused = true; notice = error.localizedDescription }
    }

    func toggleMicrophone() {
        guard active, phase != .ending else { return }
        microphonePaused.toggle(); listener.stop(); partial = ""
        if !microphonePaused, phase == .listening { notice = nil; listen() }
    }

    func interrupt() {
        guard phase == .speaking || phase == .thinking else { return }
        let interrupted = responseTask
        interrupted?.cancel(); responseTask = nil
        let id = operationID
        Task { [weak self] in
            _ = await interrupted?.value
            guard let self, operationID == id, active, phase != .ending else { return }
            do { try await avatar.interruptAndWait() }
            catch { end(message: error.localizedDescription); return }
            guard operationID == id, active, phase != .ending else { return }
            phase = .listening; listen()
        }
    }

    func sendTyped(_ text: String) {
        guard active, phase == .listening else { return }
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        listener.stop(); reply(to: text)
    }

    private func reply(to text: String) {
        guard phase == .listening, let store, let chat = conversationID, store.selected == chat else { return }
        listener.stop(); partial = ""; lastHeard = text; notice = nil; phase = .thinking
        let id = operationID
        responseTask = Task { [weak self] in
            guard let self else { return }
            do {
                let text = try await store.liveReply(to: text, conversationID: chat)
                try Task.checkCancellation()
                guard operationID == id, active, phase != .ending else { return }
                lastReply = text
                let audio = try await account.synthesizeEleven(text)
                try Task.checkCancellation()
                guard operationID == id, active, phase != .ending else { return }
                phase = .speaking
                try await avatar.sendAudio(audio)
                if operationID == id { responseTask = nil }
            } catch {
                guard operationID == id, !Task.isCancelled else { return }
                end(message: error.localizedDescription)
            }
        }
    }

    func end(message: String? = nil) {
        guard active, phase != .ending else { if let message { notice = message }; return }
        phase = .ending; operationID = UUID()
        startTask?.cancel(); startTask = nil
        let wasReplying = responseTask != nil
        responseTask?.cancel(); responseTask = nil
        limitTask?.cancel(); limitTask = nil
        listener.stop(); partial = ""
        avatar.interrupt()
        if wasReplying { store?.stop() }
        if let message { notice = message }
        let renderer = avatar
        Task { [weak self] in
            // Retain the renderer until its explicit stop finishes, even if the window closes.
            await renderer.stop()
            self?.phase = .idle
        }
    }
}
