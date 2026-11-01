import Foundation
import AppKit
@preconcurrency import AVFoundation
@preconcurrency import Speech

/// One spoken turn at a time. The owner rearms listening after avatar playback.
@MainActor
final class LiveSpeechListener {
    var onTranscript: ((String) -> Void)?
    var onError: ((String) -> Void)?
    var onPartial: ((String) -> Void)?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var audioEngine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var silenceTask: Task<Void, Never>?
    private var sessionID = UUID()
    private var partialText = ""
    private var tapInstalled = false

    func requestPermissions() async throws {
        let microphoneAllowed: Bool
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: microphoneAllowed = true
        case .notDetermined:
            NSApplication.shared.activate(ignoringOtherApps: true)
            microphoneAllowed = try await permission(.microphoneTimeout) { callback in
                AVCaptureDevice.requestAccess(for: .audio, completionHandler: callback)
            }
        default: microphoneAllowed = false
        }
        try Task.checkCancellation()
        guard microphoneAllowed else { throw LiveSpeechError.microphoneDenied }

        let speechStatus: SFSpeechRecognizerAuthorizationStatus
        if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
            NSApplication.shared.activate(ignoringOtherApps: true)
            speechStatus = try await permission(.speechTimeout) { callback in
                SFSpeechRecognizer.requestAuthorization(callback)
            }
        } else {
            speechStatus = SFSpeechRecognizer.authorizationStatus()
        }
        try Task.checkCancellation()
        guard speechStatus == .authorized else { throw LiveSpeechError.speechDenied }
        guard recognizer?.supportsOnDeviceRecognition == true else { throw LiveSpeechError.onDeviceUnavailable }
    }

    func start() throws {
        stop()
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else { throw LiveSpeechError.microphoneDenied }
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else { throw LiveSpeechError.speechDenied }
        guard let recognizer, recognizer.supportsOnDeviceRecognition else { throw LiveSpeechError.onDeviceUnavailable }
        guard recognizer.isAvailable else { throw LiveSpeechError.recognizerUnavailable }

        let identifier = UUID()
        sessionID = identifier
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw LiveSpeechError.noMicrophone }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        request.contextualStrings = ["Paige", "Qwen"]
        self.audioEngine = engine
        self.request = request
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak request] buffer, _ in
            request?.append(buffer)
        }
        tapInstalled = true
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self, self.sessionID == identifier else { return }
                if let result {
                    let text = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty {
                        let changed = text != self.partialText
                        self.partialText = text
                        self.onPartial?(text)
                        if result.isFinal {
                            self.commit(text, sessionID: identifier)
                            return
                        }
                        if changed { self.waitForSilence(sessionID: identifier) }
                    }
                }
                if let error {
                    // A framework close can accompany a usable final partial.
                    if !self.partialText.isEmpty {
                        self.commit(self.partialText, sessionID: identifier)
                    } else {
                        self.stop()
                        let native = error as NSError
                        if native.domain == "kAFAssistantErrorDomain" && native.code == 1110 {
                            self.onError?("No speech was detected. Try listening again, or type in the chat.")
                        } else {
                            self.onError?("Speech recognition stopped. Check your microphone, then try again. \(error.localizedDescription)")
                        }
                    }
                }
            }
        }
        engine.prepare()
        do { try engine.start() } catch { stop(); throw error }
    }

    func stop() {
        sessionID = UUID()
        silenceTask?.cancel()
        silenceTask = nil
        audioEngine?.stop()
        if tapInstalled { audioEngine?.inputNode.removeTap(onBus: 0) }
        tapInstalled = false
        request?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        request = nil
        audioEngine = nil
        partialText = ""
    }

    private func waitForSilence(sessionID identifier: UUID) {
        silenceTask?.cancel()
        silenceTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(1100)) } catch { return }
            guard let self, self.sessionID == identifier else { return }
            self.commit(self.partialText, sessionID: identifier)
        }
    }

    private func commit(_ text: String, sessionID identifier: UUID) {
        guard sessionID == identifier, !text.isEmpty else { return }
        stop()
        onPartial?("")
        onTranscript?(text)
    }

    private func permission<Value: Sendable>(_ timeoutError: LiveSpeechError, request: (@escaping @Sendable (Value) -> Void) -> Void) async throws -> Value {
        let gate = LivePermissionGate<Value>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                gate.install(continuation)
                DispatchQueue.main.asyncAfter(deadline: .now() + 30) { gate.resolve(.failure(timeoutError)) }
                request { gate.resolve(.success($0)) }
            }
        } onCancel: {
            gate.resolve(.failure(CancellationError()))
        }
    }
}

/// Generates raw voice audio only. Playback comes back from Anam in sync with video.
@MainActor
final class LiveSpeechSynthesizer {
    private let synthesizer = AVSpeechSynthesizer()
    private var completion: CheckedContinuation<Data, Error>?
    private var operationID = UUID()
    private var collector: LivePCMCollector?
    private var timeoutTask: Task<Void, Never>?

    func synthesize(_ text: String) async throws -> Data {
        cancel()
        try Task.checkCancellation()
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw LiveSpeechError.emptySpeech }
        guard text.count <= 6000 else { throw LiveSpeechError.speechTooLong }
        let identifier = UUID()
        operationID = identifier
        let collector = LivePCMCollector()
        self.collector = collector
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice.speechVoices().first(where: { $0.name == "Samantha" && $0.language.hasPrefix("en") })
            ?? AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.96
        utterance.pitchMultiplier = 1
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                completion = continuation
                timeoutTask = Task { @MainActor [weak self] in
                    do { try await Task.sleep(for: .seconds(45)) } catch { return }
                    guard let self, self.operationID == identifier else { return }
                    self.finish(.failure(LiveSpeechError.synthesisTimeout), operationID: identifier)
                }
                synthesizer.write(utterance) { [weak self] buffer in
                    guard let pcm = buffer as? AVAudioPCMBuffer else { return }
                    do {
                        if pcm.frameLength > 0 {
                            try collector.append(pcm)
                        } else {
                            let audio = try collector.finish()
                            Task { @MainActor [weak self] in self?.finish(.success(audio), operationID: identifier) }
                        }
                    } catch {
                        Task { @MainActor [weak self] in self?.finish(.failure(error), operationID: identifier) }
                    }
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard let self, self.operationID == identifier else { return }
                self.cancel()
            }
        }
    }

    func cancel() {
        operationID = UUID()
        collector?.cancel()
        collector = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        let pending = completion
        completion = nil
        synthesizer.stopSpeaking(at: .immediate)
        pending?.resume(throwing: CancellationError())
    }

    private func finish(_ result: Result<Data, Error>, operationID identifier: UUID) {
        guard operationID == identifier, let pending = completion else { return }
        completion = nil
        operationID = UUID()
        timeoutTask?.cancel()
        timeoutTask = nil
        collector?.cancel()
        collector = nil
        if case .failure = result { synthesizer.stopSpeaking(at: .immediate) }
        pending.resume(with: result)
    }
}

