import Foundation
@main struct ToolChecks {
    static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let tools = AgentTools(root: root)
        func blocked(_ label: String, _ work: () throws -> Void) throws {
            do { try work(); fatalError("FAILED: " + label) } catch { print("PASS: " + label) }
        }
        try blocked("parent traversal") { _ = try tools.resolve("../outside-canary.txt") }
        try blocked("absolute path") { _ = try tools.resolve("/etc/passwd") }
        try blocked("symlink escape") { _ = try tools.read("escape.txt") }
        try blocked("hidden credential") { _ = try tools.read(".env") }
        let target = root.appendingPathComponent("approval.txt")
        try "original".write(to: target, atomically: true, encoding: .utf8)
        let call = ToolCall(function: .init(name: "write_file", arguments: ["path": "approval.txt", "content": "approved replacement"]))
        do { _ = try await tools.perform(call); fatalError("unapproved write executed") } catch { print("PASS: unapproved write blocked") }
        let request = try tools.inspect(call)!
        try "user changed it".write(to: target, atomically: true, encoding: .utf8)
        do { _ = try await tools.perform(call, approval: request); fatalError("stale write executed") } catch { print("PASS: stale approval blocked") }
        let fresh = try tools.inspect(call)!
        _ = try await tools.perform(call, approval: fresh)
        let saved = try String(contentsOf: target, encoding: .utf8)
        assert(saved == "approved replacement")
        print("PASS: approved write")
        assert(!AgentTools.permittedRoot(FileManager.default.homeDirectoryForCurrentUser))
        assert(!AgentTools.permittedRoot(URL(fileURLWithPath: "/")))
        print("PASS: broad workspace denied")
    }
}
