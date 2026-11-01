import SwiftUI
import WebKit

/// A narrow renderer boundary: the web page receives ephemeral session tokens
/// and PCM speech only. It never receives provider keys, model access, or tools.
@MainActor final class LiveAvatarBridge: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    let webView: WKWebView
    var onReady: (() -> Void)?
    var onClosed: ((String?) -> Void)?
    var onSpeechEnded: (() -> Void)?
    var onSpeechStarted: (() -> Void)?
    var onError: ((String) -> Void)?
    @Published private(set) var pageReady = false
    private var pageError: Error?
    private var operationID = UUID()
    private var pageURL: URL?
    private var messageProxy: LiveAvatarMessageProxy?

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.allowsAirPlayForMediaPlayback = false
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.underPageBackgroundColor = .black
        let proxy = LiveAvatarMessageProxy(owner: self)
        messageProxy = proxy
        configuration.userContentController.add(proxy, name: "paigeLive")
        loadPage()
    }

    private func loadPage() {
        pageReady = false
        pageError = nil
        guard let directory = Bundle.main.resourceURL?.appendingPathComponent("LiveAvatar", isDirectory: true),
              FileManager.default.fileExists(atPath: directory.appendingPathComponent("index.html").path),
              FileManager.default.fileExists(atPath: directory.appendingPathComponent("avatar.js").path) else {
            pageError = LiveAvatarBridgeError.message("The live avatar renderer is missing from PAIGE. Rebuild the app.")
            return
        }
        let url = directory.appendingPathComponent("index.html")
        pageURL = url
        webView.loadFileURL(url, allowingReadAccessTo: directory)
    }

    func start(sessionToken: String) async throws {
        let id = UUID()
        operationID = id
        if pageURL == nil { loadPage() }
        for _ in 0..<100 {
            try Task.checkCancellation()
            guard operationID == id else { throw CancellationError() }
            if let pageError { throw pageError }
            if pageReady { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        guard pageReady else { throw LiveAvatarBridgeError.message("The live avatar renderer did not load.") }
        do {
            _ = try await webView.callAsyncJavaScript(
                "return await window.paigeAvatar.start(token);",
                arguments: ["token": sessionToken], in: nil, contentWorld: .page)
            guard operationID == id, !Task.isCancelled else {
                await stop()
                throw CancellationError()
            }
        } catch is CancellationError { throw CancellationError() }
        catch {
            guard operationID == id else { throw CancellationError() }
            throw LiveAvatarBridgeError.message("Could not open Anam’s live connection. Check your connection, avatar, and free minutes.")
        }
    }

    /// PCM16 little-endian mono at 24 kHz, representing one complete reply.
    func sendAudio(_ data: Data) async throws {
        guard data.count >= 2, data.count.isMultiple(of: 2), data.count <= 2_880_000 else {
            throw LiveAvatarBridgeError.message("Paige’s speech must be PCM16 mono audio no longer than 60 seconds.")
        }
        let id = operationID
        try Task.checkCancellation()
        guard pageReady else { throw LiveAvatarBridgeError.message("The live avatar is not connected.") }
        do {
            _ = try await webView.callAsyncJavaScript(
                "return await window.paigeAvatar.sendAudio(audio);",
                arguments: ["audio": data.base64EncodedString()], in: nil, contentWorld: .page)
            guard operationID == id, !Task.isCancelled else { throw CancellationError() }
        } catch is CancellationError { throw CancellationError() }
        catch { throw LiveAvatarBridgeError.message("Could not send Paige’s speech to the live avatar.") }
    }

    func interrupt() {
        guard pageReady else { return }
        webView.evaluateJavaScript("window.paigeAvatar?.interrupt();", completionHandler: nil)
    }

    /// Rearm the native microphone only after old returned audio has stopped.
    /// The page mutes output immediately, sends the interruption, and confirms
    /// silence from the remote stream; unknown or stalled playback fails closed.
    func interruptAndWait() async throws {
        guard pageReady else { return }
        let id = operationID
        do {
            _ = try await webView.callAsyncJavaScript(
                "return await window.paigeAvatar?.interruptAndWait();",
                arguments: [:], in: nil, contentWorld: .page)
            guard operationID == id, !Task.isCancelled else { throw CancellationError() }
        } catch is CancellationError { throw CancellationError() }
        catch {
            guard operationID == id else { throw CancellationError() }
            throw LiveAvatarBridgeError.message("Paige’s interrupted audio did not stop. End Live and try again.")
        }
    }

    func stop() async {
        operationID = UUID()
        guard pageReady else { return }
        _ = try? await webView.callAsyncJavaScript(
            "return await window.paigeAvatar?.stop();", arguments: [:], in: nil, contentWorld: .page)
    }

    fileprivate func receive(_ message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame,
              message.frameInfo.request.url?.standardizedFileURL == pageURL?.standardizedFileURL,
              let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        let text = (body["message"] as? String).map { String($0.prefix(500)) }
        switch type {
        case "page-ready": pageReady = true
        case "ready": onReady?()
        case "closed": onClosed?(text)
        case "speech-started": onSpeechStarted?()
        case "speech-ended": onSpeechEnded?()
        case "error": onError?(text ?? "The live connection encountered a problem.")
        default: break
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        pageReady = false
        pageError = LiveAvatarBridgeError.message("Paige’s live renderer could not load.")
        onError?("Paige’s live renderer could not load.")
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        self.webView(webView, didFail: navigation, withError: error)
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        operationID = UUID()
        pageReady = false
        onError?("Paige’s live renderer stopped. End Live and try again.")
        loadPage()
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // Remote content is media only. It cannot replace this trusted bridge page.
        decisionHandler(navigationAction.request.url?.standardizedFileURL == pageURL?.standardizedFileURL ? .allow : .cancel)
    }
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(.deny)
    }
}

@MainActor private final class LiveAvatarMessageProxy: NSObject, WKScriptMessageHandler {
    weak var owner: LiveAvatarBridge?
    init(owner: LiveAvatarBridge) { self.owner = owner }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        owner?.receive(message)
    }
}

private enum LiveAvatarBridgeError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let message) = self { return message }; return nil }
}

struct LiveAvatarVideo: NSViewRepresentable {
    let bridge: LiveAvatarBridge
    func makeNSView(context: Context) -> WKWebView { bridge.webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
