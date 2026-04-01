#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${repo_root}"

echo "==> fmt"
while IFS= read -r path; do
  x07 fmt --input "${path}" --check --report-json >/dev/null
done < <(find cli/src -name '*.x07.json' -print | LC_ALL=C sort)

echo "==> pkg lock"
x07 pkg lock --project x07.json --check --json=off >/dev/null

echo "==> arch check"
x07 arch check --manifest arch/manifest.x07arch.json >/dev/null

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

bin_path="${tmp_dir}/x07-mcp-test"
x07 bundle --project x07.json --profile os --json=off --out "${bin_path}" >/dev/null
chmod +x "${bin_path}"

echo "==> cli smoke"
"${bin_path}" --help >/dev/null

echo "==> schema fixtures"
"${bin_path}" ci validate-fixtures

echo "==> doctor smoke"
ok_json="${tmp_dir}/doctor.ok.json"
"${bin_path}" doctor --machine json >"${ok_json}"
python3 scripts/ci/assert_doctor_json.py \
  "${ok_json}" true \
  os.uname=true \
  tmp.writable=true \
  shell.sh=true \
  node.present=true \
  npm.present=true \
  npx.present=true \
  url.reachable=true \
  cmd.present=true

bad_cmd="$(tr -d '\n' < fixtures/doctor/bad_cmd.txt)"
bad_cmd_json="${tmp_dir}/doctor.bad_cmd.json"
if "${bin_path}" doctor --machine json --cmd "${bad_cmd}" >"${bad_cmd_json}"; then
  echo "ERROR: expected doctor to fail for fixture cmd (got exit 0): ${bad_cmd}" >&2
  exit 1
fi
python3 scripts/ci/assert_doctor_json.py "${bad_cmd_json}" false cmd.present=false

bad_url="$(tr -d '\n' < fixtures/doctor/bad_url.txt)"
bad_url_json="${tmp_dir}/doctor.bad_url.json"
if "${bin_path}" doctor --machine json --url "${bad_url}" >"${bad_url_json}"; then
  echo "ERROR: expected doctor to fail for fixture url (got exit 0): ${bad_url}" >&2
  exit 1
fi
python3 scripts/ci/assert_doctor_json.py "${bad_url_json}" false url.reachable=false

echo "==> conformance fixtures"

run_conformance_fixture() (
  local fixture_id="${1:?missing fixture_id}"
  local fixture_mode="${2:?missing fixture_mode}"
  local fixture_url="${3:?missing fixture_url}"
  local expected_exit="${4:?missing expected_exit}"

  local fixture_out_dir="out/ci-conformance/${fixture_id}"
  rm -rf "${fixture_out_dir}"
  mkdir -p "${fixture_out_dir}"

  local server_log="${fixture_out_dir}/server.log"
  conformance/scripts/spawn_reference_http.sh "${fixture_id}" "${fixture_mode}" >"${server_log}" 2>&1 &
  local server_pid="$!"

  cleanup() {
    kill "${server_pid}" >/dev/null 2>&1 || true
    wait "${server_pid}" >/dev/null 2>&1 || true
  }
  trap cleanup EXIT

  if ! conformance/scripts/wait_for_http.sh "${fixture_url}" >/dev/null; then
    echo "ERROR: fixture failed to start: ${fixture_id} (${fixture_url})" >&2
    tail -n 200 "${server_log}" >&2 || true
    exit 1
  fi

  set +e
  "${bin_path}" conformance run \
    --url "${fixture_url}" \
    --baseline conformance/pinned/conformance-baseline.yml \
    --out "${fixture_out_dir}" \
    --machine json >"${fixture_out_dir}/summary.stdout.json"
  local exit_code="$?"
  set -e

  if [[ "${exit_code}" != "${expected_exit}" ]]; then
    echo "ERROR: conformance run exit code mismatch for ${fixture_id} (expected ${expected_exit}, got ${exit_code})" >&2
    tail -n 200 "${server_log}" >&2 || true
    exit 1
  fi

  "${bin_path}" ci validate-json \
    --schema schemas/x07.mcp.conformance.summary.schema.json \
    --input "${fixture_out_dir}/summary.json"

  test -s "${fixture_out_dir}/summary.junit.xml"
  python3 scripts/ci/assert_junit_xml.py "${fixture_out_dir}/summary.junit.xml"
  test -s "${fixture_out_dir}/summary.html"
)

run_conformance_fixture good-http noauth http://127.0.0.1:18080/mcp 0
run_conformance_fixture auth-http oauth http://127.0.0.1:18081/mcp 1
run_conformance_fixture broken-http noauth http://127.0.0.1:18082/mcp 1
