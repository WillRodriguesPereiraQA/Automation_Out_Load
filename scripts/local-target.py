#!/usr/bin/env python3
"""Alvo HTTP local da carga completa. Escuta somente em 127.0.0.1.

Cada maquina que clona o repositorio sobe este processo na propria interface
de loopback. GET / e POST /reserve.php respondem 200.
"""
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HOST = "127.0.0.1"
BODY = b"<html><body><p>Local target</p></body></html>"


class LocalHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _reply(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(BODY)))
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(BODY)

    def _discard_body(self):
        length = int(self.headers.get("Content-Length", "0") or "0")
        if length > 0:
            remaining = length
            while remaining:
                chunk = self.rfile.read(min(remaining, 65536))
                if not chunk:
                    break
                remaining -= len(chunk)

    def do_GET(self):
        self._reply()

    def do_POST(self):
        self._discard_body()
        self._reply()

    def log_message(self, fmt, *args):
        return


class LocalServer(ThreadingHTTPServer):
    allow_reuse_address = True
    daemon_threads = True


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
    if port < 1 or port > 65535:
        print("porta invalida", file=sys.stderr)
        return 2
    server = LocalServer((HOST, port), LocalHandler)
    print(f"listening http://{HOST}:{port}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
