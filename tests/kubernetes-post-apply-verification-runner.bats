#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  export SCRIPT="${REPO_ROOT}/kubernetes/scripts/run-post-apply-verification.sh"
}

install_fake_make() {
  local bin_dir="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${bin_dir}"
  cat >"${bin_dir}/make" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${MAKE_CAPTURE}"
EOF
  chmod +x "${bin_dir}/make"
  export PATH="${bin_dir}:${PATH}"
}

@test "post-apply runner maps Lima plan steps to Make invocations" {
  install_fake_make
  export MAKE_CAPTURE="${BATS_TEST_TMPDIR}/make-calls"

  run bash -c 'printf "%s\n" configure-k3s-apiserver-oidc check-health check-gateway-urls check-sso-e2e | "$SCRIPT" --execute --variant-json "$REPO_ROOT/kubernetes/variants/lima/variant.json" --stage 900 --make-dir "$REPO_ROOT/kubernetes/lima"'

  [ "${status}" -eq 0 ]
  expected=$'-C '"${REPO_ROOT}"$'/kubernetes/lima configure-k3s-apiserver-oidc\n-C '"${REPO_ROOT}"$'/kubernetes/lima check-health STAGE=900\n-C '"${REPO_ROOT}"$'/kubernetes/lima check-gateway-urls STAGE=900\n-C '"${REPO_ROOT}"$'/kubernetes/lima check-sso-e2e STAGE=900'
  [ "$(cat "${MAKE_CAPTURE}")" = "${expected}" ]
}

@test "post-apply runner does not let make steps consume the remaining plan" {
  local bin_dir="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${bin_dir}"
  cat >"${bin_dir}/make" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
printf '%s\n' "$*" >>"${MAKE_CAPTURE}"
EOF
  chmod +x "${bin_dir}/make"
  export PATH="${bin_dir}:${PATH}"
  export MAKE_CAPTURE="${BATS_TEST_TMPDIR}/make-calls"

  run bash -c 'printf "%s\n" configure-k3s-apiserver-oidc check-health check-gateway-urls check-sso-e2e | "$SCRIPT" --execute --variant-json "$REPO_ROOT/kubernetes/variants/lima/variant.json" --stage 900 --make-dir "$REPO_ROOT/kubernetes/lima"'

  [ "${status}" -eq 0 ]
  [ "$(wc -l <"${MAKE_CAPTURE}" | tr -d ' ')" -eq 4 ]
}

@test "post-apply runner rejects unknown planned steps clearly" {
  install_fake_make
  export MAKE_CAPTURE="${BATS_TEST_TMPDIR}/make-calls"

  run bash -c 'printf "%s\n" check-health not-a-step | "$SCRIPT" --execute --variant-json "$REPO_ROOT/kubernetes/variants/kind/variant.json" --stage 900 --make-dir "$REPO_ROOT/kubernetes/kind"'

  [ "${status}" -eq 1 ]
  [[ "${output}" == *"Unknown post-apply verification step: not-a-step"* ]]
}
