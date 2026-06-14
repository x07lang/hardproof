#!/usr/bin/env python3
# Passes discovery/conformance (initialize, tools/list, ping, tools/call) but
# hangs on every other request (invalid jsonrpc methods, reliability probes,
# malformed input). A healthy discovery means the scan does NOT short-circuit,
# so without a bounded probe timeout the per-process timeouts STACK across
# dimensions. Used to prove HARDPROOF_PROBE_TIMEOUT_MS bounds the total cost.
import sys, json, time
def send(o): sys.stdout.write(json.dumps(o)+"\n"); sys.stdout.flush()
for line in sys.stdin:
    line=line.strip()
    if not line: continue
    try: msg=json.loads(line)
    except Exception:
        time.sleep(3600); continue   # hang on malformed (non-JSON) input
    m=msg.get("method"); mid=msg.get("id")
    if m=="initialize":
        send({"jsonrpc":"2.0","id":mid,"result":{"protocolVersion":"2025-11-25","capabilities":{"tools":{}},"serverInfo":{"name":"late-hang","version":"1.0"}}})
    elif m=="notifications/initialized":
        pass
    elif m=="tools/list":
        send({"jsonrpc":"2.0","id":mid,"result":{"tools":[{"name":"echo","description":"echo","inputSchema":{"type":"object"}}]}})
    elif m=="ping":
        send({"jsonrpc":"2.0","id":mid,"result":{}})
    elif m=="tools/call":
        send({"jsonrpc":"2.0","id":mid,"result":{"content":[{"type":"text","text":"ok"}]}})
    else:
        time.sleep(3600)  # hang on anything unexpected
