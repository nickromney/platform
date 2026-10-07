#!/usr/bin/env bats

setup() {
  source "$(git -C "$(dirname "${BATS_TEST_FILENAME}")" rev-parse --show-toplevel)/tests/test_helper.bash"
  setup_repo_root
  VALIDATOR="${REPO_ROOT}/scripts/validate-json-schema.sh"
  PAYLOAD="${BATS_TEST_TMPDIR}/payload.json"
  SCHEMA="${BATS_TEST_TMPDIR}/schema.json"
}

@test "real catalog schema refuses wrong applications type and missing nested fields" {
  for data in '{"schema_version":"platform.idp/v1","applications":false}' '{"schema_version":"platform.idp/v1","applications":[{"name":"one"}]}'; do
    printf '%s\n' "$data" >"$PAYLOAD"
    run "$VALIDATOR" "${REPO_ROOT}/schemas/idp/catalog.schema.json" "$PAYLOAD"
    [ "$status" -ne 0 ]
    [[ "$output" == *invalid_payload* ]]
  done
  run "$VALIDATOR" "${REPO_ROOT}/schemas/idp/catalog.schema.json" "${REPO_ROOT}/catalog/platform-apps.json"
  [ "$status" -eq 0 ]
}

@test "internal definitions validate nested enums and external refs refuse" {
  printf '%s\n' '{"$defs":{"entry":{"type":"string","enum":["one"]}},"type":"array","items":{"$ref":"#/$defs/entry"}}' >"$SCHEMA"
  printf '%s\n' '["one"]' >"$PAYLOAD"
  run "$VALIDATOR" "$SCHEMA" "$PAYLOAD"
  [ "$status" -eq 0 ]
  printf '%s\n' '["two"]' >"$PAYLOAD"
  run "$VALIDATOR" "$SCHEMA" "$PAYLOAD"
  [ "$status" -ne 0 ]
  for ref in 'https://invalid.example.test/schema.json' 'file:///etc/passwd' 'other.json'; do
    printf '{"$ref":"%s"}\n' "$ref" >"$SCHEMA"
    run "$VALIDATOR" "$SCHEMA" "$PAYLOAD"
    [ "$status" -ne 0 ]
    [[ "$output" == *external_refs_disabled* ]]
  done
}

@test "schema adapter unit regressions enforce nested types and closed reference loading" {
  run go -C "${REPO_ROOT}/tools/platform-helpers" test ./cmd/validate-json-schema
  [ "$status" -eq 0 ]
}
