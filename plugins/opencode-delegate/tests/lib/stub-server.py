#!/usr/bin/env python3
"""Minimal stand-in for `opencode serve`, for the oc-task test suite.

Answers the two endpoints oc-task uses and records what it was sent:
  GET  /global/health  -> 200 {}
  POST /session        -> 200 {"id": "ses_stub..."} (or the status in
                          OC_STUB_SESSION_STATUS, to exercise failed dispatch)

The decoded `directory` query parameter of every POST /session is appended to
$OC_STUB_STATE/session-directory, one per line, and the request body to
$OC_STUB_STATE/session-body. A repo path containing a space only survives
that round trip if the client percent-encoded it.

With OC_STUB_SERVE_ERROR set, the server logs that message to stderr in
opencode's own format (`level=ERROR ... error.error="..."`), the way a real
server reports a provider's refusal, OC_STUB_SERVE_ERROR_DELAY seconds
(default 1) after the session is created.
"""
import json
import os
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlparse, parse_qs

STATE = os.environ.get("OC_STUB_STATE", ".")
SESSION_STATUS = int(os.environ.get("OC_STUB_SESSION_STATUS", "200"))
SERVE_ERROR = os.environ.get("OC_STUB_SERVE_ERROR", "")
SERVE_ERROR_DELAY = float(os.environ.get("OC_STUB_SERVE_ERROR_DELAY", "1"))
# With OC_STUB_SERVE_ERROR_SMALL set, the error comes from the title agent.
SERVE_ERROR_SMALL = bool(os.environ.get("OC_STUB_SERVE_ERROR_SMALL"))
SESSION_ID = "ses_stub0000000000000000"


def record(name, value):
    with open(os.path.join(STATE, name), "a") as fh:
        fh.write(value + "\n")


def log_error_later():
    time.sleep(SERVE_ERROR_DELAY)
    stamp = time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime())
    sys.stderr.write(
        'timestamp=%s level=ERROR run=stub message="stream error" providerID=opencode '
        'modelID=stub session.id=%s small=%s agent=%s mode=primary error.error="%s"\n'
        % (stamp, SESSION_ID, "true" if SERVE_ERROR_SMALL else "false",
           "title" if SERVE_ERROR_SMALL else "build", SERVE_ERROR)
    )
    sys.stderr.flush()


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
        body = self.rfile.read(length).decode() if length else ""
        record("session-body", body)
        directory = parse_qs(parsed.query).get("directory", [""])[0]
        record("session-directory", directory)
        if SESSION_STATUS != 200:
            self._send(SESSION_STATUS, {"error": "stub refused"})
            return
        if SERVE_ERROR:
            threading.Thread(target=log_error_later, daemon=True).start()
        self._send(200, {"id": SESSION_ID})


def main():
    port = int(sys.argv[1])
    server = HTTPServer(("127.0.0.1", port), Handler)
    print("listening on http://127.0.0.1:%d" % port, flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
