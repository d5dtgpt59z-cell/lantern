"""Exercise image-process ownership without a GPU, image engine, or model files."""

import contextlib
import json
import os
import pathlib
import signal
import subprocess
import sys
import tempfile
import time


helper = str(pathlib.Path(sys.argv[1]).resolve())

FIXTURE = r'''
import json, os, pathlib, signal, subprocess, sys, time

mode, path = sys.argv[1], pathlib.Path(sys.argv[2])
if mode == "ignore":
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
record = {"pid": os.getpid(), "pgid": os.getpgrp(), "args": sys.argv[3:], "marker": os.environ.get("PAIGE_IMAGE_TEST_MARKER")}
if mode in ("descendant", "descendant-exit"):
    child_path = path.with_suffix(".child.json")
    child = subprocess.Popen([sys.executable, __file__, "ignore", str(child_path)], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    limit = time.monotonic() + 5
    while not child_path.exists():
        if time.monotonic() >= limit:
            raise RuntimeError("Child fixture did not start")
        time.sleep(0.02)
    record["child"] = json.loads(child_path.read_text())
temporary = path.with_suffix(".tmp")
temporary.write_text(json.dumps(record))
temporary.replace(path)
if mode == "record":
    sys.exit(37)
if mode == "descendant-exit":
    sys.exit(19)
if mode == "signal-exit":
    os.kill(os.getpid(), signal.SIGKILL)
while True:
    time.sleep(0.05)
'''


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False


def wait_for(predicate, message, timeout=5):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(0.025)
    require(predicate(), message)


def stop_owned_process(process):
    if process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=3)


with tempfile.TemporaryDirectory(prefix="paige-image-supervisor-tests-", dir="work") as directory:
    root = pathlib.Path(directory).resolve()
    fixture = root / "fixture.py"
    fixture.write_text(FIXTURE)
    sequence = 0

    @contextlib.contextmanager
    def owned_render(mode, arguments=()):
        """Every parent, supervisor, renderer, and group belongs to this test."""
        global sequence
        sequence += 1
        state_path = root / (str(sequence) + ".json")
        parent = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(60)"], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        environment = os.environ.copy()
        environment["PAIGE_IMAGE_TEST_MARKER"] = "local-supervision-fixture"
        process = subprocess.Popen([helper, sys.executable, str(parent.pid), str(fixture), mode, str(state_path), *arguments], stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=environment)
        state = None
        try:
            wait_for(state_path.exists, "renderer fixture did not start")
            state = json.loads(state_path.read_text())
            require(state["pgid"] == state["pid"], "renderer must lead its own process group")
            if "child" in state:
                require(state["child"]["pgid"] == state["pgid"], "descendant fixture must share renderer group")
            yield parent, process, state
        finally:
            stop_owned_process(process)
            # Failure cleanup is limited to the process group created for this fixture.
            if state is not None:
                try:
                    os.killpg(state["pgid"], signal.SIGKILL)
                except ProcessLookupError:
                    pass
            stop_owned_process(parent)
            process.stdout.close()
            process.stderr.close()

    def normal_exit():
        arguments = ["--prompt", "a prompt with spaces", "literal $() `quoted`\nsecond line", "", "雪", "--negative", "-p"]
        with owned_render("record", arguments) as (_, process, state):
            require(process.wait(timeout=5) == 37, "renderer exit code was not propagated")
            require(state["args"] == arguments, "renderer arguments were altered")
            require(state["marker"] == "local-supervision-fixture", "renderer environment was not inherited")
            wait_for(lambda: not alive(state["pid"]), "successful renderer was not reaped")

    def signal_exit():
        with owned_render("signal-exit") as (_, process, state):
            require(process.wait(timeout=5) == 128 + signal.SIGKILL, "renderer signal exit was not propagated")
            wait_for(lambda: not alive(state["pid"]), "signalled renderer was not reaped")

    def terminate_renderer():
        with owned_render("sleep") as (_, process, state):
            process.terminate()
            require(process.wait(timeout=5) == 128 + signal.SIGTERM, "supervisor SIGTERM exit code changed")
            wait_for(lambda: not alive(state["pid"]), "SIGTERM left renderer alive or unreaped")

    def parent_death():
        with owned_render("sleep") as (parent, process, state):
            stop_owned_process(parent)
            require(process.wait(timeout=5) == 128 + signal.SIGTERM, "parent death did not stop supervisor")
            wait_for(lambda: not alive(state["pid"]), "parent death left renderer alive or unreaped")

    def ignoring_renderer():
        with owned_render("ignore") as (_, process, state):
            started = time.monotonic()
            process.terminate()
            require(process.wait(timeout=5) == 128 + signal.SIGTERM, "SIGTERM-ignoring renderer did not stop")
            require(time.monotonic() - started < 4, "SIGKILL fallback exceeded its expected bound")
            wait_for(lambda: not alive(state["pid"]), "SIGKILL fallback did not reap renderer")

    def ignoring_descendant():
        with owned_render("descendant") as (_, process, state):
            process.terminate()
            require(process.wait(timeout=5) == 128 + signal.SIGTERM, "renderer group did not stop")
            wait_for(lambda: not alive(state["pid"]), "renderer leader was not reaped")
            wait_for(lambda: not alive(state["child"]["pid"]), "SIGTERM-ignoring renderer descendant survived", timeout=3)

    def finished_renderer_descendant():
        with owned_render("descendant-exit") as (_, process, state):
            require(process.wait(timeout=5) == 19, "completed renderer exit status changed")
            wait_for(lambda: not alive(state["pid"]), "completed renderer was not reaped")
            wait_for(lambda: not alive(state["child"]["pid"]), "completed renderer left a running descendant", timeout=3)

    def missing_binary():
        process = subprocess.run([helper, str(root / "missing-renderer"), str(os.getpid())], capture_output=True, text=True, timeout=5)
        require(process.returncode == 1, "missing renderer must fail")
        require("Could not start" in process.stderr, "missing renderer must report a useful error")

    failures = []
    checks = [
        ("exit code, exact arguments, environment, and successful reaping", normal_exit),
        ("renderer signal exit propagation", signal_exit),
        ("SIGTERM terminates and reaps renderer", terminate_renderer),
        ("parent death terminates and reaps renderer", parent_death),
        ("SIGKILL fallback terminates and reaps SIGTERM-ignoring renderer", ignoring_renderer),
        ("cancellation kills SIGTERM-ignoring descendants", ignoring_descendant),
        ("completed renderer leaves no running descendants", finished_renderer_descendant),
        ("missing renderer reports startup failure", missing_binary),
    ]
    for label, check in checks:
        try:
            check()
            print("PASS:", label, flush=True)
        except Exception as error:
            failures.append(label)
            print("FAIL:", label + ":", error, flush=True)
    if failures:
        raise SystemExit(str(len(failures)) + " image-supervisor checks failed")
    print("PASS: all image-supervisor fixtures stopped; no model loaded", flush=True)
