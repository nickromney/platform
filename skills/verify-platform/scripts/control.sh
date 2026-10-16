#!/usr/bin/env bash
# Verification harness for the platform Docker Compose dev stack (edge + Dex SSO + APIM + subnetcalc dev).
# Built on verify-kit (scripts/verify-lib.sh). The compose project name (`compose`) and edge port 8443
# are fixed by docker/compose, so only one instance can exist: launch refuses when one is already
# running, and cleanup only stops a stack this run launched. Bash 3.2 compatible. Run with --help.
# shellcheck disable=SC2034 # VK_* settings are read by the sourced verify-lib.sh
set -euo pipefail

# Absolute script path first: the repo root is entered below, before the library is sourced.
VK_SCRIPT="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
SKILL_SCRIPTS="$(dirname "$VK_SCRIPT")"
PLATFORM_ROOT="$(git -C "$SKILL_SCRIPTS" rev-parse --show-toplevel)"
cd "$PLATFORM_ROOT"

VK_APP="platform"
VK_BROWSER_SKILL=1
VK_DESCRIPTION="Verification harness for the platform compose dev stack (edge, Dex SSO, APIM simulator, subnetcalc dev)."
VK_DEFAULT_BASE_DIR="$PLATFORM_ROOT/.run/verify"
VK_DEFAULT_EVIDENCE_ROOT="$PLATFORM_ROOT/.run/verify"
# shellcheck source=verify-lib.sh disable=SC1091
. "$SKILL_SCRIPTS/verify-lib.sh"

APP_URL="https://subnetcalc.dev.compose.127.0.0.1.sslip.io:8443/"
DEX_PREFIX="https://dex.compose.127.0.0.1.sslip.io:8443/dex/"
APIM_HEALTH="http://localhost:8302/apim/health"
DRIVE_OUT=""
LOGS_OUT=""

stack_running() { docker compose ls --format json 2>/dev/null | grep -q '"Name":"compose"'; }
redirect_to_dex() {
  case "$(curl -sS -o /dev/null -w '%{redirect_url}' "$APP_URL" 2>/dev/null)" in
    "$DEX_PREFIX"*) return 0 ;;
    *) return 1 ;;
  esac
}
stack_ready() { redirect_to_dex && curl -fsS -o /dev/null "$APIM_HEALTH" 2>/dev/null; }

vk_commands_help() {
  cat <<'HELP'
  launch                 refuse if compose project 'compose' or :8443 exists; build Go binaries, install e2e deps, make -C docker/compose up-dev
  doctor                 read-only: our stack is up, edge owns 8443, SSO redirects, APIM healthy
  drive <cmd> ...        headless $VERIFY_BROWSER (chromium|firefox|webkit) through Dex SSO: login | lookup <address>
  logs                   save apim-simulator, router, api and oauth2-proxy logs into the evidence directory
  cleanup                make -C docker/compose down (only if this run launched it); evidence kept
HELP
}

vk_sample_commands() {
  printf '%s\n' verify launch doctor "drive lookup 10.0.0.0/24" logs cleanup
}

vk_paths() {
  STATE="$VK_BASE_DIR/$VK_RUN_ID/state"
  EVIDENCE="$VK_EVIDENCE_ROOT/$VK_RUN_ID/evidence"
}

vk_plan() {
  case "$1" in
    verify)
      local bs
      bs="$(vk_browsers | tr '\n' ' ')"
      vk_plan_line "launch, doctor, drive lookup 10.0.0.0/24 in each of: $bs (expect 'Usable Addresses' and 251), logs (expect path=/api/v1/ipv4/subnet-info status=200), cleanup; evidence in $EVIDENCE" ;;
    launch) vk_plan_line "refuse if compose project 'compose' or a :8443 listener exists; bun install --frozen-lockfile in tests/kubernetes/sso; make -C docker/compose up-dev; write $STATE/launched and $EVIDENCE" ;;
    doctor) vk_plan_line "read-only: check $STATE/launched, compose project 'compose', compose-edge-1 on :8443, Dex redirect and APIM health" ;;
    drive) shift; vk_plan_line "node $VK_SCRIPT_DIR/drive.mjs ${*:-<command>} with headless ${VERIFY_BROWSER:-chromium}; evidence in $EVIDENCE/<stamp>-${1:-drive}-${VERIFY_BROWSER:-chromium}" ;;
    logs) vk_plan_line "docker logs for apim-simulator, subnetcalc-router-dev, subnetcalc-api-dev, oauth2-proxy-subnetcalc-dev into $EVIDENCE/<stamp>-logs" ;;
    cleanup) vk_plan_line "make -C docker/compose down only if $STATE/launched exists; remove that marker and $STATE if empty; clear current only if it names this run; keep evidence in $EVIDENCE" ;;
    *) vk_unknown_command ;;
  esac
}

