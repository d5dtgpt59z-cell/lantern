#!/usr/bin/python3
"""Trusted command supervisor. Only the child receives model-generated code."""
import json, os, selectors, signal, subprocess, sys, tempfile, time

def main():
    payload = json.load(sys.stdin)
    root = os.path.realpath(payload['root'])
    command = payload['command']
    if not os.path.isfile('/usr/bin/sandbox-exec'):
        raise RuntimeError('macOS command sandbox is unavailable. No command was run.')
    with tempfile.TemporaryDirectory(prefix='lantern-command-') as temp:
        # JSON string escaping is also valid for these SBPL string literals.
        quote = json.dumps
        profile = '\n'.join([
            '(version 1)', '(deny default)',
            '(allow process-exec process-fork)'
            , '(allow process-info* (target self))',
            '(allow signal (target self))',
            '(allow sysctl-read)',
            '(allow file-ioctl (literal "/dev/dtracehelper"))',
            '(allow file-read-metadata)',
            '(allow file-read* (literal "/"))',
            '(allow file-read* (subpath "/private/preboot") (subpath "/dev") (subpath "/System") (subpath "/usr") (subpath "/bin") (subpath "/sbin") (subpath "/Library/Developer") (subpath "/Applications/Xcode.app") (subpath "/opt/homebrew"))',
            '(allow file-read* file-write* (literal "/dev/null") (literal "/dev/zero") (literal "/dev/dtracehelper"))',
            '(allow file-read* (literal "/dev/urandom") (literal "/dev/random") (literal "/private/etc/localtime"))',
            '(allow file-read* file-write* (subpath ' + quote(root) + ') (subpath ' + quote(os.path.realpath(temp)) + '))',
            '(deny file-read-data file-write* (regex #"(^|/)([.]env[^/]*|[.]ssh|[.]aws|[.]config|credentials|secrets[.]json)(/|$)") (regex #"[.](pem|key)$"))',
            '(deny file-write* (regex #"(^|/)[.]git(/|$)"))',
            '(deny network*)',
        ])
        env = {'PATH': '/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin', 'HOME': temp, 'TMPDIR': temp, 'LANG': 'en_US.UTF-8', 'GIT_CONFIG_NOSYSTEM': '1', 'GIT_CONFIG_GLOBAL': '/dev/null', 'GIT_TERMINAL_PROMPT': '0', 'PYTHONDONTWRITEBYTECODE': '1'}
        process = subprocess.Popen(['/usr/bin/sandbox-exec', '-p', profile, '/bin/sh', '-c', command], cwd=root, env=env, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, start_new_session=True)
        # Kill the entire command group if the supervising app cancels this helper.
        def stop(signum=None, frame=None):
            process.poll()  # Reap an exited sandbox process before signaling its group.
            try: os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError: pass
            if signum is not None: raise SystemExit(130)
        signal.signal(signal.SIGTERM, stop)
        signal.signal(signal.SIGINT, stop)
        selector = selectors.DefaultSelector(); selector.register(process.stdout, selectors.EVENT_READ)
        output = bytearray(); reason = ''; deadline = time.monotonic() + 30
        try:
            while selector.get_map():
                if time.monotonic() >= deadline: reason = '\n[Stopped: 30-second time limit]'; break
                for key, _ in selector.select(timeout=0.1):
                    data = os.read(key.fileobj.fileno(), 4096)
                    if not data: selector.unregister(key.fileobj); continue
                    output.extend(data)
                    if len(output) >= 64000: reason = '\n[Stopped: 64 KB output limit]'; break
                if reason: break
        finally:
            stop(); process.wait(); selector.close()
        print(json.dumps({'exit_code': process.returncode, 'output': output[:64000].decode('utf-8', errors='replace') + reason}))

if __name__ == '__main__':
    try: main()
    except Exception as exc:
        print(json.dumps({'error': str(exc)})); sys.exit(1)
