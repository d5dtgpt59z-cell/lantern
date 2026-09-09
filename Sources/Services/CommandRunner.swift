import Foundation
final class CommandJob: @unchecked Sendable {
    let process = Process()
    let lock = NSLock()
    var cancelled = false
    func cancel() { lock.lock(); cancelled = true; if process.isRunning { process.terminate() }; lock.unlock() }
    func start() throws {
        lock.lock(); defer { lock.unlock() }
        if cancelled { throw CancellationError() }
        try process.run()
    }
}
struct CommandRunner {
    static func run(command: String, root: URL) async throws -> String {
        guard let helper = Bundle.main.url(forResource: "run_command", withExtension: "py") else { throw AgentTools.fail("Command supervisor is missing. No command was run.") }
        let job = CommandJob()
        return try await withTaskCancellationHandler {
            try await Task.detached {
                let process = job.process
                process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
                process.arguments = [helper.path]
                let input = Pipe(); let output = Pipe()
                process.standardInput = input; process.standardOutput = output; process.standardError = output
                try job.start()
                let payload = try JSONSerialization.data(withJSONObject: ["root": root.path, "command": command])
                try input.fileHandleForWriting.write(contentsOf: payload); try input.fileHandleForWriting.close()
                let data = output.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
                if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let error = object["error"] as? String { throw AgentTools.fail(error) }
                    return "Exit status: \(object["exit_code"] ?? "unknown")\n" + (object["output"] as? String ?? "")
                }
                throw AgentTools.fail("Command supervisor failed: \(String(decoding: data.prefix(1000), as: UTF8.self))")
            }.value
        } onCancel: { job.cancel() }
    }
}
