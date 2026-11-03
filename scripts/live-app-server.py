#!/usr/bin/env python3
"""
xChat Live App Server & API Proxy
Serves the local android/app/src/main/assets/index.html file dynamically on GET /
and reverse-proxies all /api/* requests to the local Rust xChat node.
"""
import http.server
import os
import sys
import urllib.request
import urllib.error

FRONTEND_PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 4000
BACKEND_PORT = int(sys.argv[2]) if len(sys.argv) > 2 else 4001
HTML_PATH = sys.argv[3] if len(sys.argv) > 3 else "android/app/src/main/assets/index.html"

if not os.path.isabs(HTML_PATH):
    HTML_PATH = os.path.abspath(HTML_PATH)

class LiveAppHandler(http.server.BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        # Quiet log
        pass

    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        self.send_header('Content-Length', '0')
        self.end_headers()

    def do_GET(self):
        if self.path == '/' or not self.path.startswith('/api'):
            try:
                with open(HTML_PATH, 'rb') as f:
                    content = f.read()
                self.send_response(200)
                self.send_header('Content-Type', 'text/html; charset=utf-8')
                self.send_header('Access-Control-Allow-Origin', '*')
                self.send_header('Cache-Control', 'no-cache, no-store, must-revalidate')
                self.send_header('Content-Length', str(len(content)))
                self.end_headers()
                self.wfile.write(content)
            except Exception as e:
                self.send_response(500)
                self.send_header('Content-Type', 'text/plain')
                self.end_headers()
                self.wfile.write(f"Error loading {HTML_PATH}: {e}".encode())
        else:
            # Proxy /api GET request to backend
            target_url = f"http://127.0.0.1:{BACKEND_PORT}{self.path}"
            req = urllib.request.Request(target_url)
            try:
                with urllib.request.urlopen(req, timeout=10) as resp:
                    data = resp.read()
                    self.send_response(resp.status)
                    self.send_header('Access-Control-Allow-Origin', '*')
                    for k, v in resp.headers.items():
                        if k.lower() not in ['transfer-encoding', 'content-length', 'access-control-allow-origin']:
                            self.send_header(k, v)
                    self.send_header('Content-Length', str(len(data)))
                    self.end_headers()
                    self.wfile.write(data)
            except urllib.error.HTTPError as he:
                data = he.read()
                self.send_response(he.code)
                self.send_header('Access-Control-Allow-Origin', '*')
                self.send_header('Content-Length', str(len(data)))
                self.end_headers()
                self.wfile.write(data)
            except Exception as err:
                self.send_response(502)
                self.send_header('Content-Type', 'application/json')
                self.send_header('Access-Control-Allow-Origin', '*')
                err_msg = f'{{"error": "Backend offline", "detail": "{err}"}}'.encode()
                self.send_header('Content-Length', str(len(err_msg)))
                self.end_headers()
                self.wfile.write(err_msg)

    def do_POST(self):
        content_len = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_len) if content_len > 0 else None
        target_url = f"http://127.0.0.1:{BACKEND_PORT}{self.path}"
        req = urllib.request.Request(target_url, data=body, method='POST')
        req.add_header('Content-Type', self.headers.get('Content-Type', 'application/json'))
        try:
            with urllib.request.urlopen(req, timeout=10) as resp:
                data = resp.read()
                self.send_response(resp.status)
                self.send_header('Access-Control-Allow-Origin', '*')
                for k, v in resp.headers.items():
                    if k.lower() not in ['transfer-encoding', 'content-length', 'access-control-allow-origin']:
                        self.send_header(k, v)
                self.send_header('Content-Length', str(len(data)))
                self.end_headers()
                self.wfile.write(data)
        except urllib.error.HTTPError as he:
            data = he.read()
            self.send_response(he.code)
            self.send_header('Access-Control-Allow-Origin', '*')
            self.send_header('Content-Length', str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        except Exception as err:
            self.send_response(502)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Access-Control-Allow-Origin', '*')
            err_msg = f'{{"error": "Backend offline", "detail": "{err}"}}'.encode()
            self.send_header('Content-Length', str(len(err_msg)))
            self.end_headers()
            self.wfile.write(err_msg)

if __name__ == '__main__':
    server = http.server.ThreadingHTTPServer(('0.0.0.0', FRONTEND_PORT), LiveAppHandler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass

