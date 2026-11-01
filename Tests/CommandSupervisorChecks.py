"""Developer regression checks; Python is not required by the shipped app."""
import json
import pathlib
import subprocess
import sys
import tempfile
import time
import socket

helper = str(pathlib.Path(sys.argv[1]).resolve())
with tempfile.TemporaryDirectory(prefix="lantern-command-tests-", dir="work") as directory:
    root = pathlib.Path(directory).resolve()
    (root / ".env").write_text("PRIVATE_TEST_CANARY")
    (root / ".npmrc").write_text("NPM_PRIVATE_CANARY")
    (root / ".git").mkdir()

    def run(command, timeout=5, network=False):
        payload = {"root": str(root), "command": command, "timeout": str(timeout), "network": "true" if network else "false"}
        result = subprocess.run([helper], input=json.dumps(payload), text=True, capture_output=True, timeout=timeout + 5)
        return json.loads(result.stdout)

    checks = [
        ("normal output", "printf 'works'", lambda r: r["exit_code"] == 0 and r["output"] == "works"),
        ("isolated temporary directory", 'printf cache-ok > "$TMPDIR/check"; cat "$TMPDIR/check"', lambda r: r["exit_code"] == 0 and r["output"] == "cache-ok"),
        ("credential denial", "cat .env", lambda r: r["exit_code"] != 0 and "PRIVATE_TEST_CANARY" not in r["output"]),
        ("package credential denial", "cat .npmrc", lambda r: r["exit_code"] != 0 and "NPM_PRIVATE_CANARY" not in r["output"]),
        ("network denial", "/usr/bin/curl --max-time 2 http://127.0.0.1:11435/api/version", lambda r: r["exit_code"] != 0),
        ("git write denial", "touch .git/forbidden", lambda r: r["exit_code"] != 0),
        ("output limit", "yes test", lambda r: "256 KB output limit" in r["output"] and len(r["output"]) < 257000),
        ("timeout", "sleep 3", lambda r: "1-second time limit" in r["output"]),
    ]
    for label, command, check in checks:
        assert check(run(command, timeout=1 if label == "timeout" else 5)), label
        print("PASS:", label, flush=True)
    (root / "network-check.txt").write_text("network-ok")
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        port = probe.getsockname()[1]
    server = subprocess.Popen([sys.executable, "-m", "http.server", str(port), "--bind", "127.0.0.1"], cwd=root, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        time.sleep(0.2)
        result = run(f"/usr/bin/curl --silent --show-error --fail --max-time 2 http://127.0.0.1:{port}/network-check.txt", network=True)
        assert result["exit_code"] == 0 and result["output"] == "network-ok"
        print("PASS: approved network mode permits outbound access", flush=True)
    finally:
        server.terminate()
        server.wait(timeout=5)
    process = subprocess.Popen([helper], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
    process.stdin.write(json.dumps({"root": str(root), "command": "sleep 2; touch should-not-exist"}))
    process.stdin.close()
    time.sleep(0.3)
    process.terminate()
    process.wait(timeout=5)
    time.sleep(2)
    assert not (root / "should-not-exist").exists()
    print("PASS: cancellation kills descendants")
