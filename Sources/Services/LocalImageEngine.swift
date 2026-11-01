import Foundation
import AppKit

/// Routes direct image requests without loading the language model.
struct ImageRequest {
    let prompt: String
    var negative = ""
    var size = 512

    static func parse(_ text: String, imageMode: Bool = false) -> ImageRequest? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if imageMode { return ImageRequest(prompt: text) }
        if text.range(of: #"^/image(?:\s|$)"#, options: [.regularExpression, .caseInsensitive]) != nil {
            let prompt = String(text.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)
            return prompt.isEmpty ? nil : ImageRequest(prompt: prompt)
        }
        let prefix = #"^(?:(?:please|paige)[,\s]+)*(?:(?:can|could|would|will)\s+you\s+)?(?:please\s+)?"#
        let nouns = #"(?:images?|pictures?|photos?|photographs?|illustrations?|artworks?|portraits?|paintings?|posters?|logos?)"#
        let software = #"(?:prompts?|generators?|generation|models?|tools?|apps?|applications?|buttons?|apis?|galleries|gallery|components?|views?|elements?|files?|tags?|functions?|classes|class|scripts?|code|websites?|interfaces?|layouts?|schemas?|pipelines?|processors?|processing|loaders?|viewers?|editors?|converters?|servers?|services?|endpoints?|libraries|library|parsers?|recognition|classification|compression|embeddings?)"#
        let otherTasks = #"(?:write|explain|describe|learn|support|information|instructions?|tutorials?|guides?|plans?|poems?|stories|story|essays?|summaries|summary|captions?|descriptions?|explanations?|examples?|comparisons?|analyses|analysis)"#
        func matches(_ pattern: String, _ value: String) -> Bool {
            value.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
        func clearImageTarget(_ target: String) -> Bool {
            // Modifiers are unrestricted. Inspect the requested noun and task instead of a style list.
            guard let noun = target.range(of: #"(?<![\p{L}\p{N}_-])"# + nouns + #"(?![\p{L}\p{N}_-])"#, options: [.regularExpression, .caseInsensitive]) else { return false }
            let modifiers = String(target[..<noun.lowerBound])
            let description = String(target[noun.upperBound...])
            guard !matches(#"\b(?:"# + software + "|" + otherTasks + #")\b"#, modifiers),
                  !matches(#"^\s+(?:"# + software + #")\b"#, description),
                  matches(#"[\p{L}\p{N}]"#, description) else { return false }
            return true
        }
        let creating = prefix + #"(?:make|create|generate)\s+(?:me\s+)?"#
        let wanting = prefix + #"(?:i\s+(?:want|would\s+like)|i['’]d\s+like)\s+"#
        for head in [creating, wanting] {
            if let range = text.range(of: head, options: [.regularExpression, .caseInsensitive]) {
                return clearImageTarget(String(text[range.upperBound...])) ? ImageRequest(prompt: text) : nil
            }
        }
        if let range = text.range(of: prefix + #"(?:draw|paint|sketch|render)\s+"#, options: [.regularExpression, .caseInsensitive]) {
            let target = String(text[range.upperBound...])
            guard !matches(#"^(?:up|a\s+conclusion|a\s+comparison|a\s+blank|attention|the\s+line|html|this\s+(?:html|page|component|markdown|json|code|view|template))\b"#, target),
                  !matches(#"^(?:me\s+)?(?:(?:a|an|some)\s+)?"# + nouns + #"[?.!]*$"#, target),
                  !matches(#"\b(?:as|using|in)\s+(?:html|css|javascript|typescript|swiftui|react|python|svg|json|markdown|mermaid|code)\b"#, target) else { return nil }
            return ImageRequest(prompt: text)
        }
        // Preserve short descriptions such as “A picture of…” without treating general questions as requests.
        let bare = prefix + #"(?:(?:a|an|some)\s+|"# + nouns + #"\s+of\s+)"#
        if matches(bare, text), clearImageTarget(text), matches(#"\b"# + nouns + #"\s+of\s+.+"#, text) { return ImageRequest(prompt: text) }
        return nil
    }
}

/// Keeps cancellation coupled to the actual renderer process, including before launch.
private final class ImageRenderJob: @unchecked Sendable {
    let process = Process()
    private let lock = NSLock()
    private var cancelled = false
    func start() throws {
        lock.lock(); defer { lock.unlock() }
        if cancelled { throw CancellationError() }
        try process.run()
    }
    func cancel() {
        lock.lock(); cancelled = true
        if process.isRunning { process.terminate() }
        lock.unlock()
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) { [self] in
            lock.lock(); defer { lock.unlock() }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
    }
}

/// Native offline image generation. Every renderer exits when its image is done.
final class LocalImageEngine: NSObject, URLSessionTaskDelegate {
    static let modelName = "DreamShaper 8 · local"
    static var directory: URL { Personalization.directory.appendingPathComponent("ImageEngine") }
    private static var binary: URL { directory.appendingPathComponent("bin/sd-cli") }
    private static var requiredFiles: [URL] {
        [binary, directory.appendingPathComponent("models/dreamshaper-8.safetensors")]
    }
    static var isInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: binary.path) && requiredFiles.allSatisfy { FileManager.default.isReadableFile(atPath: $0.path) }
    }
    private lazy var session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }

    func model() async throws -> String {
        guard Self.isInstalled else { throw Attachment.failure("The local image model is not installed yet. Finish PAIGE's image-engine setup, then try again.") }
        return Self.modelName
    }

    private func releaseChatMemory() async throws {
        var request = URLRequest(url: URL(string: LocalEngine.base + "/api/ps")!); request.timeoutInterval = 5
        let data: Data
        do {
            let result = try await session.data(for: request)
            guard (result.1 as? HTTPURLResponse)?.statusCode == 200 else { throw Attachment.failure("Could not check PAIGE's chat-model memory. Retry the connection.") }
            data = result.0
        } catch let error as URLError where error.code == .cannotConnectToHost {
            return
        }
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        for entry in object?["models"] as? [[String: Any]] ?? [] {
            guard let name = entry["name"] as? String else { continue }
            var unload = URLRequest(url: URL(string: LocalEngine.base + "/api/generate")!)
            unload.httpMethod = "POST"; unload.timeoutInterval = 60
            unload.setValue("application/json", forHTTPHeaderField: "Content-Type")
            unload.httpBody = try JSONSerialization.data(withJSONObject: ["model": name, "keep_alive": 0])
            let (_, response) = try await session.data(for: unload)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw Attachment.failure("PAIGE could not release its chat model before drawing. Try again.") }
        }
    }

    func generate(prompt: String, negative: String = "", size: Int = 512, model: String = LocalImageEngine.modelName) async throws -> URL {
        guard model == (try await self.model()), [512, 768, 1024].contains(size) else { throw Attachment.failure("Choose a supported local image size.") }
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Attachment.failure("Describe the image you want to make.") }
        try await releaseChatMemory()
        try Task.checkCancellation()
        let outputs = Personalization.directory.appendingPathComponent("Images")
        try FileManager.default.createDirectory(at: outputs, withIntermediateDirectories: true)
        let output = outputs.appendingPathComponent("PAIGE-\(UUID().uuidString).png")
        let log = output.deletingPathExtension().appendingPathExtension("log")
        let job = ImageRenderJob()
        try await withTaskCancellationHandler {
            try await Task.detached {
                let process = job.process
                let supervisor = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/LanternImage")
                guard FileManager.default.isExecutableFile(atPath: supervisor.path) else { throw Attachment.failure("PAIGE’s image supervisor is missing. Rebuild or reinstall the app.") }
                process.executableURL = supervisor
                process.currentDirectoryURL = Self.directory
                process.arguments = [Self.binary.path, String(ProcessInfo.processInfo.processIdentifier),
                    "-m", Self.directory.appendingPathComponent("models/dreamshaper-8.safetensors").path,
                    "-p", prompt, "-n", negative, "-s", "-1", "-o", output.path,
                    "-W", String(size), "-H", String(size), "--steps", "20", "--cfg-scale", "7.0",
                    "--sampling-method", "euler_a", "--backend", "diffusion=MTL0,vae=MTL0,te=CPU",
                    "--mmap", "--batched-cfg", "off", "--flash-attn", "off,diffusion=on", "--vae-tiling"]
                var env = ProcessInfo.processInfo.environment
                env["GGML_METAL_TENSOR_DISABLE"] = "1"
                process.environment = env
                FileManager.default.createFile(atPath: log.path, contents: nil)
                let handle = try FileHandle(forWritingTo: log); defer { try? handle.close() }
                process.standardInput = FileHandle.nullDevice; process.standardOutput = handle; process.standardError = handle
                try job.start()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else {
                    let details = (try? String(contentsOf: log, encoding: .utf8))?.suffix(1800) ?? ""
                    throw Attachment.failure("The image renderer stopped before finishing. \(details)")
                }
            }.value
        } onCancel: { job.cancel() }
        try Task.checkCancellation()
        guard let bitmap = NSBitmapImageRep(data: try Data(contentsOf: output)), bitmap.pixelsWide == size, bitmap.pixelsHigh == size else {
            throw Attachment.failure("The renderer finished without a readable image. Try again.")
        }
        let metadata: [String: Any] = ["prompt": prompt, "negative_prompt": negative, "model": model, "size": size, "engine": "stable-diffusion.cpp", "local": true]
        try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys]).write(to: output.deletingPathExtension().appendingPathExtension("json"), options: .atomic)
        return output
    }
}

