#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
}

@test "SSO E2E runner derives app toggles from layered tfvars" {
  python3 - <<'PY' "${REPO_ROOT}"
import pathlib
import sys

repo = pathlib.Path(sys.argv[1])
run_sh = (repo / "tests/kubernetes/sso/run.sh").read_text()
kind_makefile = (repo / "kubernetes/kind/Makefile").read_text()

assert "STAGE_TFVARS_FILES" in run_sh
assert "SSO_E2E_ENABLE_SENTIMENT" in run_sh
assert "SSO_E2E_ENABLE_SUBNETCALC" in run_sh
assert 'enable_app_repo_sentiment' in run_sh
assert 'enable_app_repo_subnetcalc' in run_sh
assert 'STAGE_TFVARS_FILES="$$tfvar_files_joined"' in kind_makefile
PY
}

@test "SSO E2E spec filters sentiment and subnetcalc targets by feature toggles" {
  python3 - <<'PY' "${REPO_ROOT}"
import pathlib
import sys

repo = pathlib.Path(sys.argv[1])
spec = (repo / "tests/kubernetes/sso/tests/sso-smoke.spec.ts").read_text()

assert "INCLUDE_SENTIMENT" in spec
assert "INCLUDE_SUBNETCALC" in spec
assert "filterTargetByEnabledApps" in spec
assert "sentiment-" in spec
assert "subnetcalc-" in spec
PY
}
