import Foundation
import Darwin

// A separate process owns the renderer group, so Stop and app exit also free GPU memory.
var rendererPID: pid_t = 0
func stopRenderer(_ signalNumber: Int32) {
    if rendererPID > 0 {
        kill(-rendererPID, SIGTERM)
        for _ in 0..<20 {
            var status: Int32 = 0
            if waitpid(rendererPID, &status, WNOHANG) == rendererPID { kill(-rendererPID, SIGKILL); _exit(128 + signalNumber) }
            usleep(50_000)
        }
        kill(-rendererPID, SIGKILL)
        var status: Int32 = 0
        _ = waitpid(rendererPID, &status, 0)
    }
    _exit(128 + signalNumber)
}
guard CommandLine.arguments.count >= 3, let parent = Int32(CommandLine.arguments[2]) else { exit(1) }
let binary = CommandLine.arguments[1]
var attributes: posix_spawnattr_t?
posix_spawnattr_init(&attributes)
posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP))
posix_spawnattr_setpgroup(&attributes, 0)
var arguments = ([binary] + Array(CommandLine.arguments.dropFirst(3))).map { strdup($0) } + [nil]
var environment = ProcessInfo.processInfo.environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
signal(SIGTERM, stopRenderer); signal(SIGINT, stopRenderer)
let result = posix_spawn(&rendererPID, binary, nil, &attributes, &arguments, &environment)
arguments.forEach { free($0) }; environment.forEach { free($0) }; posix_spawnattr_destroy(&attributes)
guard result == 0 else { fputs("Could not start PAIGE's image renderer.\n", stderr); exit(1) }
let deadline = Date().addingTimeInterval(1800)
while kill(parent, 0) == 0 {
    var status: Int32 = 0
    if waitpid(rendererPID, &status, WNOHANG) == rendererPID {
        kill(-rendererPID, SIGKILL)
        rendererPID = 0
        exit((status & 0x7f) == 0 ? (status >> 8) & 0xff : 128 + (status & 0x7f))
    }
    if Date() >= deadline { stopRenderer(SIGTERM) }
    usleep(100_000)
}
stopRenderer(SIGTERM)