cmd_launch() {
  if stack_running || vk_port_busy 8443; then
    vk_fail "a compose project named 'compose' or a listener on :8443 already exists; it is not ours. Stop it yourself (make -C docker/compose down) if it is safe to."
    return 1
  fi
  mkdir -p "$STATE" "$EVIDENCE" || { vk_fail "cannot create $STATE or $EVIDENCE"; return 1; }
  vk_mark_current
  vk_record_revision "$EVIDENCE/revision.txt"
  "$SKILL_SCRIPTS/runtime-snapshot.sh" capture "$EVIDENCE/unrelated-containers.before.txt" || return 1
  (cd tests/kubernetes/sso && bun install --frozen-lockfile) >> "$EVIDENCE/launch.log" 2>&1 \
    || { vk_fail "bun install failed; see $EVIDENCE/launch.log"; return 1; }
  # up-dev builds the linux/amd64 app binaries itself (docker/compose `binaries` prerequisite).
  if ! make -C docker/compose up-dev >> "$EVIDENCE/launch.log" 2>&1; then
    touch "$STATE/launched"
    vk_fail "up-dev failed; see $EVIDENCE/launch.log"
    return 1
  fi
  touch "$STATE/launched"
  if vk_wait_for 120 stack_ready; then
    vk_say "ready run=$VK_RUN_ID url=$APP_URL (login demo@dev.test)"
    return 0
  fi
  vk_fail "stack not ready after 120s; see $EVIDENCE/launch.log and make -C docker/compose logs"
  return 1
}

cmd_doctor() {
  local owner
  vk_say "run=$VK_RUN_ID"
  [ -f "$STATE/launched" ] || { vk_fail "this run did not launch a stack"; return 1; }
  stack_running || { vk_fail "compose project 'compose' is not running"; return 1; }
  owner="$(docker ps --filter publish=8443 --format '{{.Names}}' | head -1)"
  [ "$owner" = compose-edge-1 ] || { vk_fail ":8443 published by '${owner:-nothing}', not compose-edge-1"; return 1; }
  redirect_to_dex || { vk_fail "$APP_URL does not redirect to Dex"; return 1; }
  curl -fsS -o /dev/null "$APIM_HEALTH" || { vk_fail "APIM health"; return 1; }
  local b
  for b in $(vk_browsers); do
    (cd tests/kubernetes/sso && node -e 'const pw=require("playwright-core"); process.exit(require("fs").existsSync(pw[process.argv[1]].executablePath())?0:1)' "$b") >/dev/null 2>&1 \
      || { vk_fail "Playwright $b is not installed; run: cd tests/kubernetes/sso && bunx playwright install $b"; return 1; }
  done
  vk_say "revision $(head -1 "$EVIDENCE/revision.txt") (now $(git rev-parse HEAD))"
  vk_say "OK services=$(docker compose -p compose ps --services --status running | tr '\n' ',')"
}

cmd_drive() {
  [ -f "$STATE/launched" ] || { vk_fail "no stack launched by run $VK_RUN_ID"; return 1; }
  local browser="${VERIFY_BROWSER:-chromium}"
  DRIVE_OUT="$EVIDENCE/$(vk_stamp)-${1:-drive}-$browser"
  VERIFY_BROWSER="$browser" VERIFY_REPO_ROOT="$PLATFORM_ROOT" VERIFY_APP_URL="$APP_URL" VERIFY_EVIDENCE_DIR="$DRIVE_OUT" \
    node "$VK_SCRIPT_DIR/drive.mjs" ${@+"$@"}
  vk_say "evidence: $DRIVE_OUT"
}

cmd_logs() {
  LOGS_OUT="$EVIDENCE/$(vk_stamp)-logs"
  mkdir -p "$LOGS_OUT"
  local svc
  for svc in apim-simulator subnetcalc-router-dev subnetcalc-api-dev oauth2-proxy-subnetcalc-dev; do
    docker logs "compose-$svc-1" > "$LOGS_OUT/$svc.log" 2>&1 || true
  done
  vk_say "evidence: $LOGS_OUT"
}

# launch writes exactly one file into the state dir (the launched marker), so cleanup removes
# exactly that file and then the directory only if it is empty. Evidence is never touched.
cmd_cleanup() {
  if [ -f "$STATE/launched" ]; then
    mkdir -p "$EVIDENCE"
    make -C docker/compose down > "$EVIDENCE/down.log" 2>&1 || {
      vk_fail "compose cleanup failed; ownership marker and evidence retained for retry"
      return 1
    }
    "$SKILL_SCRIPTS/runtime-snapshot.sh" assert "$EVIDENCE/unrelated-containers.before.txt" \
      > "$EVIDENCE/unrelated-containers.after.txt" 2>&1 || {
      vk_fail "unrelated runtime changed; see $EVIDENCE/unrelated-containers.after.txt"
      return 1
    }
  else
    vk_say "this run did not launch the stack; leaving any running compose project alone"
  fi
  rm -f "$STATE/launched"
  rmdir "$STATE" 2>/dev/null || true
  vk_clear_current
  vk_say "cleaned run=$VK_RUN_ID; evidence kept at $EVIDENCE"
}

vk_verify_recipes() {
  local browsers b
  browsers="$(vk_browsers)"
  for b in $browsers; do
    VERIFY_BROWSER="$b"; export VERIFY_BROWSER
    cmd_drive lookup 10.0.0.0/24
    vk_expect_contains "$DRIVE_OUT/steps.jsonl" '"result":"PASS"'
    vk_expect_contains "$DRIVE_OUT/03-lookup-results.txt" 'Usable Addresses'
    vk_expect_contains "$DRIVE_OUT/03-lookup-results.txt" '251'
    cmd_logs
    vk_expect_contains "$LOGS_OUT/apim-simulator.log" 'path=/api/v1/ipv4/subnet-info status=200'
  done
}

vk_dispatch() {
  local cmd="$1"
  shift
  case "$cmd" in
    launch) cmd_launch ;;
    doctor) cmd_doctor ;;
    drive) cmd_drive ${@+"$@"} ;;
    logs) cmd_logs ;;
    cleanup) cmd_cleanup ;;
    *) vk_unknown_command ;;
  esac
}

vk_main "$@"
