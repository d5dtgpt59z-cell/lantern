import AppKit
import Foundation
struct AgentTools {
    static func schema(_ name:String,_ desc:String,_ args:[String:String]) -> [String:Any] { ["type":"function","function":["name":name,"description":desc,"parameters":["type":"object","properties":args.mapValues { ["type":"string","description":$0] },"required":Array(args.keys)]]] }
}
@main struct Probe {
    @MainActor static func main() {
        let app = NSApplication.shared; app.setActivationPolicy(.regular)
        DispatchQueue.main.async {
            Task { @MainActor in
                let tools = AutomationTools()
                var results:[String] = []
                func check(_ condition:Bool,_ text:String) throws { guard condition else { throw Attachment.failure("FAIL: " + text) }; results.append("PASS: " + text) }
                @MainActor func act(_ name:String,_ args:[String:String] = [:]) async throws -> (String,Attachment?) {
                    let call = ToolCall(function:.init(name:name,arguments:args)); let approval = try tools.inspect(call)
                    return try await tools.perform(call,approval:approval)
                }
                do {
                    let (fetched,_) = try await act("web_fetch",["url":"http://127.0.0.1:18765/text"])
                    try check(fetched.contains("Internet fixture"),"bounded HTTP fetch")
                    let (redirect,_) = try await act("web_fetch",["url":"http://127.0.0.1:18765/redirect"])
                    try check(redirect.contains("Redirect requires"),"redirect does not silently follow")
                    do { _ = try BrowserDriver.url("file:///etc/passwd"); throw Attachment.failure("FAIL scheme accepted") } catch { try check(error.localizedDescription.contains("http"),"local file URL rejected") }
                    let (snapshot,_) = try await act("browser_open",["url":"http://127.0.0.1:18765/"])
                    func state(_ text:String) throws -> [String:Any] { let json=String(text.dropFirst(text.firstIndex(of:"{")!.utf16Offset(in:text))); return try JSONSerialization.jsonObject(with:Data(json.utf8)) as! [String:Any] }
                    var current = try state(snapshot)
                    let nodes = current["elements"] as! [[String:Any]]
                    let field = nodes.first { ($0["tag"] as? String) == "INPUT" }!["id"] as! Int
                    let oldRevision = current["revision"] as! String
                    let (typed,_) = try await act("browser_type",["element":String(field),"revision":oldRevision,"text":"Lantern test"])
                    current = try state(typed)
                    try check((try await tools.browser.js("document.querySelector('input').value")) as? String == "Lantern test","browser enters exact text")
                    do { _ = try await act("browser_click",["element":"1","revision":oldRevision]); throw Attachment.failure("FAIL stale accepted") } catch { try check(error.localizedDescription.contains("revision"),"stale browser target rejected") }
                    let button = (current["elements"] as! [[String:Any]]).first { ($0["tag"] as? String) == "BUTTON" }!["id"] as! Int
                    let (clicked,_) = try await act("browser_click",["element":String(button),"revision":current["revision"] as! String])
                    try check(clicked.contains("Clicked Lantern test"),"browser click updates page")
                    let (_,screenshot) = try await act("browser_screenshot")
                    try check((screenshot?.imageData?.count ?? 0) > 1000,"browser screenshot captured")
                    if let data=screenshot?.imageData { try data.write(to:URL(fileURLWithPath:CommandLine.arguments[1]).appendingPathComponent("browser-test.png")) }
                    tools.browserEnabled = false
                    do { _ = try await act("browser_read"); throw Attachment.failure("FAIL capability off accepted") } catch { try check(error.localizedDescription.contains("off"),"disabled browser denied") }
                    let call=ToolCall(function:.init(name:"web_fetch",arguments:["url":"http://127.0.0.1:18765/text"]))
                    do { _ = try await tools.perform(call,approval:nil); throw Attachment.failure("FAIL no approval accepted") } catch { try check(error.localizedDescription.contains("approved"),"missing approval denied") }
                    tools.browserEnabled = true
                    let task = Task { try await act("browser_open",["url":"http://127.0.0.1:18765/slow"]) }
                    try await Task.sleep(for:.milliseconds(100)); task.cancel(); tools.stop()
                    do { _ = try await task.value; throw Attachment.failure("FAIL cancellation accepted") } catch { try check(error is CancellationError,"cancellation stops browser tool") }
                    try check(!ComputerDriver.trusted || !tools.computer.apps().isEmpty,"Mac permissions checked without requesting access")
                    results.append("DONE")
                } catch { results.append(error.localizedDescription) }
                try? results.joined(separator:"\n").write(to:URL(fileURLWithPath:CommandLine.arguments[1]).appendingPathComponent("automation-results.txt"),atomically:true,encoding:.utf8)
                tools.stop(); NSApp.terminate(nil)
            }
        }
        app.run()
    }
}
