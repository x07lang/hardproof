# External smoke matrix summary

## Tool versions

- hardproof: 0.4.0-beta.2 (345bd66599bb59123e9a05a7e37d71f2679531f7)
- x07: x07 0.1.110
- x07-mcp: f6e3b7f3879cabbba70d49bf29077237cfd86cbd

## STDIO: x07lang-mcp

- status: fail
- score_truth_status: partial
- score_mode: partial
- overall_score: None
- partial_score: 78
- unknown_dimensions: ['trust']
- target: stdio server/x07lang-mcp

## HTTP: postgres-mcp demo (partial)

- status: warn
- score_truth_status: partial
- score_mode: partial
- overall_score: None
- partial_score: 96
- unknown_dimensions: ['trust']
- target: streamable_http http://127.0.0.1:8403/mcp

## Trust-evaluable: postgres-mcp demo (full)

- status: warn
- score_truth_status: publishable
- score_mode: full
- overall_score: 93
- partial_score: 93
- unknown_dimensions: []
- target: streamable_http http://127.0.0.1:8403/mcp

## Corpus

- ok: True
- counts: total=1 ok=1 failed=0

