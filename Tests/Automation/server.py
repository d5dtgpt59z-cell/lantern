from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
import time
class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/redirect':
            self.send_response(302); self.send_header('Location','/text'); self.end_headers(); return
        if self.path == '/slow': time.sleep(5)
        body = b'Internet fixture' if self.path == '/text' else b'''<!doctype html><html><head><title>Lantern tool test</title></head><body style="font:24px system-ui;padding:64px;background:#141619;color:#eee"><h1>Lantern browser test</h1><label>Message <input aria-label="Message"></label><button onclick="document.querySelector('p').textContent='Clicked '+document.querySelector('input').value">Apply</button><p>Ready</p></body></html>'''
        self.send_response(200); self.send_header('Content-Type','text/html; charset=utf-8'); self.send_header('Content-Length',str(len(body))); self.end_headers()
        try: self.wfile.write(body)
        except BrokenPipeError: pass
    def log_message(self,*args): pass
ThreadingHTTPServer(('127.0.0.1',18765),Handler).serve_forever()
