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
    dimension_coverage = {}
    unknown_dimensions = []

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
        dimension_coverage[name] = score is not None
        if status == "unknown":
            unknown_dimensions.append(name)
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

    overall_status = report.get("overall_status")
    if overall_status not in {"pass", "warn", "fail", "unknown"}:
        fail(f"overall_status invalid: {overall_status}")

    score_mode = report.get("score_mode")
    if score_mode not in {"full", "partial"}:
        fail(f"score_mode invalid: {score_mode}")

    score_truth_status = report.get("score_truth_status")
    if score_truth_status not in {"publishable", "partial", "insufficient"}:
        fail(f"score_truth_status invalid: {score_truth_status}")

    score_weight_present = report.get("score_weight_present")
    if not isinstance(score_weight_present, int) or score_weight_present < 0 or score_weight_present > 100:
        fail(f"score_weight_present invalid: {score_weight_present}")

    coverage = report.get("dimension_coverage")
    if not isinstance(coverage, dict):
        fail("dimension_coverage must be object")
    if coverage != dimension_coverage:
        fail(f"dimension_coverage mismatch: got {coverage}, expected {dimension_coverage}")

    report_unknown_dimensions = report.get("unknown_dimensions")
    if report_unknown_dimensions != unknown_dimensions:
        fail(
            f"unknown_dimensions mismatch: got {report_unknown_dimensions}, expected {unknown_dimensions}"
        )

    partial_reasons = report.get("partial_reasons")
    gating_reasons = report.get("gating_reasons")
    if not isinstance(partial_reasons, list):
        fail("partial_reasons must be array")
    if not isinstance(gating_reasons, list):
        fail("gating_reasons must be array")

    overall_score = report.get("overall_score")
    partial_score = report.get("partial_score")
    computed_partial_score = None if score_weight_total <= 0 else score_weight_sum // score_weight_total
    computed_score_available = score_truth_status != "insufficient"
    if score_available != computed_score_available:
        fail(
            f"score_available mismatch: got {score_available}, expected {computed_score_available} "
            f"(score_truth_status={score_truth_status})"
        )

    if score_weight_present != score_weight_total:
        fail(
            f"score_weight_present mismatch: got {score_weight_present}, expected {score_weight_total}"
        )

    computed_mode = "full" if score_truth_status == "publishable" else "partial"
    if score_mode != computed_mode:
        fail(f"score_mode mismatch: got {score_mode}, expected {computed_mode}")

    if score_truth_status == "publishable":
        if score_weight_total < 85:
            fail(f"publishable score requires score_weight_present >= 85 (got {score_weight_total})")
        if unknown_dimensions:
            fail(f"publishable score cannot include unknown_dimensions (got {unknown_dimensions})")
        if not isinstance(overall_score, int):
            fail(f"overall_score must be integer when score is publishable (got {overall_score})")
        computed_overall = score_weight_sum // score_weight_total
        if overall_score != computed_overall:
            fail(
                f"overall_score mismatch: got {overall_score}, expected {computed_overall} "
                f"(weight_sum={score_weight_sum}, weight_total={score_weight_total})"
            )
        if not isinstance(partial_score, int):
            fail(f"partial_score must be integer when score is publishable (got {partial_score})")
        if partial_score != computed_partial_score:
            fail(
                f"partial_score mismatch: got {partial_score}, expected {computed_partial_score} "
                f"(weight_sum={score_weight_sum}, weight_total={score_weight_total})"
            )
    elif score_truth_status == "partial":
        if overall_score is not None:
            fail(f"overall_score must be null when score is partial (got {overall_score})")
        if not isinstance(partial_score, int):
            fail(f"partial_score must be integer when score is partial (got {partial_score})")
        if partial_score != computed_partial_score:
            fail(
                f"partial_score mismatch: got {partial_score}, expected {computed_partial_score} "
                f"(weight_sum={score_weight_sum}, weight_total={score_weight_total})"
            )
    else:
        if overall_score is not None:
            fail(f"overall_score must be null when score is insufficient (got {overall_score})")
        if partial_score is not None:
            fail(f"partial_score must be null when score is insufficient (got {partial_score})")

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
    if overall_status != computed_status:
        fail(f"overall_status mismatch: got {overall_status}, expected {computed_status}")

    usage = report.get("usage_metrics")
    if not isinstance(usage, dict):
        fail("usage_metrics must be object")

    if usage.get("estimator_family") == "bytes_per_token_v1":
        estimator_version = usage.get("estimator_version")
        if estimator_version != "v1":
            fail(f"usage.estimator_version mismatch: got {estimator_version}, expected v1")

        tool_catalog_bytes = usage.get("tool_catalog_bytes")
        tool_catalog_tokens = usage.get("tool_catalog_est_tokens_cl100k")
        tool_count = usage.get("tool_count")
        if not isinstance(tool_catalog_bytes, int) or tool_catalog_bytes < 0:
            fail(f"usage.tool_catalog_bytes must be non-negative integer (got {tool_catalog_bytes})")
        if not isinstance(tool_catalog_tokens, int) or tool_catalog_tokens < 0:
            fail(f"usage.tool_catalog_est_tokens_cl100k must be non-negative integer (got {tool_catalog_tokens})")
        if not isinstance(tool_count, int) or tool_count < 0:
            fail(f"usage.tool_count must be non-negative integer (got {tool_count})")
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

        metadata_ratio = usage.get("metadata_to_payload_ratio_pct")
        if not isinstance(metadata_ratio, int) or metadata_ratio < 0:
            fail(
                f"usage.metadata_to_payload_ratio_pct must be non-negative integer (got {metadata_ratio})"
            )


if __name__ == "__main__":
    main()
