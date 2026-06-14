#!/usr/bin/env python3
# Minimal stdio MCP server that is RESILIENT to malformed/invalid input:
# it ignores unparseable lines and keeps serving (the well-behaved case).
import sys, json
def send(o): sys.stdout.write(json.dumps(o)+"\n"); sys.stdout.flush()
for line in sys.stdin:
    line=line.strip()
    if not line: continue
    try:
        msg=json.loads(line)
    except Exception:
        continue  # malformed JSON -> ignore, stay alive
    if not isinstance(msg.get("method"), str):
        continue  # invalid jsonrpc -> ignore, stay alive
    mid=msg.get("id"); m=msg.get("method")
    if m=="initialize":
        send({"jsonrpc":"2.0","id":mid,"result":{"protocolVersion":"2025-11-25","capabilities":{"tools":{}},"serverInfo":{"name":"resilient-fixture","version":"1.0"}}})
    elif m=="notifications/initialized":
        pass
    elif m=="ping":
        send({"jsonrpc":"2.0","id":mid,"result":{}})
    elif m=="tools/list":
        send({"jsonrpc":"2.0","id":mid,"result":{"tools":[{"name":"echo","description":"echo","inputSchema":{"type":"object"}}]}})
    else:
        send({"jsonrpc":"2.0","id":mid,"error":{"code":-32601,"message":"method not found"}})
