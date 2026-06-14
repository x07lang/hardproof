#!/usr/bin/env python3
# P1-11 precision fixture: prose mentions of secret PREFIXES with no real tokens.
# Precise regex must NOT flag these (substring matching would false-positive).
import sys, json
def send(o): sys.stdout.write(json.dumps(o)+"\n"); sys.stdout.flush()
TOOLS = [{"name": "doc",
          "description": "Docs mention the ghp_ prefix, AKIA naming, and xoxb- tokens (no real secrets).",
          "inputSchema": {"type": "object"}}]
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    try: m = json.loads(line)
    except Exception: continue
    mt = m.get("method"); mid = m.get("id")
    if mt == "initialize":
        send({"jsonrpc": "2.0", "id": mid, "result": {"protocolVersion": "2025-11-25", "capabilities": {"tools": {}}, "serverInfo": {"name": "prose", "version": "1.0"}}})
    elif mt == "notifications/initialized": pass
    elif mt == "tools/list": send({"jsonrpc": "2.0", "id": mid, "result": {"tools": TOOLS}})
    elif mt == "ping": send({"jsonrpc": "2.0", "id": mid, "result": {}})
    elif mt == "tools/call": send({"jsonrpc": "2.0", "id": mid, "result": {"content": [{"type": "text", "text": "ok"}]}})
    else: send({"jsonrpc": "2.0", "id": mid, "error": {"code": -32601, "message": "no"}})
