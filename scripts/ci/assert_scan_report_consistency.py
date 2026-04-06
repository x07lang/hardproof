#!/usr/bin/env python3
import json
import math
import sys


EXPECTED_WEIGHTS_PCT = {
    "conformance": 30,
    "security": 20,
    "performance": 15,
    "trust": 20,
    "reliability": 15,
}


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


def main() -> None:
    if len(sys.argv) != 2:
        fail("usage: assert_scan_report_consistency.py <scan.json>")

    report_path = sys.argv[1]
    with open(report_path, "r", encoding="utf-8") as f:
        report = json.load(f)

    dims = report.get("dimensions")
    if not isinstance(dims, list) or not dims:
        fail("dimensions must be a non-empty array")

    seen = set()
    score_weight_total = 0
    score_weight_sum = 0
    has_fail = False
    has_warn = False
    has_unknown = False

    for dim in dims:
        name = dim.get("name")
        if name in seen:
            fail(f"duplicate dimension: {name}")
        seen.add(name)
        if name not in EXPECTED_WEIGHTS_PCT:
            fail(f"unexpected dimension: {name}")

        weight = dim.get("weight")
        expected_weight = EXPECTED_WEIGHTS_PCT[name] / 100.0
        if not isinstance(weight, (int, float)) or abs(weight - expected_weight) > 1e-9:
            fail(f"dimension weight mismatch for {name}: got {weight}, expected {expected_weight}")

        status = dim.get("status")
        if status == "fail":
            has_fail = True
        elif status == "warn":
            has_warn = True
        elif status == "unknown":
            has_unknown = True

        score = dim.get("score")
        if score is None:
            continue
        if not isinstance(score, int) or score < 0 or score > 100:
            fail(f"invalid score for {name}: {score}")

        w_pct = EXPECTED_WEIGHTS_PCT[name]
        score_weight_total += w_pct
        score_weight_sum += w_pct * score

    if set(EXPECTED_WEIGHTS_PCT.keys()) != seen:
        missing = sorted(set(EXPECTED_WEIGHTS_PCT.keys()) - seen)
        extra = sorted(seen - set(EXPECTED_WEIGHTS_PCT.keys()))
        fail(f"dimension set mismatch: missing={missing} extra={extra}")

    score_available = report.get("score_available")
    if not isinstance(score_available, bool):
        fail("score_available must be boolean")

    overall_score = report.get("overall_score")
    computed_score_available = score_weight_total >= 80
    if score_available != computed_score_available:
        fail(
            f"score_available mismatch: got {score_available}, expected {computed_score_available} "
            f"(weight_total={score_weight_total})"
        )

    if not computed_score_available:
        if overall_score is not None:
            fail(f"overall_score must be null when score_available=false (got {overall_score})")
    else:
        if not isinstance(overall_score, int):
            fail(f"overall_score must be integer when score_available=true (got {overall_score})")
        computed_overall = score_weight_sum // score_weight_total
        if overall_score != computed_overall:
            fail(
                f"overall_score mismatch: got {overall_score}, expected {computed_overall} "
                f"(weight_sum={score_weight_sum}, weight_total={score_weight_total})"
            )

    findings = report.get("findings")
    if not isinstance(findings, list):
        fail("findings must be array")
    critical_n = sum(1 for f in findings if f.get("severity") == "critical")
    warning_n = sum(1 for f in findings if f.get("severity") == "warning")

    computed_status = None
    if has_fail:
        computed_status = "fail"
    elif not computed_score_available:
        computed_status = "unknown"
    elif critical_n > 0:
        computed_status = "fail"
    elif warning_n > 0 or has_warn:
        computed_status = "warn"
    elif has_unknown:
        computed_status = "warn"
    else:
        computed_status = "pass"

    status = report.get("status")
    if status != computed_status:
        fail(
            f"status mismatch: got {status}, expected {computed_status} "
            f"(has_fail={has_fail}, has_warn={has_warn}, has_unknown={has_unknown}, "
            f"critical_n={critical_n}, warning_n={warning_n}, score_available={computed_score_available})"
        )

    usage = report.get("usage_metrics")
    if not isinstance(usage, dict):
        fail("usage_metrics must be object")

    if usage.get("estimator_family") == "bytes_per_token_v1":
        tool_catalog_bytes = usage.get("tool_catalog_bytes")
        tool_catalog_tokens = usage.get("tool_catalog_est_tokens_cl100k")
        if not isinstance(tool_catalog_bytes, int) or tool_catalog_bytes < 0:
            fail(f"usage.tool_catalog_bytes must be non-negative integer (got {tool_catalog_bytes})")
        if not isinstance(tool_catalog_tokens, int) or tool_catalog_tokens < 0:
            fail(f"usage.tool_catalog_est_tokens_cl100k must be non-negative integer (got {tool_catalog_tokens})")
        expected_tokens = 0 if tool_catalog_bytes <= 0 else int(math.ceil(tool_catalog_bytes / 4.0))
        if tool_catalog_tokens != expected_tokens:
            fail(
                f"usage token estimate mismatch: got {tool_catalog_tokens}, expected {expected_tokens} "
                f"(tool_catalog_bytes={tool_catalog_bytes})"
            )

        input_schema_bytes_total = usage.get("input_schema_bytes_total")
        input_schema_tokens_total = usage.get("input_schema_est_tokens_total")
        if not isinstance(input_schema_bytes_total, int) or input_schema_bytes_total < 0:
            fail(
                f"usage.input_schema_bytes_total must be non-negative integer (got {input_schema_bytes_total})"
            )
        if not isinstance(input_schema_tokens_total, int) or input_schema_tokens_total < 0:
            fail(
                f"usage.input_schema_est_tokens_total must be non-negative integer (got {input_schema_tokens_total})"
            )
        expected_schema_tokens = 0 if input_schema_bytes_total <= 0 else int(math.ceil(input_schema_bytes_total / 4.0))
        if input_schema_tokens_total != expected_schema_tokens:
            fail(
                f"usage schema token estimate mismatch: got {input_schema_tokens_total}, expected {expected_schema_tokens} "
                f"(input_schema_bytes_total={input_schema_bytes_total})"
            )

        p50 = usage.get("response_payload_est_tokens_p50")
        p95 = usage.get("response_payload_est_tokens_p95")
        if isinstance(p50, int) and isinstance(p95, int) and p95 < p50:
            fail(f"usage response quantiles invalid: p95 < p50 ({p95} < {p50})")


if __name__ == "__main__":
    main()

