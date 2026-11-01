import Foundation
import AppKit

let fm = FileManager.default
let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("LanternSandboxProbe")
try fm.createDirectory(at: support, withIntermediateDirectories: true)
let report = support.appendingPathComponent("results.txt")
fm.createFile(atPath: report.path, contents: Data())
let log = try FileHandle(forWritingTo: report)
func record(_ s: String) { try? log.write(contentsOf: Data((s + "\n").utf8)); print(s); fflush(stdout) }
func run(_ executable: URL, _ args: [String], input: Data? = nil, env: [String:String]? = nil) -> String {
    let p = Process(); p.executableURL = executable; p.arguments = args; p.environment = env
    let out = Pipe(); p.standardOutput = out; p.standardError = out
    let pipe = Pipe(); p.standardInput = pipe
    do {
        try p.run(); if let input { try pipe.fileHandleForWriting.write(contentsOf: input) }; try pipe.fileHandleForWriting.close()
        let data = out.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        return "exit=\(p.terminationStatus) " + String(decoding: data, as: UTF8.self).prefix(3000)
    } catch { return "launch error: \(error)" }
}
record("Sandbox probe started. Container: \(support.path)")
let root = support.appendingPathComponent("Project")
try fm.createDirectory(at: root, withIntermediateDirectories: true)
try "project fixture\n".write(to: root.appendingPathComponent("sample.txt"), atomically: true, encoding: .utf8)
record("system shell: " + run(URL(fileURLWithPath: "/bin/sh"), ["-c", "printf shell-ok"]))
let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/LanternCommand")
let payload = try JSONSerialization.data(withJSONObject: ["root": root.path, "command": "cat sample.txt | /usr/bin/tr a-z A-Z"])
record("existing command supervisor: " + run(helper, [], input: payload))
let config = try! String(contentsOf: Bundle.main.url(forResource: "canary-path", withExtension: "txt")!, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
do { _ = try String(contentsOfFile: config, encoding: .utf8); record("FAIL: outside fixture readable") } catch { record("PASS: outside fixture denied") }
record("developer tool git: " + run(URL(fileURLWithPath: "/usr/bin/git"), ["--version"]))
record("developer tool swift: " + run(URL(fileURLWithPath: "/usr/bin/xcrun"), ["swift", "--version"]))
record("direct Xcode git: " + run(URL(fileURLWithPath: "/Applications/Xcode.app/Contents/Developer/usr/bin/git"), ["--version"]))
record("direct Xcode Swift: " + run(URL(fileURLWithPath: "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift"), ["--version"]))
record("Homebrew node: " + run(URL(fileURLWithPath: "/opt/homebrew/bin/node"), ["-e", "console.log('node-ok')"]))
if CommandLine.arguments.contains("--project") {
    let app = NSApplication.shared; app.setActivationPolicy(.regular); app.activate(ignoringOtherApps: true)
    let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
    panel.message = "Select the SandboxProject fixture to test project-folder access."
    panel.prompt = "Test project"
    panel.directoryURL = URL(fileURLWithPath: config).deletingLastPathComponent().appendingPathComponent("SandboxProject")
    let bookmarkFile = support.appendingPathComponent("project.bookmark")
    var selected: URL?
    if fm.fileExists(atPath: bookmarkFile.path) {
        var stale = false
        selected = try? URL(resolvingBookmarkData: Data(contentsOf: bookmarkFile), options: [.withSecurityScope], bookmarkDataIsStale: &stale)
        record("project bookmark restored; stale=\(stale)")
    } else if panel.runModal() == .OK, let url = panel.url {
        selected = url
        try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys:nil, relativeTo:nil).write(to:bookmarkFile)
        record("project bookmark saved")
    }
    if let selected {
        let scope = selected.startAccessingSecurityScopedResource(); defer { if scope { selected.stopAccessingSecurityScopedResource() } }
        do {
            let text = try String(contentsOf: selected.appendingPathComponent("sample.txt"), encoding:.utf8)
            record("selected project app read: " + text)
            try "sandbox write verified\n".write(to:selected.appendingPathComponent("probe-output.txt"),atomically:true,encoding:.utf8)
            record("selected project app write: PASS")
            record("selected project shell read: " + run(URL(fileURLWithPath:"/bin/cat"),[selected.appendingPathComponent("sample.txt").path]))
        } catch { record("project error: \(error)") }
    } else { record("project selection cancelled") }
    record("PROJECT DONE"); try? log.close(); exit(0)
}
let engine = Process()
engine.executableURL = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/LanternEngine")
engine.arguments = [Bundle.main.bundleURL.appendingPathComponent("Contents/Frameworks/Engine/ollama").path, String(ProcessInfo.processInfo.processIdentifier)]
let engineHome = support.appendingPathComponent("EngineHome")
try fm.createDirectory(at: engineHome, withIntermediateDirectories: true)
engine.environment = ["HOME":engineHome.path,"PATH":"/usr/bin:/bin","TMPDIR":NSTemporaryDirectory(),"OLLAMA_MODELS":support.appendingPathComponent("Models").path,"OLLAMA_HOST":"127.0.0.1:11439","OLLAMA_NO_CLOUD":"1","OLLAMA_NOPRUNE":"1","OLLAMA_MAX_LOADED_MODELS":"1","OLLAMA_NUM_PARALLEL":"1","OLLAMA_CONTEXT_LENGTH":"2048"]
let engineLog = support.appendingPathComponent("engine.log"); fm.createFile(atPath:engineLog.path,contents:Data())
let engineFile = try FileHandle(forWritingTo:engineLog); engine.standardOutput = engineFile; engine.standardError = engineFile
Task {
    do {
        try engine.run()
        defer { if engine.isRunning { engine.terminate(); engine.waitUntilExit() } }
        var ready = false
        let configuration = URLSessionConfiguration.ephemeral; configuration.timeoutIntervalForRequest = 3
        let session = URLSession(configuration: configuration)
        for _ in 0..<20 {
            if let (_,response) = try? await session.data(from: URL(string:"http://127.0.0.1:11439/api/version")!), (response as? HTTPURLResponse)?.statusCode == 200 { ready = true; break }
            try await Task.sleep(for:.milliseconds(500))
        }
        record("bundled engine startup: \(ready ? "PASS" : "FAIL")")
        if ready {
            let (tags,_) = try await session.data(from:URL(string:"http://127.0.0.1:11439/api/tags")!)
            record("models: " + String(decoding:tags,as:UTF8.self))
            if String(decoding:tags,as:UTF8.self).contains("qwen3.5:9b") {
                var request = URLRequest(url:URL(string:"http://127.0.0.1:11439/api/chat")!); request.httpMethod = "POST"; request.timeoutInterval = 180
                request.setValue("application/json",forHTTPHeaderField:"Content-Type")
                request.httpBody = try JSONSerialization.data(withJSONObject:["model":"qwen3.5:9b","stream":false,"think":false,"keep_alive":0,"messages":[["role":"user","content":"Reply with exactly: Sandbox inference works."]],"options":["num_ctx":2048,"num_predict":32]])
                let (answer,response) = try await session.data(for:request)
                record("inference HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0): " + String(decoding:answer,as:UTF8.self))
            }
        }
    } catch { record("engine error: \(error)") }
    record("DONE"); try? log.close(); exit(0)
}
dispatchMain()