/// Serializes callback buffers into a single PCM source, then resamples once so
/// there are no per-buffer resampler resets at speech-buffer boundaries.
private final class LivePCMCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var sourceFormat: AVAudioFormat?
    private var channelData: [Data] = []
    private var frameCount: AVAudioFrameCount = 0
    private var finished = false

    func append(_ buffer: AVAudioPCMBuffer) throws {
        lock.lock(); defer { lock.unlock() }
        guard !finished else { return }
        if sourceFormat == nil {
            sourceFormat = buffer.format
            channelData = Array(repeating: Data(), count: Int(buffer.audioBufferList.pointee.mNumberBuffers))
        }
        guard sourceFormat == buffer.format else { throw LiveSpeechError.audioFormatChanged }
        guard Double(frameCount + buffer.frameLength) / buffer.format.sampleRate < 240 else { throw LiveSpeechError.speechTooLong }
        let buffers = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        for (index, audioBuffer) in buffers.enumerated() {
            guard let bytes = audioBuffer.mData else { throw LiveSpeechError.noSpeechAudio }
            channelData[index].append(bytes.assumingMemoryBound(to: UInt8.self), count: Int(audioBuffer.mDataByteSize))
        }
        frameCount += buffer.frameLength
    }

    func finish() throws -> Data {
        lock.lock(); defer { lock.unlock() }
        guard !finished else { throw CancellationError() }
        finished = true
        guard let sourceFormat, frameCount > 0,
              let source = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: frameCount),
              let targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24000, channels: 1, interleaved: true),
              let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else { throw LiveSpeechError.noSpeechAudio }
        source.frameLength = frameCount
        let buffers = UnsafeMutableAudioBufferListPointer(source.mutableAudioBufferList)
        for (index, audioBuffer) in buffers.enumerated() {
            guard let destination = audioBuffer.mData, index < channelData.count else { throw LiveSpeechError.noSpeechAudio }
            channelData[index].withUnsafeBytes { bytes in
                if let address = bytes.baseAddress { destination.copyMemory(from: address, byteCount: bytes.count) }
            }
        }
        let capacity = AVAudioFrameCount(ceil(Double(frameCount) * targetFormat.sampleRate / sourceFormat.sampleRate)) + 4096
        guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { throw LiveSpeechError.noSpeechAudio }
        var supplied = false
        var conversionError: NSError?
        let status = converter.convert(to: converted, error: &conversionError) { _, status in
            if supplied { status.pointee = .endOfStream; return nil }
            supplied = true
            status.pointee = .haveData
            return source
        }
        if let conversionError { throw conversionError }
        guard status != .error, converted.frameLength > 0, let bytes = converted.audioBufferList.pointee.mBuffers.mData else { throw LiveSpeechError.noSpeechAudio }
        return Data(bytes: bytes, count: Int(converted.frameLength) * 2)
    }

    func cancel() {
        lock.lock(); defer { lock.unlock() }
        finished = true
        channelData.removeAll()
    }
}

private final class LivePermissionGate<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<Value, Error>?
    private var continuation: CheckedContinuation<Value, Error>?
    func install(_ continuation: CheckedContinuation<Value, Error>) {
        lock.lock()
        if let result { lock.unlock(); continuation.resume(with: result) }
        else { self.continuation = continuation; lock.unlock() }
    }
    func resolve(_ result: Result<Value, Error>) {
        lock.lock()
        guard self.result == nil else { lock.unlock(); return }
        self.result = result
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(with: result)
    }
}

private enum LiveSpeechError: LocalizedError {
    case microphoneDenied, speechDenied, microphoneTimeout, speechTimeout
    case onDeviceUnavailable, recognizerUnavailable, noMicrophone
    case emptySpeech, speechTooLong, noSpeechAudio, audioFormatChanged, synthesisTimeout
    var errorDescription: String? {
        switch self {
        case .microphoneDenied: return "Allow PAIGE microphone access in System Settings → Privacy & Security → Microphone, then try Go Live again."
        case .speechDenied: return "Allow PAIGE Speech Recognition in System Settings → Privacy & Security → Speech Recognition, then try Go Live again."
        case .microphoneTimeout: return "macOS is waiting for microphone permission. Allow PAIGE in the system dialog, then try Go Live again."
        case .speechTimeout: return "macOS is waiting for Speech Recognition permission. Allow PAIGE in the system dialog, then try Go Live again."
        case .onDeviceUnavailable: return "On-device English speech recognition is unavailable. Install it in macOS or use typed messages; PAIGE does not send your microphone audio to a speech service."
        case .recognizerUnavailable: return "On-device speech recognition is temporarily unavailable. Try the microphone again, or type your message."
        case .noMicrophone: return "No active microphone was found. Select one in System Settings → Sound, then try again."
        case .emptySpeech: return "There is no text to speak."
        case .speechTooLong: return "This reply is too long for a live voice turn. Ask Paige for a shorter answer."
        case .noSpeechAudio: return "The local voice did not produce audio. Paige's reply is still available in the chat."
        case .audioFormatChanged: return "The local voice changed audio format unexpectedly. Try the voice turn again."
        case .synthesisTimeout: return "The local voice took too long to generate audio. Try again, or select another installed voice."
        }
    }
}
