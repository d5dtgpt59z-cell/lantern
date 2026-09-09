import Foundation
import AppKit

/// A loopback-only client. Redirects must never turn a local prompt into a cloud request.
final class LocalImageEngine: NSObject, URLSessionTaskDelegate {
    private lazy var session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }

    private func request(_ url: String, body: [String: Any]? = nil, timeout: Double = 5) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: url)!)
        request.timeoutInterval = timeout
        if let body {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await session.data(for: request)
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw Attachment.failure(object["detail"] as? String ?? "The local image engine could not complete this request.")
        }
        return object
    }

    func model() async throws -> String {
        let options = try await request("http://127.0.0.1:7860/sdapi/v1/options")
        guard let model = options["model"] as? String, model.hasSuffix(".ckpt"), !model.contains(":"), !model.contains("/") else {
            throw Attachment.failure("Select a downloaded local image model in Draw Things. Cloud models are not supported here.")
        }
        return model
    }

    func generate(prompt: String, negative: String, size: Int, model: String) async throws -> URL {
        // Release the chat model before the image engine uses unified memory.
        let running = try await request("http://127.0.0.1:11434/api/ps")
        for entry in running["models"] as? [[String: Any]] ?? [] {
            if let name = entry["name"] as? String {
                _ = try await request("http://127.0.0.1:11434/api/generate", body: ["model": name, "keep_alive": 0], timeout: 30)
            }
        }
        guard try await self.model() == model else { throw Attachment.failure("The image model changed. Reconnect before generating.") }
        let body: [String: Any] = ["prompt": prompt, "negative_prompt": negative, "model": model,
            "width": size, "height": size, "batch_count": 1, "batch_size": 1, "seed": -1,
            "loras": [], "controls": [], "hires_fix": false, "upscaler": NSNull(), "refiner_model": NSNull()]
        let result = try await request("http://127.0.0.1:7860/sdapi/v1/txt2img", body: body, timeout: 1800)
        guard let encoded = (result["images"] as? [String])?.first,
              let data = Data(base64Encoded: encoded), let bitmap = NSBitmapImageRep(data: data),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            throw Attachment.failure("Draw Things returned no readable image.")
        }
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Lantern/Images")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let output = directory.appendingPathComponent("Lantern-\(UUID().uuidString).png")
        try png.write(to: output, options: .atomic)
        try JSONSerialization.data(withJSONObject: ["prompt": prompt, "negative_prompt": negative, "model": model, "size": size], options: [.prettyPrinted, .sortedKeys]).write(to: output.deletingPathExtension().appendingPathExtension("json"), options: .atomic)
        return output
    }
}
