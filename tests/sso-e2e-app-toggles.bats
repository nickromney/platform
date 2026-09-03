#!/usr/bin/env bats

setup() {
  source "$(git -C "$(dirname "${BATS_TEST_FILENAME}")" rev-parse --show-toplevel)/tests/test_helper.bash"
  setup_repo_root
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

# #126 moved the tfvars layering out of the recipe and into
# build-sso-e2e-env.sh, which the Makefile evals before passing the result on.
# The local `tfvar_files_joined` this used to assert on has not existed since,
# so the contract checked here is the pass-through, not the variable name.
assert "BUILD_SSO_E2E_ENV" in kind_makefile
assert 'STAGE_TFVARS_FILES="$${STAGE_TFVARS_FILES}"' in kind_makefile
PY
}

@test "SSO working suite requires a data contract for every smoke target" {
  python3 - <<'PY' "${REPO_ROOT}"
import pathlib
import re
import sys

repo = pathlib.Path(sys.argv[1])
harness = (repo / "tests/kubernetes/sso/lib/harness.ts").read_text()
working = (repo / "tests/kubernetes/sso/lib/working.ts").read_text()
run_sh = (repo / "tests/kubernetes/sso/run.sh").read_text()
kind_makefile = (repo / "kubernetes/kind/Makefile").read_text()
lima_makefile = (repo / "kubernetes/lima/Makefile").read_text()

assert "SSO_E2E_PROJECT" in run_sh
assert "--project" in run_sh
assert "check-sso-working" in kind_makefile
assert "check-sso-working" in lima_makefile
assert "SSO_E2E_PROJECT=working" in kind_makefile
assert "SSO_E2E_PROJECT=working" in lima_makefile
assert "hubbleUatServiceMapWorks" in working
assert "HUBBLE_EMPTY_SERVICE_MAP" in working
assert "loginArgocdConsoleIfNeeded" in harness
assert "WORKING_BY_NAME" in working

names = set(re.findall(r"name:\s*'([^']+)'", harness))
for required in (
    "hubble-admin",
    "gitea-admin",
    "argocd-admin",
    "kyverno-admin",
    "apim-admin",
    "sentiment-uat",
    "grafana-launchpad",
):
    assert required in names, required
    assert f"'{required}'" in working, f"working contract missing for {required}"
PY
}

@test "SSO E2E spec filters sentiment and subnetcalc targets by feature toggles" {
  python3 - <<'PY' "${REPO_ROOT}"
import pathlib
import sys

repo = pathlib.Path(sys.argv[1])
spec = (repo / "tests/kubernetes/sso/lib/harness.ts").read_text()

assert "INCLUDE_SENTIMENT" in spec
assert "INCLUDE_SUBNETCALC" in spec
assert "filterTargetByEnabledApps" in spec
assert "sentiment-" in spec
assert "subnetcalc-" in spec
PY
}
