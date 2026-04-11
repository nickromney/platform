#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$ROOT_DIR/scripts/tutorial_lib.sh"

init_tutorial_env
EXECUTE=0
VERIFY=0
MOCK_API_ID="${MOCK_API_ID:-mock-only}"
MOCK_API_PATH="${MOCK_API_PATH:-mock-only}"
MOCK_OPERATION_ID="${MOCK_OPERATION_ID:-test-call}"

usage() {
  cat <<EOF
Usage: ./docs/tutorials/apim-get-started/tutorial03.sh [--setup|--execute|--verify]

Runs tutorial step 3 for the APIM simulator.

Flags:
  --setup, --execute  Start the local stack and author the mocked tutorial API.
  --verify            Verify the existing tutorial state without restarting it.
  --help, -h          Show this help text.
EOF
}

verify_tutorial() {
  echo "Verifying mocked response"

  echo '$ curl -sS "'"$APIM_BASE"'/'"$MOCK_API_PATH"'/test"'
  mocked_response="$(gateway_get "/$MOCK_API_PATH/test")"
  json_expect_summary \
    "$mocked_response" \
    '{"sampleField":"test"}' \
    'summary = {"sampleField": data.get("sampleField")}'
  echo
}

while (($# > 0)); do
  case "$1" in
    --setup|--execute)
      EXECUTE=1
      ;;
    --verify)
      VERIFY=1
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

if [[ "$EXECUTE" -eq 1 && "$VERIFY" -eq 1 ]]; then
  echo "Choose either --setup/--execute or --verify." >&2
  usage >&2
  exit 2
fi

if [[ "$EXECUTE" -eq 0 && "$VERIFY" -eq 0 ]]; then
  usage
  exit 0
fi

if [[ "$VERIFY" -eq 1 ]]; then
  run_verify_with_setup_hint "./docs/tutorials/apim-get-started/tutorial03.sh" verify_tutorial
  exit 0
fi

echo "Starting tutorial 03 stack with docker compose"
start_public_stack

echo "Waiting for gateway health at $APIM_BASE/apim/health"
wait_for_gateway

echo "Creating blank API '$MOCK_API_ID'"
api_response="$(management_put "/apim/management/apis/$MOCK_API_ID" "$(cat <<JSON
{"name":"Mock Only","path":"$MOCK_API_PATH","upstream_base_url":"http://example.invalid"}
JSON
)")"
json_expect_summary \
  "$api_response" \
  "{\"id\":\"$MOCK_API_ID\",\"path\":\"$MOCK_API_PATH\",\"upstream_base_url\":\"http://example.invalid\"}" \
  'summary = {"id": data.get("id"), "path": data.get("path"), "upstream_base_url": data.get("upstream_base_url")}'
echo

echo "Adding operation '$MOCK_OPERATION_ID' with an authored example response"
operation_response="$(management_put "/apim/management/apis/$MOCK_API_ID/operations/$MOCK_OPERATION_ID" "$(cat <<JSON
{"name":"Test call","method":"GET","url_template":"/test","responses":[{"status_code":200,"representations":[{"content_type":"application/json","examples":[{"name":"ok","value":{"sampleField":"test"}}]}]}]}
JSON
)")"
json_expect_summary \
  "$operation_response" \
  "{\"example_name\":\"ok\",\"id\":\"$MOCK_OPERATION_ID\",\"method\":\"GET\",\"url_template\":\"/test\"}" \
  'summary = {"example_name": (((((data.get("responses") or [{}])[0]).get("representations") or [{}])[0]).get("examples") or [{}])[0].get("name"), "id": data.get("id"), "method": data.get("method"), "url_template": data.get("url_template")}'
echo

echo "Enabling mock-response on '$MOCK_API_ID:$MOCK_OPERATION_ID'"
policy_response="$(management_put "/apim/management/policies/operation/$MOCK_API_ID:$MOCK_OPERATION_ID" "$(cat <<JSON
{"xml":"<policies><inbound><mock-response status-code=\"200\" content-type=\"application/json\" /></inbound><backend /><outbound /><on-error /></policies>"}
JSON
)")"
json_expect_summary \
  "$policy_response" \
  "{\"contains_mock_response\":true,\"scope_name\":\"$MOCK_API_ID:$MOCK_OPERATION_ID\",\"scope_type\":\"operation\"}" \
  'summary = {"contains_mock_response": "mock-response" in (data.get("xml") or ""), "scope_name": data.get("scope_name"), "scope_type": data.get("scope_type")}'
echo
echo "Setup complete. Run ./docs/tutorials/apim-get-started/tutorial03.sh --verify to validate the mocked response."
