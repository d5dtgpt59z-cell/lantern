import Foundation
import Combine
import Security
import LocalAuthentication

/// Credentials stay in native code. Only short-lived Anam tokens enter the avatar view.
@MainActor final class LiveAccount: ObservableObject {
    @Published var avatarID: String { didSet { defaults.set(avatarID, forKey: "live.anamAvatarID") } }
    @Published var useElevenLabs: Bool { didSet { defaults.set(useElevenLabs, forKey: "live.useElevenLabs") } }
    @Published var elevenVoiceID: String { didSet { defaults.set(elevenVoiceID, forKey: "live.elevenVoiceID") } }

    static let defaultElevenVoiceID = "EXAVITQu4vr4xnSDxMaL" // Sarah; verified with this account's TTS permission.
    private let defaults: UserDefaults
    private let session: URLSession
    private let credentialStore: LiveCredentialStore
    private let environment: [String: String]
    private let dotenvURL: URL?

    init(defaults: UserDefaults = .standard, session: URLSession? = nil,
         credentialStore: LiveCredentialStore = LiveKeychainStore(),
         environment: [String: String] = ProcessInfo.processInfo.environment,
         dotenvURL: URL? = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".hermes/.env")) {
        self.defaults = defaults
        self.credentialStore = credentialStore
        self.environment = environment
        self.dotenvURL = dotenvURL
        avatarID = defaults.string(forKey: "live.anamAvatarID") ?? environment["ANAM_AVATAR_ID"] ?? ""
        useElevenLabs = defaults.object(forKey: "live.useElevenLabs") == nil ? true : defaults.bool(forKey: "live.useElevenLabs")
        elevenVoiceID = defaults.string(forKey: "live.elevenVoiceID") ?? environment["ELEVENLABS_VOICE_ID"] ?? Self.defaultElevenVoiceID
        if let session { self.session = session }
        else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 20
            configuration.timeoutIntervalForResource = 20
            configuration.urlCache = nil
            configuration.httpCookieStorage = nil
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            self.session = URLSession(configuration: configuration, delegate: LiveNetworkDelegate(), delegateQueue: nil)
        }
    }

    var hasAnamKey: Bool { (try? secret("ANAM_API_KEY")) != nil }
    var hasElevenKey: Bool { (try? secret("ELEVENLABS_API_KEY")) != nil }

    func saveAnamKey(_ key: String) throws { try save(key, account: "ANAM_API_KEY", provider: "Anam") }
    func saveElevenKey(_ key: String) throws { try save(key, account: "ELEVENLABS_API_KEY", provider: "ElevenLabs") }

    /// Call only after the user explicitly starts a live session. There is no retry or background connection.
    func makeSessionToken() async throws -> String {
        guard let key = try secret("ANAM_API_KEY") else { throw LiveAccountError.message("Add your Anam API key in Live settings.") }
        let avatar = avatarID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.validIdentifier(avatar) else { throw LiveAccountError.message("Paste Paige's avatar ID from Anam Lab into Live settings.") }
        var request = URLRequest(url: URL(string: "https://api.anam.ai/v1/auth/session-token")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "personaConfig": ["avatarId": avatar, "avatarModel": "cara-4.1-express", "enableAudioPassthrough": true]
        ])
        let (data, response) = try await boundedResponse(request, limit: 65_536, provider: "Anam")
        guard (200..<300).contains(response.statusCode) else { throw Self.providerError("Anam", status: response.statusCode, data: data) }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = object["sessionToken"] as? String,
              !token.isEmpty, token.utf8.count <= 32_768,
              token.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            throw LiveAccountError.message("Anam returned an unreadable session token. Try Start live again.")
        }
        return token
    }

    /// Returns signed 16-bit little-endian PCM, 24 kHz, mono. The avatar plays its synchronized returned audio.
    func synthesizeEleven(_ text: String) async throws -> Data {
        guard useElevenLabs else { throw LiveAccountError.message("Choose ElevenLabs in Live settings before starting voice.") }
        guard let key = try secret("ELEVENLABS_API_KEY") else { throw LiveAccountError.message("Add your ElevenLabs API key in Live settings.") }
        let voice = elevenVoiceID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.validIdentifier(voice) else { throw LiveAccountError.message("Choose an ElevenLabs voice ID in Live settings.") }
        let phrase = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !phrase.isEmpty, phrase.count <= 4_000 else { throw LiveAccountError.message("Keep each spoken response between 1 and 4,000 characters.") }
        var components = URLComponents(string: "https://api.elevenlabs.io")!
        components.path = "/v1/text-to-speech/" + voice
        components.queryItems = [URLQueryItem(name: "output_format", value: "pcm_24000")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue(key, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/pcm", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["text": phrase, "model_id": "eleven_flash_v2_5"])
        let (data, response) = try await boundedResponse(request, limit: 8_640_000, provider: "ElevenLabs")
        guard (200..<300).contains(response.statusCode) else { throw Self.providerError("ElevenLabs", status: response.statusCode, data: data) }
        let contentType = response.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        guard contentType.hasPrefix("audio/pcm") || contentType.hasPrefix("application/octet-stream"),
              !data.isEmpty, data.count.isMultiple(of: 2) else {
            throw LiveAccountError.message("ElevenLabs did not return valid PCM speech. Check the voice ID, then try again.")
        }
        return data
    }

    private func save(_ key: String, account: String, provider: String) throws {
        guard let cleaned = Self.cleanKey(key) else { throw LiveAccountError.message("Paste a non-empty \(provider) API key without spaces or line breaks.") }
        try credentialStore.write(cleaned, account: account)
        objectWillChange.send()
    }

    private func secret(_ name: String) throws -> String? {
        if let value = try credentialStore.read(account: name), let key = Self.cleanKey(value) { return key }
        if let value = environment[name], let key = Self.cleanKey(value) { return key }
        guard let dotenvURL,
              let values = try? dotenvURL.resourceValues(forKeys: [.fileSizeKey]),
              let size = values.fileSize, size <= 131_072,
              let data = try? Data(contentsOf: dotenvURL), data.count <= 131_072,
              let source = String(data: data, encoding: .utf8) else { return nil }
        return Self.dotenvValue(name, source: source).flatMap(Self.cleanKey)
    }

    // Reads literal assignments only; never sources a shell file or expands substitutions.
    static func dotenvValue(_ name: String, source: String) -> String? {
        for original in source.split(whereSeparator: \.isNewline) {
            var line = original.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("export ") { line = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces) }
            guard let separator = line.firstIndex(of: "="), line[..<separator].trimmingCharacters(in: .whitespaces) == name else { continue }
            var value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            if let first = value.first, first == "\"" || first == "'" {
                guard value.count >= 2, value.last == first else { return nil }
                value = String(value.dropFirst().dropLast())
            } else if let comment = value.range(of: " #") { value = String(value[..<comment.lowerBound]).trimmingCharacters(in: .whitespaces) }
            return value
        }
        return nil
    }

    private static func cleanKey(_ value: String) -> String? {
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, key.utf8.count <= 4_096,
              key.unicodeScalars.allSatisfy({ (33...126).contains($0.value) }) else { return nil }
        return key
    }

    private static func validIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 128 && value.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) && $0.isASCII || $0 == "_" || $0 == "-"
        }
    }

    private func boundedResponse(_ request: URLRequest, limit: Int, provider: String) async throws -> (Data, HTTPURLResponse) {
        do {
            try Task.checkCancellation()
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse else { throw LiveAccountError.message("\(provider) returned an unreadable response.") }
            let maximum = (200..<300).contains(http.statusCode) ? limit : min(limit, 65_536)
            guard response.expectedContentLength <= Int64(maximum) else { throw LiveAccountError.message("\(provider)'s response was too large. Try a shorter response.") }
            var data = Data()
            data.reserveCapacity(min(maximum, 65_536))
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < maximum else { throw LiveAccountError.message("\(provider)'s response was too large. Try a shorter response.") }
                data.append(byte)
            }
            try Task.checkCancellation()
            return (data, http)
        } catch is CancellationError { throw CancellationError() }
        catch let error as LiveAccountError { throw error }
        catch let error as URLError where error.code == .cancelled { throw CancellationError() }
        catch let error as URLError where error.code == .timedOut { throw LiveAccountError.message("\(provider) did not respond within 20 seconds. Check your connection, then try again.") }
        catch { throw LiveAccountError.message("Could not connect to \(provider). Check your internet connection, then try again.") }
    }

    private static func providerError(_ provider: String, status: Int, data: Data) -> LiveAccountError {
        // Inspect known failure categories, but never display provider bodies that might echo credentials or text.
        let body = String(data: data.prefix(65_536), encoding: .utf8)?.lowercased() ?? ""
        if body.contains("missing_permissions") || body.contains("missing_permission") {
            return .message("\(provider)'s key is missing permission. Enable \(provider == "ElevenLabs" ? "Text to Speech" : "avatar sessions") for this key, then try again.")
        }
        if status == 402 || ["quota_exceeded", "insufficient_credit", "insufficient_balance", "minute_limit", "minutes_exhausted", "allowance_exhausted"].contains(where: body.contains) {
            return .message(provider == "Anam" ? "Anam's available minutes are exhausted. Check your allowance in Anam Lab before starting another session." : "ElevenLabs speech credits are exhausted. Check your ElevenLabs allowance before trying again.")
        }
        switch status {
        case 401: return .message("\(provider) rejected the API key. Save a valid key in Live settings.")
        case 403: return .message("\(provider) did not allow this request. Check the key's permissions and your account allowance.")
        case 400, 404, 422:
            return .message(provider == "Anam" ? "Anam could not use this avatar. Check Paige's avatar ID and Cara-4.1 compatibility in Anam Lab." : "ElevenLabs could not use this voice. Check the voice ID and your access to it.")
        case 409, 429: return .message("\(provider) is at its session or request limit. End other sessions or wait, then try again.")
        case 500...599: return .message("\(provider) is temporarily unavailable. Try again later.")
        default: return .message("\(provider) could not complete this request (HTTP \(status)). Check your account settings.")
        }
    }
}

enum LiveAccountError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(message) = self { return message }; return nil }
}

protocol LiveCredentialStore {
    func read(account: String) throws -> String?
    func write(_ value: String, account: String) throws
}

struct LiveKeychainStore: LiveCredentialStore {
    private let service = "com.builtbymagnus.lantern.live"
    private func query(_ account: String) -> [String: Any] {
        let context = LAContext()
        context.interactionNotAllowed = true
        return [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                kSecAttrAccount as String: account, kSecUseAuthenticationContext as String: context]
    }
    func read(account: String) throws -> String? {
        var request = query(account)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            throw LiveAccountError.message("PAIGE could not read its live credentials. Unlock your login Keychain and try again.")
        }
        return value
    }
    func write(_ value: String, account: String) throws {
        let request = query(account)
        let data = Data(value.utf8)
        var status = SecItemUpdate(request as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var entry = request
            entry[kSecValueData as String] = data
            entry[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(entry as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw LiveAccountError.message("PAIGE could not save this key securely. Unlock your login Keychain, then try again.") }
    }
}

private final class LiveNetworkDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
