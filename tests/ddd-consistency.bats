#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  export GLOSSARY="${REPO_ROOT}/docs/ddd/ubiquitous-language.md"
}

section_occurrence_count() {
  local heading="$1"
  local pattern="$2"

  awk -v heading="${heading}" '
    $0 == heading { in_section=1; next }
    in_section && /^## / { exit }
    in_section { print }
  ' "${GLOSSARY}" | rg -o "${pattern}" | wc -l | tr -d '[:space:]'
}

@test "ubiquitous language auth method values match the glossary-approved enum vocabulary" {
  run rg -n '^\\| auth method \\| the backend auth strategy \\| `none`, `api_key`, `jwt`, `azure_swa`, `apim`, `azure_ad`\\. \\|$' "${GLOSSARY}"

  [ "${status}" -eq 0 ]
}

@test "ubiquitous language confines Easy Auth to the Identity And Access section" {
  total_count="$(rg -o 'Easy Auth' "${GLOSSARY}" | wc -l | tr -d '[:space:]')"
  identity_count="$(section_occurrence_count '## Identity And Access Language' 'Easy Auth')"

  [ "${total_count}" -eq 1 ]
  [ "${identity_count}" -eq 1 ]
}

@test "ubiquitous language treats lookup as a frontend orchestration term" {
  run rg -n '^\\| lookup \\| the frontend'"'"'s combined query over validation, private-range, Cloudflare, and subnet-info checks \\| Frontend orchestration term; not a backend domain concept pre-launch\\. \\|$' "${GLOSSARY}"

  [ "${status}" -eq 0 ]

  run rg -n 'Useful application term, not yet a clear domain term' "${GLOSSARY}"

  [ "${status}" -eq 1 ]
}
