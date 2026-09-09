"""Developer regression checks; Python is not required by the shipped app."""
import json
import pathlib
import subprocess
import sys
import tempfile
import time

helper = str(pathlib.Path(sys.argv[1]).resolve())
with tempfile.TemporaryDirectory(prefix="lantern-command-tests-", dir="work") as directory:
    root = pathlib.Path(directory).resolve()
    (root / ".env").write_text("PRIVATE_TEST_CANARY")
    (root / ".git").mkdir()

    def run(command):
        result = subprocess.run([helper], input=json.dumps({"root": str(root), "command": command}), text=True, capture_output=True, timeout=35)
        return json.loads(result.stdout)

    checks = [
        ("normal output", "printf 'works'", lambda r: r["exit_code"] == 0 and r["output"] == "works"),
        ("credential denial", "cat .env", lambda r: r["exit_code"] != 0 and "PRIVATE_TEST_CANARY" not in r["output"]),
        ("network denial", "/usr/bin/curl --max-time 2 http://127.0.0.1:11435/api/version", lambda r: r["exit_code"] != 0),
        ("git write denial", "touch .git/forbidden", lambda r: r["exit_code"] != 0),
        ("output limit", "yes test", lambda r: "64 KB output limit" in r["output"] and len(r["output"]) < 65000),
        ("timeout", "sleep 35", lambda r: "30-second time limit" in r["output"]),
    ]
    for label, command, check in checks:
        assert check(run(command)), label
        print("PASS:", label, flush=True)
    process = subprocess.Popen([helper], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
    process.stdin.write(json.dumps({"root": str(root), "command": "sleep 2; touch should-not-exist"}))
    process.stdin.close()
    time.sleep(0.3)
    process.terminate()
    process.wait(timeout=5)
    time.sleep(2)
    assert not (root / "should-not-exist").exists()
    print("PASS: cancellation kills descendants")
