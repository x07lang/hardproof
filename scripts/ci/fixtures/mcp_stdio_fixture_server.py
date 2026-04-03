#!/usr/bin/env python3

import argparse
import json
import sys


def _json_line(obj: object) -> str:
    return json.dumps(obj, separators=(",", ":"), ensure_ascii=False) + "\n"


def _write(obj: object) -> None:
    sys.stdout.write(_json_line(obj))
    sys.stdout.flush()


def _handle_good(req: dict) -> None:
    method = req.get("method")
    req_id = req.get("id")
    params = req.get("params") or {}

    if method == "initialize":
        _write(
            {
                "jsonrpc": "2.0",
                "id": req_id if req_id is not None else 1,
                "result": {
                    "protocolVersion": "2025-11-25",
                    "capabilities": {},
                    "serverInfo": {"name": "hardproof-fixture", "version": "0.0.0"},
                },
            }
        )
        return

    if method == "notifications/initialized":
        return

    if method == "ping":
        _write({"jsonrpc": "2.0", "id": req_id if req_id is not None else 2, "result": {}})
        return

    if method == "tools/list":
        _write(
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
            }
        )
        return

    if method == "tools/call":
        tool_name = params.get("name")
        if tool_name != "test_tool_with_progress":
            _write(
                {
                    "jsonrpc": "2.0",
                    "id": req_id if req_id is not None else 2,
                    "error": {"code": -32601, "message": "unknown tool"},
                }
            )
            return

        meta = params.get("_meta") or {}
        token = meta.get("progressToken") or "tok"
        _write(
            {
                "jsonrpc": "2.0",
                "method": "notifications/progress",
                "params": {"progressToken": token, "progress": 0.5},
            }
        )
        _write(
            {
                "jsonrpc": "2.0",
                "id": req_id if req_id is not None else 2,
                "result": {"content": [{"type": "text", "text": "ok"}]},
            }
        )
        return

    if method in ("resources/subscribe", "resources/unsubscribe"):
        _write({"jsonrpc": "2.0", "id": req_id if req_id is not None else 2, "result": {}})
        return

    _write(
        {
            "jsonrpc": "2.0",
            "id": req_id,
            "error": {"code": -32601, "message": "method not found"},
        }
    )


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--fixture-id", required=True, choices=("good-stdio", "broken-stdio"))
    args = parser.parse_args(argv[1:])

    if args.fixture_id == "broken-stdio":
        # Consume stdin, emit no responses.
        for _line in sys.stdin:
            pass
        return 0

    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            req = json.loads(line)
        except Exception:
            continue
        if isinstance(req, dict):
            _handle_good(req)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))

