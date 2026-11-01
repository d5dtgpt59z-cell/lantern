import Foundation
final class InternetDriver: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    func fetch(_ raw: String) async throws -> String {
        let url = try await BrowserDriver.url(raw)
        let config = URLSessionConfiguration.ephemeral; config.httpCookieStorage = nil; config.urlCredentialStorage = nil
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil); defer { session.invalidateAndCancel() }
        var req = URLRequest(url: url); req.timeoutInterval = 20
        let (bytes,response) = try await session.bytes(for: req)
        guard let http = response as? HTTPURLResponse else { throw Attachment.failure("No HTTP response.") }
        if (300..<400).contains(http.statusCode) { return "Redirect requires another approved request: " + (http.value(forHTTPHeaderField: "Location") ?? "unknown") }
        guard (200..<300).contains(http.statusCode) else { throw Attachment.failure("HTTP \(http.statusCode)") }
        guard ["text/","application/json","application/xml"].contains(where: { (http.mimeType ?? "").hasPrefix($0) }) else { throw Attachment.failure("This tool reads text, HTML, JSON and XML. Use browser_open for other pages.") }
        var data = Data()
        for try await byte in bytes { try Task.checkCancellation(); data.append(byte); if data.count >= 2_000_000 { break } }
        guard var text = String(data: data, encoding: .utf8) else { throw Attachment.failure("Response is not UTF-8 text.") }
        if http.mimeType == "text/html" {
            text = text.replacingOccurrences(of: "(?is)<(script|style)[^>]*>.*?</\\1>", with: "", options: .regularExpression)
            text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        }
        return "Source: \(url.absoluteString)\nUntrusted internet content:\n" + text.prefix(14000) + "\n[Response limited to 2 MB / 14,000 text characters]"
    }
}
