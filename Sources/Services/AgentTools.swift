import Foundation
struct AgentTools {
    let root: URL
    static var schemas: [[String: Any]] {
        [schema("list_files", "List files in a relative folder. Hidden files are excluded.", ["path": "Relative directory, use . for root"]),
         schema("read_file", "Read a UTF-8 text file, up to 80 KB.", ["path": "Relative file path"]),
         schema("search_files", "Search text in project files, up to 50 matches.", ["query": "Literal text to find"]),
         schema("write_file", "Propose creating or replacing a text file. The user must approve the full before/after preview. Read an existing file first.", ["path": "Relative file path", "content": "Complete new file contents"]),
         schema("run_command", "Request approval for a shell command in the workspace. No network or private home-file access; 30 second limit. Package downloads, system changes and background services are unavailable.", ["command": "Exact shell command to review"])]
    }
    static func schema(_ name: String, _ desc: String, _ params: [String: String]) -> [String: Any] {
        ["type": "function", "function": ["name": name, "description": desc, "parameters": ["type": "object", "properties": params.mapValues { ["type": "string", "description": $0] }, "required": Array(params.keys), "additionalProperties": false]]]
    }
    static func fail(_ message: String) -> NSError { NSError(domain: "Lantern tools", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    static func permittedRoot(_ url: URL) -> Bool {
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let blocked = ["/", "/Users", home, home + "/Documents", home + "/Desktop", home + "/Downloads", home + "/Library"]
        return path.hasPrefix(home + "/") && !blocked.contains(path) && !path.hasPrefix(home + "/Library/") && !path.split(separator: "/").contains(where: { $0.hasPrefix(".") })
    }
    func resolve(_ path: String) throws -> URL {
        guard !path.hasPrefix("/"), !path.contains("\0"), !path.split(separator: "/").contains("..") else { throw Self.fail("Use a relative path inside the selected folder.") }
        let parts = path.split(separator: "/")
        guard !parts.contains(where: { $0 != "." && ($0.hasPrefix(".") || $0.hasSuffix(".pem") || $0.hasSuffix(".key") || $0 == "credentials" || $0 == "secrets.json") }) else { throw Self.fail("Hidden files and credential files are blocked.") }
        let base = root.resolvingSymlinksInPath().standardizedFileURL
        let url = base.appendingPathComponent(path).standardizedFileURL.resolvingSymlinksInPath()
        guard url.path == base.path || url.path.hasPrefix(base.path + "/") else { throw Self.fail("Path escapes the selected folder, possibly through a symbolic link.") }
        return url
    }
    func read(_ path: String) throws -> String {
        let url = try resolve(path)
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attrs[.type] as? FileAttributeType == .typeRegular, (attrs[.size] as? NSNumber)?.intValue ?? Int.max <= 80_000 else { throw Self.fail("Only regular text files up to 80 KB can be read.") }
        return try String(contentsOf: url, encoding: .utf8)
    }
    func inspect(_ call: ToolCall) throws -> ApprovalRequest? {
        let args = call.function.arguments
        switch call.function.name {
        case "write_file":
            let path = args["path"] ?? ""; let url = try resolve(path)
            guard url.path != root.resolvingSymlinksInPath().path, let content = args["content"], content.utf8.count <= 80_000 else { throw Self.fail("A file path and content under 80 KB are required.") }
            let before = FileManager.default.fileExists(atPath: url.path) ? try read(path) : nil
            return ApprovalRequest(call: call, title: before == nil ? "Create a file?" : "Change this file?", detail: path, before: before, after: content)
        case "run_command":
            guard let command = args["command"], !command.isEmpty, command.utf8.count < 8000 else { throw Self.fail("Command is missing or too long.") }
            return ApprovalRequest(call: call, title: "Run this command?", detail: command, before: nil, after: nil)
        case "list_files", "read_file", "search_files": return nil
        default: throw Self.fail("Unknown tool. No action taken.")
        }
    }
    func perform(_ call: ToolCall, approval: ApprovalRequest? = nil) async throws -> String {
        try Task.checkCancellation()
        let args = call.function.arguments
        switch call.function.name {
        case "list_files":
            let url = try resolve(args["path"] ?? ".")
            return try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]).prefix(150).map { entry in
                let relative = String(entry.path.dropFirst(root.path.count + 1))
                _ = try resolve(relative)
                return entry.lastPathComponent + ((try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true ? "/" : "")
            }.sorted().joined(separator: "\n")
        case "read_file": return try read(args["path"] ?? "")
        case "search_files":
            guard let query = args["query"], !query.isEmpty else { throw Self.fail("Search text is required.") }
            let result = await Task.detached { () -> String in
                guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return "No files." }
                var hits: [String] = []; var visited = 0
                while let file = files.nextObject() as? URL {
                    visited += 1; if visited > 2000 || Task.isCancelled { break }
                    if ["node_modules", "build", "dist", "vendor"].contains(file.lastPathComponent) { files.skipDescendants(); continue }
                    let path = String(file.path.dropFirst(root.path.count + 1))
                    guard let text = try? read(path) else { continue }
                    for (line, content) in text.components(separatedBy: "\n").enumerated() where content.localizedCaseInsensitiveContains(query) {
                        hits.append("\(path):\(line + 1): \(content.prefix(250))")
                        if hits.count >= 50 { return hits.joined(separator: "\n") + "\n[50-match limit]" }
                    }
                }
                return hits.isEmpty ? "No matches within the 2,000-entry search limit." : hits.joined(separator: "\n")
            }.value
            return result
        case "write_file":
            guard let approval, approval.call.function.name == call.function.name, approval.call.function.arguments == args else { throw Self.fail("Write was not approved.") }
            let path = args["path"] ?? ""; let url = try resolve(path)
            let current = FileManager.default.fileExists(atPath: url.path) ? try read(path) : nil
            guard current == approval.before else { throw Self.fail("The file changed after the preview. Request a new approval.") }
            guard let content = approval.after else { throw Self.fail("No approved content.") }
            if let current {
                let backup = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Lantern/Backups")
                try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
                try current.write(to: backup.appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent), atomically: true, encoding: .utf8)
            }
            try content.write(to: url, atomically: true, encoding: .utf8)
            return "Saved \(path)." + (current != nil ? " A backup of the old file was saved in Lantern's Backups folder." : "")
        case "run_command":
            guard let approval, approval.call.function.name == call.function.name, approval.call.function.arguments == args else { throw Self.fail("Command was not approved.") }
            return try await CommandRunner.run(command: args["command"] ?? "", root: root)
        default: throw Self.fail("Tool is unavailable.")
        }
    }
}
