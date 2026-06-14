#!/usr/bin/env python3
# Minimal stdio MCP server that CRASHES (exits) on any malformed/unparseable line.
# Used to prove hardproof still flags genuinely-unreliable servers.
import sys, json
def send(o): sys.stdout.write(json.dumps(o)+"\n"); sys.stdout.flush()
for line in sys.stdin:
    line=line.strip()
    if not line: continue
    try:
        msg=json.loads(line)
    except Exception:
        # malformed JSON -> crash hard (the unreliable behavior)
        sys.exit(7)
    if not isinstance(msg.get("method"), str):
        sys.exit(7)  # invalid jsonrpc -> crash
    mid=msg.get("id"); m=msg.get("method")
    if m=="initialize":
        send({"jsonrpc":"2.0","id":mid,"result":{"protocolVersion":"2025-11-25","capabilities":{"tools":{}},"serverInfo":{"name":"crash-fixture","version":"1.0"}}})
    elif m=="notifications/initialized":
        pass
    elif m=="ping":
        send({"jsonrpc":"2.0","id":mid,"result":{}})
    elif m=="tools/list":
        send({"jsonrpc":"2.0","id":mid,"result":{"tools":[]}})
    else:
        send({"jsonrpc":"2.0","id":mid,"error":{"code":-32601,"message":"method not found"}})
