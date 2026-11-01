import Foundation

private final class MemoryLiveCredentials: LiveCredentialStore {
    var values: [String: String] = [:]
    func read(account: String) throws -> String? { values[account] }
    func write(_ value: String, account: String) throws { values[account] = value }
}

private final class LiveMockProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, [String: String], Data))!
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, headers, data) = try Self.handler(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

/// No network calls, real credentials, Keychain writes, or existing chat storage.
@main struct LiveAccountChecks {
    @MainActor static func main() async throws {
        var count = 0
        func check(_ value: Bool, _ label: String) throws {
            count += 1
            if !value { throw LiveAccountError.message("FAIL: " + label) }
        }
        let suite = "paige.live.checks." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LiveMockProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let credentials = MemoryLiveCredentials()
        let account = LiveAccount(defaults: defaults, session: session, credentialStore: credentials,
                                  environment: ["ELEVENLABS_API_KEY": "environment-test-key"], dotenvURL: nil)
        try check(account.useElevenLabs, "ElevenLabs is the default voice provider")
        try check(account.elevenVoiceID == LiveAccount.defaultElevenVoiceID, "verified female voice is the initial voice")
        try check(account.hasElevenKey && !account.hasAnamKey, "environment credentials remain usable without saving plaintext")
        try check(LiveAccount.dotenvValue("KEY", source: "# KEY=ignored\nexport KEY='literal-value'\n") == "literal-value", "literal dotenv assignment")
        try check(LiveAccount.dotenvValue("KEY", source: "OTHER=one\nKEY=literal # comment\n") == "literal", "dotenv comments")
        try check(LiveAccount.dotenvValue("KEY", source: "KEY='unterminated") == nil, "unterminated dotenv quotes rejected")
        do { try account.saveAnamKey("one\ntwo"); try check(false, "embedded newline rejected") }
        catch { try check(credentials.values["ANAM_API_KEY"] == nil, "invalid key never stored") }
        try account.saveAnamKey("  native-test-key  ")
        try check(credentials.values["ANAM_API_KEY"] == "native-test-key", "key stored through secure credential interface")
        account.avatarID = "test-avatar-id"
        try check(defaults.string(forKey: "live.anamAvatarID") == "test-avatar-id", "avatar selection persists")
        try check(defaults.string(forKey: "ANAM_API_KEY") == nil, "secrets never enter UserDefaults")

        var tokenRequests = 0
        LiveMockProtocol.handler = { request in
            tokenRequests += 1
            guard request.url?.absoluteString == "https://api.anam.ai/v1/auth/session-token",
                  request.httpMethod == "POST", request.timeoutInterval == 20,
                  request.value(forHTTPHeaderField: "Authorization") == "Bearer native-test-key" else {
                throw LiveAccountError.message("bad token request")
            }
            let raw = request.httpBody ?? request.httpBodyStream.flatMap { stream -> Data? in
                stream.open(); defer { stream.close() }
                var result = Data(); var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable { let read = stream.read(&buffer, maxLength: buffer.count); if read <= 0 { break }; result.append(contentsOf: buffer.prefix(read)) }
                return result
            }
            let object = raw.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let persona = object?["personaConfig"] as? [String: Any]
            guard persona?["avatarId"] as? String == "test-avatar-id",
                  persona?["avatarModel"] as? String == "cara-4.1-express",
                  persona?["enableAudioPassthrough"] as? Bool == true else { throw LiveAccountError.message("wrong persona configuration") }
            return (200, ["Content-Type": "application/json"], Data("{\"sessionToken\":\"ephemeral-test-token\"}".utf8))
        }
        let token = try await account.makeSessionToken()
        try check(token == "ephemeral-test-token" && tokenRequests == 1, "one explicit native-only token exchange uses passthrough")

        LiveMockProtocol.handler = { request in
            guard request.url?.host == "api.elevenlabs.io",
                  request.url?.path == "/v1/text-to-speech/" + LiveAccount.defaultElevenVoiceID,
                  request.url?.query == "output_format=pcm_24000",
                  request.value(forHTTPHeaderField: "xi-api-key") == "environment-test-key" else { throw LiveAccountError.message("wrong speech request") }
            return (200, ["Content-Type": "audio/pcm"], Data([1, 0, 2, 0]))
        }
        let pcm = try await account.synthesizeEleven("Hello.")
        try check(pcm == Data([1, 0, 2, 0]), "speech returns raw PCM")
        account.useElevenLabs = false
        do { _ = try await account.synthesizeEleven("Hello."); try check(false, "provider guard") }
        catch { try check(error.localizedDescription.contains("Choose ElevenLabs"), "disabled provider cannot make a paid call") }
        account.useElevenLabs = true

        var failures = 0
        LiveMockProtocol.handler = { _ in
            failures += 1
            return (401, ["Content-Type": "application/json"], Data("{\"detail\":{\"status\":\"missing_permissions\",\"message\":\"environment-test-key\"}}".utf8))
        }
        do { _ = try await account.synthesizeEleven("Hello."); try check(false, "permission rejection") }
        catch {
            try check(error.localizedDescription.contains("Text to Speech") && !error.localizedDescription.contains("environment-test-key"), "permission message is actionable and sanitized")
            try check(failures == 1, "provider rejection is not retried")
        }
        LiveMockProtocol.handler = { _ in (402, [:], Data("quota_exceeded".utf8)) }
        do { _ = try await account.makeSessionToken(); try check(false, "quota rejection") }
        catch { try check(error.localizedDescription.contains("minutes are exhausted"), "allowance exhaustion is clear") }
        LiveMockProtocol.handler = { _ in (200, ["Content-Type": "audio/pcm"], Data([1])) }
        do { _ = try await account.synthesizeEleven("Hello."); try check(false, "malformed PCM") }
        catch { try check(error.localizedDescription.contains("valid PCM"), "odd-byte PCM is rejected") }
        LiveMockProtocol.handler = { _ in (200, ["Content-Length": "65537"], Data()) }
        do { _ = try await account.makeSessionToken(); try check(false, "large token response") }
        catch { try check(error.localizedDescription.contains("too large"), "response size bound") }
        print("Live account checks passed (\(count)).")
    }
}
