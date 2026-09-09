import Foundation
import Darwin

// The helper owns a separate process group, so cancellation and timeout kill descendants.
var child: pid_t = 0
func terminate(_ value: Int32) { if child > 0 { kill(-child, SIGKILL) }; _exit(130) }
func output(_ object: [String: Any]) {
    if let data = try? JSONSerialization.data(withJSONObject: object) { FileHandle.standardOutput.write(data) }
}
func run() throws {
    let input = FileHandle.standardInput.readDataToEndOfFile()
    guard let payload = try JSONSerialization.jsonObject(with: input) as? [String: String], let path = payload["root"], let command = payload["command"] else { throw NSError(domain: "Invalid request", code: 1) }
    let root = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    let temp = FileManager.default.temporaryDirectory.appendingPathComponent("lantern-command-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temp) }
    func quote(_ s: String) -> String { String(data: try! JSONEncoder().encode(s), encoding: .utf8)! }
    let profile = """
    (version 1)
    (deny default)
    (allow process-exec process-fork)
    (allow process-info* (target self))
    (allow signal (target self))
    (allow sysctl-read)
    (allow file-ioctl (literal "/dev/dtracehelper"))
    (allow file-read-metadata)
    (allow file-read* (literal "/"))
    (allow file-read* (subpath "/private/preboot") (subpath "/dev") (subpath "/System") (subpath "/usr") (subpath "/bin") (subpath "/sbin") (subpath "/Library/Developer") (subpath "/Applications/Xcode.app") (subpath "/opt/homebrew"))
    (allow file-read* file-write* (literal "/dev/null") (literal "/dev/zero") (literal "/dev/dtracehelper"))
    (allow file-read* (literal "/dev/urandom") (literal "/dev/random") (literal "/private/etc/localtime"))
    (allow file-read* file-write* (subpath \(quote(root))) (subpath \(quote(temp.resolvingSymlinksInPath().path))))
    (deny file-read-data file-write* (regex #"(^|/)([.]env[^/]*|[.]ssh|[.]aws|[.]config|credentials|secrets[.]json)(/|$)") (regex #"[.](pem|key)$"))
    (deny file-write* (regex #"(^|/)[.]git(/|$)"))
    (deny network*)
    """
    guard chdir(root) == 0 else { throw NSError(domain: "Project folder unavailable", code: 1) }
    var fds: [Int32] = [0, 0]
    guard pipe(&fds) == 0 else { throw NSError(domain: "Pipe failed", code: 1) }
    defer { close(fds[0]) }
    var actions: posix_spawn_file_actions_t?
    posix_spawn_file_actions_init(&actions)
    defer { posix_spawn_file_actions_destroy(&actions) }
    posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
    posix_spawn_file_actions_adddup2(&actions, fds[1], STDOUT_FILENO)
    posix_spawn_file_actions_adddup2(&actions, fds[1], STDERR_FILENO)
    posix_spawn_file_actions_addclose(&actions, fds[0])
    posix_spawn_file_actions_addclose(&actions, fds[1])
    var attr: posix_spawnattr_t?
    posix_spawnattr_init(&attr)
    defer { posix_spawnattr_destroy(&attr) }
    posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETPGROUP))
    posix_spawnattr_setpgroup(&attr, 0)
    let args = ["/usr/bin/sandbox-exec", "-p", profile, "/bin/sh", "-c", command]
    let env = ["PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin", "HOME=\(temp.path)", "TMPDIR=\(temp.path)", "LANG=en_US.UTF-8", "GIT_CONFIG_NOSYSTEM=1", "GIT_CONFIG_GLOBAL=/dev/null", "GIT_TERMINAL_PROMPT=0"]
    var argv = args.map { strdup($0) } + [nil]
    var envp = env.map { strdup($0) } + [nil]
    defer { argv.forEach { free($0) }; envp.forEach { free($0) } }
    signal(SIGTERM, terminate); signal(SIGINT, terminate)
    let result = posix_spawn(&child, args[0], &actions, &attr, &argv, &envp)
    close(fds[1])
    guard result == 0 else { child = 0; throw NSError(domain: "Command sandbox could not start", code: Int(result)) }
    _ = fcntl(fds[0], F_SETFL, O_NONBLOCK)
    var bytes = Data(); var reason = ""; var status: Int32 = 0
    let deadline = ProcessInfo.processInfo.systemUptime + 30
    var buffer = [UInt8](repeating: 0, count: 4096)
    while true {
        if ProcessInfo.processInfo.systemUptime >= deadline { reason = "\n[Stopped: 30-second time limit]"; break }
        let count = read(fds[0], &buffer, buffer.count)
        if count > 0 { bytes.append(contentsOf: buffer.prefix(count)); if bytes.count >= 64000 { reason = "\n[Stopped: 64 KB output limit]"; break } }
        else if count == 0 { break }
        else if errno != EAGAIN && errno != EINTR { break }
        else { usleep(10_000) }
    }
    kill(-child, SIGKILL)
    waitpid(child, &status, 0); child = 0
    let code = (status & 0x7f) == 0 ? (status >> 8) & 0xff : -(status & 0x7f)
    output(["exit_code": code, "output": String(decoding: bytes.prefix(64000), as: UTF8.self) + reason])
}
do { try run() } catch { output(["error": error.localizedDescription]); exit(1) }
