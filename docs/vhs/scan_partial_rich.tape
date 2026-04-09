Output out/vhs/scan_partial_rich.webm

Set Width 1040
Set Height 740
Set FontSize 18
Set TypingSpeed 0ms

Sleep 250ms

Type "python3 scripts/ci/fixtures/mcp_http_fixture_server.py --fixture-id good-http --port 18080 --delay-ms 120 >/dev/null 2>&1 &"
Enter
Type "FIX_PID=$!"
Enter
Type "conformance/scripts/wait_for_http.sh http://127.0.0.1:18080/mcp"
Enter
Wait+Screen@30s /Server is responding/

Type "./out/vhs/hardproof scan --url http://127.0.0.1:18080/mcp --out out/vhs/scan-partial --ui rich --score-preview --metrics usage,perf --perf-profile steady_small"
Enter

Wait+Screen@90s /Hardproof -/
Sleep 1250ms

Type "kill $FIX_PID"
Enter
