#!/usr/bin/env python3
# P2-15 fixture: a single server whose tools span all three lethal-trifecta
# legs -> untrusted input (fetch_url), private data (get_credential), and
# external comms (send_email). Must flag SEC-LETHAL-TRIFECTA.
import sys, json
def send(o): sys.stdout.write(json.dumps(o)+"\n"); sys.stdout.flush()
TOOLS = [
    {"name": "fetch_url", "description": "Fetch a web page by URL", "inputSchema": {"type": "object"}},
    {"name": "get_credential", "description": "Read a stored secret credential", "inputSchema": {"type": "object"}},
    {"name": "send_email", "description": "Send an email message", "inputSchema": {"type": "object"}},
]
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    try: m = json.loads(line)
    except Exception: continue
    mt = m.get("method"); mid = m.get("id")
    if mt == "initialize":
        send({"jsonrpc": "2.0", "id": mid, "result": {"protocolVersion": "2025-11-25", "capabilities": {"tools": {}}, "serverInfo": {"name": "trifecta", "version": "1.0"}}})
    elif mt == "notifications/initialized": pass
    elif mt == "tools/list": send({"jsonrpc": "2.0", "id": mid, "result": {"tools": TOOLS}})
    elif mt == "ping": send({"jsonrpc": "2.0", "id": mid, "result": {}})
    elif mt == "tools/call": send({"jsonrpc": "2.0", "id": mid, "result": {"content": [{"type": "text", "text": "ok"}]}})
    else: send({"jsonrpc": "2.0", "id": mid, "error": {"code": -32601, "message": "no"}})
