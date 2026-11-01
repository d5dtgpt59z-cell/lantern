import Foundation
import Darwin

var enginePID: pid_t = 0
func stopEngine(_ signalNumber: Int32) {
    if enginePID > 0 { kill(-enginePID, SIGTERM); usleep(200_000); kill(-enginePID, SIGKILL) }
    _exit(0)
}
guard CommandLine.arguments.count == 3, let parent = Int32(CommandLine.arguments[2]) else { exit(1) }
let binary = CommandLine.arguments[1]
var attributes: posix_spawnattr_t?
posix_spawnattr_init(&attributes)
posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP))
posix_spawnattr_setpgroup(&attributes, 0)
var arguments = [strdup(binary), strdup("serve"), nil]
var environment = ProcessInfo.processInfo.environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
signal(SIGTERM, stopEngine); signal(SIGINT, stopEngine)
let result = posix_spawn(&enginePID, binary, nil, &attributes, &arguments, &environment)
arguments.forEach { free($0) }; environment.forEach { free($0) }; posix_spawnattr_destroy(&attributes)
guard result == 0 else { exit(1) }
while kill(parent, 0) == 0 {
    var status: Int32 = 0
    if waitpid(enginePID, &status, WNOHANG) == enginePID { kill(-enginePID, SIGKILL); enginePID = 0; exit(1) }
    usleep(200_000)
}
stopEngine(0)
