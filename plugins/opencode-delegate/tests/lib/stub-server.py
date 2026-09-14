#!/usr/bin/env python3
"""Minimal stand-in for `opencode serve`, for the oc-task test suite.

Answers the two endpoints oc-task uses and records what it was sent:
  GET  /global/health  -> 200 {}
  POST /session        -> 200 {"id": "ses_stub..."} (or the status in
                          OC_STUB_SESSION_STATUS, to exercise failed dispatch)

The decoded `directory` query parameter of every POST /session is appended to
$OC_STUB_STATE/session-directory, one per line. A repo path containing a space
only survives that round trip if the client percent-encoded it.
"""
import json
import os
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlparse, parse_qs

STATE = os.environ.get("OC_STUB_STATE", ".")
SESSION_STATUS = int(os.environ.get("OC_STUB_SESSION_STATUS", "200"))


def record(name, value):
    with open(os.path.join(STATE, name), "a") as fh:
        fh.write(value + "\n")


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass  # keep the serve log to the one "listening on" line oc-task greps

    def _send(self, status, payload):
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if urlparse(self.path).path == "/global/health":
            self._send(200, {})
        else:
            self._send(404, {})

    def do_POST(self):
        parsed = urlparse(self.path)
        if parsed.path != "/session":
            self._send(404, {})
            return
        length = int(self.headers.get("Content-Length") or 0)
        if length:
            self.rfile.read(length)
        directory = parse_qs(parsed.query).get("directory", [""])[0]
        record("session-directory", directory)
        if SESSION_STATUS != 200:
            self._send(SESSION_STATUS, {"error": "stub refused"})
            return
        self._send(200, {"id": "ses_stub0000000000000000"})


def main():
    port = int(sys.argv[1])
    server = HTTPServer(("127.0.0.1", port), Handler)
    print("listening on http://127.0.0.1:%d" % port, flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
