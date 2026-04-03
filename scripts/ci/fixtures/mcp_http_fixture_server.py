#!/usr/bin/env python3

import argparse
import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def _json_bytes(obj: object) -> bytes:
    return json.dumps(obj, separators=(",", ":"), ensure_ascii=False).encode("utf-8")


def _sse_bytes(events: list[object]) -> bytes:
    chunks: list[bytes] = []
    for ev in events:
        chunks.append(b"event: message\n")
        chunks.append(b"data: ")
        chunks.append(_json_bytes(ev))
        chunks.append(b"\n\n")
    return b"".join(chunks)


def _host_allowed(host_header: str) -> bool:
    host = host_header.split(":", 1)[0].strip().lower()
    if host in ("127.0.0.1", "localhost", "::1", "[::1]"):
        return True
    return host.startswith("127.0.0.1")


def _origin_allowed(origin_header: str) -> bool:
    origin = origin_header.strip().lower()
    if origin == "":
        return True
    return origin.startswith("http://127.0.0.1") or origin.startswith("http://localhost") or origin.startswith(
        "https://127.0.0.1"
    ) or origin.startswith("https://localhost")


class _Handler(BaseHTTPRequestHandler):
    server: "_FixtureHttpServer"  # type: ignore[assignment]
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt: str, *args: object) -> None:  # noqa: D401
        return

    def do_GET(self) -> None:  # noqa: N802
        self._send_raw(200, b"", content_type="text/plain; charset=utf-8")

    def do_HEAD(self) -> None:  # noqa: N802
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", "0")
        self.end_headers()

    def do_POST(self) -> None:  # noqa: N802
        host = self.headers.get("Host", "")
        origin = self.headers.get("Origin", "")
        if host and not _host_allowed(host):
            self._send_json(403, {"error": "host_not_allowed"})
            return
        if origin and not _origin_allowed(origin):
            self._send_json(403, {"error": "origin_not_allowed"})
            return

        if self.server.fixture_id == "auth-http":
            auth = self.headers.get("Authorization", "")
            if not auth.startswith("Bearer "):
                self._send_json(401, {"error": "missing_authorization"})
                return

        if self.server.fixture_id == "broken-http":
            self._send_raw(500, b"broken\n", content_type="text/plain; charset=utf-8")
            return

        length_s = self.headers.get("Content-Length", "0")
        try:
            length = int(length_s)
        except ValueError:
            self._send_json(400, {"error": "invalid_content_length"})
            return

        body = self.rfile.read(max(0, length))
        try:
            req = json.loads(body.decode("utf-8"))
        except Exception:
            self._send_json(400, {"error": "invalid_json"})
            return

        method = req.get("method")
        req_id = req.get("id")
        params = req.get("params") or {}

        if method == "initialize":
            resp = {
                "jsonrpc": "2.0",
                "id": req_id if req_id is not None else 1,
                "result": {
                    "protocolVersion": "2025-11-25",
                    "capabilities": {},
                    "serverInfo": {"name": "hardproof-fixture", "version": "0.0.0"},
                },
            }
            payload = _json_bytes(resp)
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("mcp-session-id", "fixture-session")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
            return

        if method == "notifications/initialized":
            self._send_raw(202, b"", content_type="application/json; charset=utf-8")
            return

        if method == "ping":
            self._send_json(
                200,
                {"jsonrpc": "2.0", "id": req_id if req_id is not None else 2, "result": {}},
            )
            return

        if method == "tools/list":
            self._send_json(
                200,
                {
                    "jsonrpc": "2.0",
                    "id": req_id if req_id is not None else 2,
                    "result": {
                        "tools": [
                            {
                                "name": "test_tool_with_progress",
                                "description": "fixture tool",
                                "inputSchema": {"type": "object"},
                            }
                        ]
                    },
                },
            )
            return

        if method == "tools/call":
            tool_name = params.get("name")
            if tool_name != "test_tool_with_progress":
                self._send_json(
                    200,
                    {
                        "jsonrpc": "2.0",
                        "id": req_id if req_id is not None else 2,
                        "error": {"code": -32601, "message": "unknown tool"},
                    },
                )
                return

            meta = params.get("_meta") or {}
            token = meta.get("progressToken") or "tok"
            payload = _sse_bytes(
                [
                    {
                        "jsonrpc": "2.0",
                        "method": "notifications/progress",
                        "params": {"progressToken": token, "progress": 0.5},
                    },
                    {
                        "jsonrpc": "2.0",
                        "id": req_id if req_id is not None else 2,
                        "result": {"content": [{"type": "text", "text": "ok"}]},
                    },
                ]
            )
            self._send_raw(200, payload, content_type="text/event-stream; charset=utf-8")
            return

        if method in ("resources/subscribe", "resources/unsubscribe"):
            self._send_json(200, {"jsonrpc": "2.0", "id": req_id if req_id is not None else 2, "result": {}})
            return

        # Default to a JSON-RPC method-not-found error, but still HTTP 200.
        self._send_json(
            200,
            {
                "jsonrpc": "2.0",
                "id": req_id,
                "error": {"code": -32601, "message": "method not found"},
            },
        )

    def _send_raw(self, status: int, payload: bytes, *, content_type: str) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def _send_json(self, status: int, obj: object) -> None:
        self._send_raw(status, _json_bytes(obj), content_type="application/json; charset=utf-8")


class _FixtureHttpServer(ThreadingHTTPServer):
    def __init__(self, addr: tuple[str, int], fixture_id: str):
        super().__init__(addr, _Handler)
        self.fixture_id = fixture_id


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--fixture-id", required=True, choices=("good-http", "auth-http", "broken-http"))
    parser.add_argument("--port", type=int, required=True)
    args = parser.parse_args(argv[1:])

    server = _FixtureHttpServer(("127.0.0.1", args.port), args.fixture_id)
    server.serve_forever(poll_interval=0.1)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
