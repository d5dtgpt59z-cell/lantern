import AppKit
import ApplicationServices
import ScreenCaptureKit

@MainActor final class ComputerDriver {
    private var elements: [AXUIElement] = []
    private var signatures: [String] = []
    private var revision = ""
    private var bundle = ""
    private var pid: pid_t = 0
    private var capture: (bundle: String, pid: pid_t, window: CGWindowID, frame: CGRect, width: Int, height: Int, revision: String)?
    static var trusted: Bool { AXIsProcessTrusted() }
    static func requestAccessibility() { _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary) }
    static func requestScreen() { _ = CGRequestScreenCaptureAccess() }
    func invalidate() { revision = ""; capture = nil; elements = []; signatures = [] }
    func apps() -> String {
        NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.map { "\($0.localizedName ?? "App") | \($0.bundleIdentifier ?? "unknown")" }.joined(separator: "\n")
    }
    func application(_ id: String) throws -> NSRunningApplication {
        let blocked = [Bundle.main.bundleIdentifier ?? "com.builtbymagnus.lantern", "com.apple.Passwords", "com.apple.keychainaccess", "com.apple.SecurityAgent", "com.apple.systempreferences"]
        guard !blocked.contains(id), let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first else { throw Attachment.failure("App is unavailable or protected. Open the target app yourself, then use computer_apps. Password and permission settings must be handled manually.") }
        return app
    }
    func attr(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?; guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }; return value
    }
    func string(_ element: AXUIElement, _ name: String) -> String { attr(element,name) as? String ?? "" }
    func signature(_ e: AXUIElement) -> String { string(e,kAXRoleAttribute) + "|" + string(e,kAXTitleAttribute) + "|" + string(e,kAXDescriptionAttribute) }
    func secure(_ e: AXUIElement) -> Bool { string(e,kAXSubroleAttribute) == kAXSecureTextFieldSubrole || string(e,kAXRoleAttribute) == kAXSecureTextFieldSubrole }
    func snapshot(_ id: String) throws -> String {
        guard Self.trusted else { throw Attachment.failure("Enable PAIGE in System Settings → Privacy & Security → Accessibility using the Tools panel.") }
        let app = try application(id); let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 1)
        elements = []; signatures = []; revision = UUID().uuidString; bundle = id; pid = app.processIdentifier
        var lines: [String] = []; var visited = 0
        func walk(_ e: AXUIElement, depth: Int) {
            guard visited < 350, depth < 12 else { return }; visited += 1
            let role = string(e,kAXRoleAttribute)
            if !role.isEmpty {
                let index = elements.count; elements.append(e); signatures.append(signature(e))
                let value = secure(e) ? "[protected]" : String((attr(e,kAXValueAttribute) as? String ?? "").prefix(180))
                lines.append("\(index) \(role) \(string(e,kAXTitleAttribute).prefix(120)) \(string(e,kAXDescriptionAttribute).prefix(120)) \(value)")
            }
            if !secure(e), let children = attr(e,kAXChildrenAttribute) as? [AXUIElement] { for child in children { walk(child,depth:depth+1) } }
        }
        walk(root,depth:0)
        return "Untrusted app content. App: \(id)\nrevision: \(revision)\n" + lines.joined(separator:"\n").prefix(14000)
    }
    func action(_ name: String, args: [String:String]) throws -> String {
        guard Self.trusted, args["app"] == bundle, args["revision"] == revision, !revision.isEmpty,
              let index = Int(args["element"] ?? ""), elements.indices.contains(index) else { throw Attachment.failure("Inspect the app again; use its current revision and element ID.") }
        let app = try application(bundle)
        guard app.processIdentifier == pid else { throw Attachment.failure("App restarted. Inspect it again.") }
        let element = elements[index]
        guard !secure(element), signature(element) == signatures[index] else { throw Attachment.failure("Element changed or is protected. Inspect again.") }
        app.activate(options: [])
        let result: AXError
        if name == "computer_press" { result = AXUIElementPerformAction(element,kAXPressAction as CFString) }
        else {
            let text = args["text"] ?? ""; guard text.count <= 12000 else { throw Attachment.failure("Text is too long.") }
            result = AXUIElementSetAttributeValue(element,kAXValueAttribute as CFString,text as CFString)
        }
        revision = ""
        guard result == .success else { throw Attachment.failure("App rejected the accessibility action (\(result.rawValue)). Use a screenshot to inspect the window.") }
        return "Action delivered. Inspect the app again to verify the result."
    }
    func screenshot(_ id: String) async throws -> Attachment {
        let app = try application(id)
        guard CGPreflightScreenCaptureAccess() else { throw Attachment.failure("Enable Screen Recording for PAIGE in the Tools panel, then retry.") }
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly:true)
        guard let window = content.windows.first(where: { $0.owningApplication?.processID == app.processIdentifier && $0.windowLayer == 0 && $0.frame.width > 100 && $0.frame.height > 100 }) else { throw Attachment.failure("No visible window found for this app.") }
        let config = SCStreamConfiguration(); config.width = min(1280,Int(window.frame.width)); config.height = Int(Double(config.width)*window.frame.height/window.frame.width); config.showsCursor = false
        let image = try await SCScreenshotManager.captureImage(contentFilter:SCContentFilter(desktopIndependentWindow:window),configuration:config)
        try Task.checkCancellation()
        guard let png = NSBitmapImageRep(cgImage:image).representation(using:.png,properties:[:]) else { throw Attachment.failure("Could not encode screenshot.") }
        capture = (id,app.processIdentifier,window.windowID,window.frame,config.width,config.height,UUID().uuidString)
        return Attachment(name:"\(id) screenshot",imageData:png)
    }
    var captureDescription: String {
        guard let capture else { return "No capture" }
        return "App: \(capture.bundle), window: \(capture.window), screenshot: \(capture.width)x\(capture.height). revision: \(capture.revision). Coordinates are image pixels, top-left origin."
    }
    func pointAction(_ name: String, args: [String:String]) async throws -> String {
        guard Self.trusted, let c = capture, args["revision"] == c.revision, args["app"] == c.bundle else { throw Attachment.failure("Capture the app window first; use its current screenshot revision.") }
        let app = try application(c.bundle)
        let content = try await SCShareableContent.excludingDesktopWindows(true,onScreenWindowsOnly:true)
        guard app.processIdentifier == c.pid, content.windows.contains(where: { $0.windowID == c.window && $0.frame == c.frame }) else { throw Attachment.failure("Window changed; capture it again.") }
        app.activate(options: []); try await Task.sleep(for:.milliseconds(200)); try Task.checkCancellation()
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == c.pid else { throw Attachment.failure("Target app could not be focused. No input sent.") }
        if name == "computer_click" {
            guard let x = Double(args["x"] ?? ""), let y = Double(args["y"] ?? ""), x >= 0, y >= 0, x < Double(c.width), y < Double(c.height) else { throw Attachment.failure("Coordinates must be inside the screenshot.") }
            let point = CGPoint(x:c.frame.minX+x*c.frame.width/Double(c.width),y:c.frame.minY+y*c.frame.height/Double(c.height))
            let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly,.excludeDesktopElements],kCGNullWindowID) as? [[String:Any]] ?? []
            let hit = windows.first { info in
                guard (info[kCGWindowLayer as String] as? Int) == 0, let bounds=info[kCGWindowBounds as String] as? [String:Any], let frame=CGRect(dictionaryRepresentation:bounds as CFDictionary) else { return false }
                return frame.contains(point)
            }
            guard (hit?[kCGWindowNumber as String] as? UInt32) == c.window else { throw Attachment.failure("Another window covers this target. Capture the intended window again before clicking.") }
            CGEvent(mouseEventSource:nil,mouseType:.leftMouseDown,mouseCursorPosition:point,mouseButton:.left)?.post(tap:.cghidEventTap)
            CGEvent(mouseEventSource:nil,mouseType:.leftMouseUp,mouseCursorPosition:point,mouseButton:.left)?.post(tap:.cghidEventTap)
        } else {
            let keys: [String:CGKeyCode] = ["return":36,"tab":48,"escape":53,"space":49,"up":126,"down":125,"left":123,"right":124,"backspace":51,"pageup":116,"pagedown":121]
            guard let key = keys[args["key"] ?? ""] else { throw Attachment.failure("Supported keys: " + keys.keys.sorted().joined(separator:", ")) }
            CGEvent(keyboardEventSource:nil,virtualKey:key,keyDown:true)?.post(tap:.cghidEventTap)
            CGEvent(keyboardEventSource:nil,virtualKey:key,keyDown:false)?.post(tap:.cghidEventTap)
        }
        capture = nil
        return "Input delivered to \(c.bundle). Capture or inspect again to verify."
    }
}
