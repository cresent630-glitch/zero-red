#!/usr/bin/env python3
"""Loopback fixtures for real URLSession downloads and simulator UI tests."""
import argparse
import io
import re
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from pathlib import Path
from functools import partial

ROOT = Path(__file__).resolve().parent.parent / "Fixtures"
class Handler(SimpleHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    def send_head(self):
        path = Path(self.translate_path(self.path))
        if path.suffix.lower() != ".mp4" or not path.is_file():
            return super().send_head()
        data = path.read_bytes()
        start, end = 0, len(data) - 1
        requested = self.headers.get("Range")
        if requested:
            match = re.fullmatch(r"bytes=(\d*)-(\d*)", requested)
            if not match or not any(match.groups()):
                self.send_error(416); return None
            left, right = match.groups()
            if left:
                start = int(left); end = min(int(right), end) if right else end
            else:
                start = max(0, len(data) - int(right))
            if start > end or start >= len(data):
                self.send_error(416); return None
        self.send_response(206 if requested else 200)
        self.send_header("Content-Type", "video/mp4")
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Content-Length", str(end - start + 1))
        if requested: self.send_header("Content-Range", f"bytes {start}-{end}/{len(data)}")
        self.end_headers()
        return io.BytesIO(data[start:end + 1])

    def do_POST(self):
        if self.path not in ["/test/offline-media/enable", "/test/offline-media/disable"]:
            self.send_error(404); return
        self.server.offline_media_enabled = self.path.endswith("/enable")
        self.send_response(200); self.send_header("Content-Length", "0"); self.end_headers()

    def do_GET(self):
        route = self.path.split("?")[0]
        if route == "/offline-sample.mp4":
            if not getattr(self.server, "offline_media_enabled", True):
                self.send_error(503, "Media source disabled for offline playback test"); return
            self.path = "/sample.mp4"
        if route == "/redirect":
            self.send_response(302); self.send_header("Location", "/sample.mp4"); self.send_header("Content-Length", "0"); self.end_headers(); return
        if route == "/redirect-other":
            self.send_response(302)
            self.send_header("Location", f"http://localhost:{self.server.server_port}/no-cookie.mp4")
            self.send_header("Content-Length", "0")
            self.end_headers(); return
        if route in ["/cookie.mp4", "/no-cookie.mp4", "/referer.mp4"]:
            ok = True
            if route == "/cookie.mp4": ok = self.headers.get("Cookie") == "session=secret"
            if route == "/no-cookie.mp4": ok = not self.headers.get("Cookie") and not self.headers.get("Referer")
            if route == "/referer.mp4": ok = self.headers.get("Referer") == "http://example.com/"
            if not ok:
                self.send_error(403); return
            self.path = "/sample.mp4"
        elif route in ["/empty.mp4", "/partial.mp4", "/error.mp4", "/fake.mp4"]:
            body = b"" if route == "/empty.mp4" else b"not a full video"
            self.send_response({"/partial.mp4":206,"/error.mp4":403}.get(route,200))
            self.send_header("Content-Type", "text/html" if route == "/fake.mp4" else "video/mp4")
            self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body); return
        super().do_GET()
    def log_message(self, format, *args): pass

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8765)
    args = parser.parse_args()
    server = ThreadingHTTPServer(("127.0.0.1", args.port), partial(Handler, directory=str(ROOT)))
    print(f"READY http://127.0.0.1:{server.server_port}", flush=True)
    server.serve_forever()
