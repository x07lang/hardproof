#!/usr/bin/env python3
import sys, json, time
def send(o): sys.stdout.write(json.dumps(o)+"\n"); sys.stdout.flush()
for line in sys.stdin:
    line=line.strip()
    if not line: continue
    try: msg=json.loads(line)
    except Exception: time.sleep(3600); continue
    m=msg.get("method"); mid=msg.get("id")
    if m=="initialize":
        send({"jsonrpc":"2.0","id":mid,"result":{"protocolVersion":"2025-11-25","capabilities":{"tools":{}},"serverInfo":{"name":"hang-fixture","version":"1.0"}}})
    elif m=="notifications/initialized":
        pass
    elif m=="tools/list":
        send({"jsonrpc":"2.0","id":mid,"result":{"tools":[]}})
    else:
        time.sleep(3600)  # hang on ping / reliability probes / everything else
