# shellcheck shell=bash
# verify-lib.sh: the shared harness for project verification skills (verify-kit).
#
# Vendored into skills/verify-<app>/scripts/verify-lib.sh. Do not edit a vendored copy;
# change the origin (harnesses-private/nickromney/verify-kit) and re-vendor with bin/vendor.sh.
# Bash 3.2 compatible (macOS /bin/bash), BSD userland only.
#
# A skill's scripts/control.sh sets configuration, sources this file, defines hooks, then calls
# `vk_main "$@"`:
#
#   VK_APP                    short app name, used in default paths (required)
#   VK_DESCRIPTION            one line for --help (required)
#   VK_DEFAULT_BASE_DIR       state/run root   (default: $TMPDIR/verify-$VK_APP)
#   VK_DEFAULT_EVIDENCE_ROOT  evidence root    (default: the base dir)
#
#   vk_commands_help          print the skill's command lines for --help (two-space indent)
#   vk_sample_commands        print one sample invocation per line (the contract tests dry-run each)
#   vk_paths                  derive the skill's paths (must set EVIDENCE) from VK_BASE_DIR,
#                             VK_EVIDENCE_ROOT and VK_RUN_ID; must not write anything
#   vk_plan <cmd> [args]      print what <cmd> would do with vk_plan_line
#   vk_dispatch <cmd> [args]  run <cmd>
#                             (both end their case with `*) vk_unknown_command ;;`, which exits 2)
#   cmd_launch, cmd_doctor, cmd_cleanup, vk_verify_recipes
#   vk_env_help               optional: extra environment lines for --help
#   VK_BROWSER_SKILL=1        optional: the skill drives a web UI, so its recipes run once per
#                             browser from vk_browsers (VERIFY_BROWSERS, default all three engines)
#
# Every control.sh carries the same two shellcheck directives (spelled out in README.md): a
# file-level disable of SC2034, since VK_* settings are read here rather than in control.sh,
# and a source=verify-lib.sh directive that also disables SC1091 on the sourcing line. Repo
# hooks that run shellcheck without -x then stay clean; the contract tests check both ways.
#
# Interface every skill gets: control.sh [--help] [--dry-run|--execute] <command> [args]
# Nothing runs without --execute. A bare call, or a call without --execute, prints the plan.
# `verify` = launch, doctor, recipes, cleanup (cleanup also on failure), then VERIFY PASS.

# Variables such as EVIDENCE are assigned by the skill's vk_paths hook, not here.
# shellcheck disable=SC2154

VK_KIT_VERSION="1.3.3"
VK_SCRIPT_NAME="control.sh"
VK_VERIFY_ACTIVE=0
VK_CLEANUP_ATTEMPTED=0
VK_CLEANUP_RESULT=not_attempted

vk_say() { printf '%s\n' "$*"; }
vk_err() { printf '%s: %s\n' "$VK_SCRIPT_NAME" "$*" >&2; }
vk_plan_line() { printf 'INFO dry-run: %s\n' "$*"; }
vk_fail() { vk_say "FAIL: $*"; return 1; }
vk_unknown_command() { vk_err "unknown command '$VK_CMD'"; return 2; }

vk_usage() {
  cat <<EOF
Usage: $VK_SCRIPT_NAME [--help] [--dry-run|--execute] <command> [args]

$VK_DESCRIPTION
Nothing runs without --execute; a bare call or --dry-run prints the plan instead.

Commands:
  verify                 full proven cycle: launch, doctor, recipes, cleanup (cleanup also on failure)
EOF
  vk_commands_help
  cat <<EOF

Options:
  -h, --help             show this help
  --dry-run              print what the command would do, change nothing
  --execute              run the command

Environment:
  VERIFY_RUN_ID          run to act on (default: the current run, or a new one for launch/verify)
  VERIFY_BASE_DIR        state root (default: $VK_DEFAULT_BASE_DIR)
  VERIFY_EVIDENCE_ROOT   evidence root (default: $VK_DEFAULT_EVIDENCE_ROOT)
EOF
  if [ "${VK_BROWSER_SKILL:-0}" = 1 ]; then
    printf '%s\n' "  VERIFY_BROWSERS        browsers to drive, space or comma separated (default: $VK_BROWSERS_ALL)"
  fi
  if declare -F vk_env_help >/dev/null; then vk_env_help; fi
  printf '\nverify-kit %s\n' "$VK_KIT_VERSION"
}

# Resolve the repository root, the base/evidence roots and the run id. Reads only.
vk_resolve() {
  VK_SCRIPT_DIR="$(cd "$(dirname "$VK_SCRIPT")" && pwd)"
  VK_SKILL_DIR="$(cd "$VK_SCRIPT_DIR/.." && pwd)"
  VK_ROOT="$(git -C "$VK_SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$VK_SKILL_DIR")"
  local tmp_root="${TMPDIR:-/tmp}"
  VK_DEFAULT_BASE_DIR="${VK_DEFAULT_BASE_DIR:-${tmp_root%/}/verify-$VK_APP}"
  VK_DEFAULT_EVIDENCE_ROOT="${VK_DEFAULT_EVIDENCE_ROOT:-$VK_DEFAULT_BASE_DIR}"
  VK_BASE_DIR="${VERIFY_BASE_DIR:-$VK_DEFAULT_BASE_DIR}"
  VK_EVIDENCE_ROOT="${VERIFY_EVIDENCE_ROOT:-$VK_DEFAULT_EVIDENCE_ROOT}"
  if [ -n "${VERIFY_RUN_ID:-}" ]; then
    VK_RUN_ID="$VERIFY_RUN_ID"
  elif [ "$VK_CMD" = launch ] || [ "$VK_CMD" = verify ] || [ ! -f "$VK_BASE_DIR/current" ]; then
    VK_RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$$-$RANDOM-$RANDOM"
  else
    VK_RUN_ID="$(cat "$VK_BASE_DIR/current")"
  fi
  case "$VK_RUN_ID" in
    ""|.|..|*[!A-Za-z0-9._-]*)
      vk_err "invalid run id; use only letters, digits, dot, underscore or hyphen"
      return 2
      ;;
  esac
}

vk_mark_current() { mkdir -p "$VK_BASE_DIR" && printf '%s\n' "$VK_RUN_ID" > "$VK_BASE_DIR/current"; }
# Clear the current-run pointer only if it names this run.
vk_clear_current() {
  if [ -f "$VK_BASE_DIR/current" ] && [ "$(cat "$VK_BASE_DIR/current")" = "$VK_RUN_ID" ]; then
    rm -f "$VK_BASE_DIR/current"
  fi
}
vk_record_revision() {
  { git -C "$VK_ROOT" rev-parse HEAD 2>/dev/null || echo "not-a-git-checkout"; git -C "$VK_ROOT" status --porcelain 2>/dev/null || true; } > "$1"
}

# HHMMSS-NNN: sortable and unique within EVIDENCE, even for several calls per second.
vk_stamp() {
  printf '%s-%03d' "$(date -u +%H%M%S)" "$(find "$EVIDENCE" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')"
}

# ---- browsers (web skills) -------------------------------------------------------------------
# A web skill proves its UI in every engine it ships to, not only Chromium. vk_browsers prints
# the browsers to drive, one per line: VERIFY_BROWSERS (space or comma separated), default all
# three Playwright engines, duplicates dropped. An unknown name or an empty list exits 2.
VK_BROWSERS_ALL="chromium firefox webkit"
vk_browsers() {
  local list b seen=" "
  list="$(printf '%s' "${VERIFY_BROWSERS-$VK_BROWSERS_ALL}" | tr ',' ' ')"
  for b in $list; do
    case " $VK_BROWSERS_ALL " in
      *" $b "*) ;;
      *) vk_err "unknown browser '$b' in VERIFY_BROWSERS (use: $VK_BROWSERS_ALL)"; return 2 ;;
    esac
    case "$seen" in *" $b "*) continue ;; esac
    seen="$seen$b "
    printf '%s\n' "$b"
  done
  if [ "$seen" = " " ]; then vk_err "VERIFY_BROWSERS names no browser"; return 2; fi
}

# ---- assertions used by vk_verify_recipes ----------------------------------------------------
vk_pass() { vk_say "PASS: $*"; }
vk_expect_contains() {   # <file> <fixed text>
  if [ -f "$1" ] && grep -F -q -- "$2" "$1"; then vk_pass "$(basename "$1") contains '$2'"
  else vk_fail "$(basename "$1") lacks '$2'"; fi
}
vk_expect_not_contains() {   # <file> <fixed text>
  local rc=0
  [ -f "$1" ] && [ -r "$1" ] || { vk_fail "cannot read evidence $1"; return 1; }
  grep -F -q -- "$2" "$1" || rc=$?
  case "$rc" in
    1) vk_pass "$(basename "$1") has no '$2'" ;;
    0) vk_fail "$(basename "$1") contains '$2'" ;;
    *) vk_fail "cannot read evidence $1 (grep exit $rc)" ;;
  esac
}
vk_expect_equals() {   # <label> <actual> <expected>
  if [ "$2" = "$3" ]; then vk_pass "$1 = '$3'"; else vk_fail "$1 = '$2', expected '$3'"; fi
}
vk_expect_count() {   # <file> <fixed text> <expected line count>
  local n rc=0
  [ -f "$1" ] && [ -r "$1" ] || { vk_fail "cannot read evidence $1"; return 1; }
  n="$(grep -F -c -- "$2" "$1")" || rc=$?
  [ "$rc" -le 1 ] || { vk_fail "cannot read evidence $1 (grep exit $rc)"; return 1; }
  vk_expect_equals "$(basename "$1") lines containing '$2'" "$n" "$3"
}
vk_expect_line() {   # <file> <line prefix> <fixed text>: the first line starting with prefix contains text
  local line=""
  if [ -f "$1" ]; then line="$(grep -F -- "$2" "$1" | awk -v p="$2" 'index($0, p) == 1 { print; exit }')"; fi
  if [ -n "$line" ] && printf '%s\n' "$line" | grep -F -q -- "$3"; then vk_pass "$(basename "$1") line '$2...' contains '$3'"
  else vk_fail "$(basename "$1") has no line starting '$2' containing '$3'"; fi
}
vk_expect_file() {   # <path>
  if [ -e "$1" ]; then vk_pass "$1 exists"; else vk_fail "$1 is missing"; fi
}

# Hash names, types, contents and symlink targets without following links or writing files.
vk_tree_digest() {   # <directory>
  [ -d "$1" ] || { vk_err "not a directory: $1"; return 1; }
  perl -MFile::Find -MDigest::SHA -e '
    use strict; use warnings;
    local $SIG{__WARN__} = sub { die @_ };
    my $root = shift; chdir $root or die "chdir: $!";
    my @paths;
    find({ no_chdir => 1, wanted => sub { push @paths, $File::Find::name } }, ".");
    my $sha = Digest::SHA->new(256);
    for my $path (sort @paths) {
      my $kind = -l $path ? "link" : -f $path ? "file" : -d $path ? "dir" : "other";
      $sha->add(length($path), ":", $path, $kind, "\0");
      if ($kind eq "file") {
        open my $fh, "<", $path or die "read $path: $!"; binmode $fh;
        my $file = Digest::SHA->new(256); $file->addfile($fh); close $fh or die "close: $!";
        $sha->add($file->hexdigest);
      } elsif ($kind eq "link") {
        my $target = readlink $path; defined $target or die "readlink: $!";
        $sha->add(length($target), ":", $target);
      } elsif ($kind eq "other") { die "unsupported file type: $path"; }
    }
    print $sha->hexdigest, "\n";
  ' "$1"
}

# ---- processes and ports ---------------------------------------------------------------------
vk_port_listener() { lsof -nP -t -iTCP:"$1" -sTCP:LISTEN 2>/dev/null | head -1 || true; }
vk_port_busy() { [ -n "$(vk_port_listener "$1")" ]; }
# Start a command in its own process group so cleanup can stop exactly what this run started.
vk_spawn_group() {   # <pidfile> <logfile> <command...>
  local pidfile="$1" logfile="$2"
  shift 2
  nohup perl -e 'setpgrp(0,0); exec @ARGV' "$@" > "$logfile" 2>&1 < /dev/null &
  printf '%s\n' "$!" > "$pidfile"
}
vk_group_alive() {   # <pidfile>
  local g
  g="$(cat "$1" 2>/dev/null || true)"
  [ -n "$g" ] && { kill -0 "$g" 2>/dev/null || kill -0 -- "-$g" 2>/dev/null; }
}
vk_listener_in_group() {   # <port> <pidfile>
  local l g
  l="$(vk_port_listener "$1")"
  g="$(cat "$2" 2>/dev/null || true)"
  [ -n "$l" ] && [ -n "$g" ] && [ "$(ps -o pgid= -p "$l" | tr -d ' ')" = "$g" ]
}
vk_stop_group() {   # <pidfile>
  local g i=0
  g="$(cat "$1" 2>/dev/null || true)"
  [ -n "$g" ] || return 0
  kill -TERM -- "-$g" 2>/dev/null || kill -TERM "$g" 2>/dev/null || true
  while vk_group_alive "$1" && [ "$i" -lt 20 ]; do sleep 0.25; i=$((i + 1)); done
  if vk_group_alive "$1"; then kill -KILL -- "-$g" 2>/dev/null || true; fi
}
# Poll a command once a second until it succeeds or the timeout passes.
vk_wait_for() {   # <seconds> <command...>
  local limit="$1" i=0
  shift
  while [ "$i" -lt "$limit" ]; do
    if "$@" >/dev/null 2>&1; then return 0; fi
    sleep 1; i=$((i + 1))
  done
  return 1
}

# Like vk_wait_for, but give up at once if the process group in <pidfile> has exited.
vk_wait_for_alive() {   # <pidfile> <seconds> <command...>
  local pidfile="$1" limit="$2" i=0
  shift 2
  while [ "$i" -lt "$limit" ]; do
    if "$@" >/dev/null 2>&1; then return 0; fi
    vk_group_alive "$pidfile" || return 2
    sleep 1; i=$((i + 1))
  done
  return 1
}

# ---- the verify cycle ------------------------------------------------------------------------
# Claims live outside project scratch state, which cleanup hooks may remove.
vk_claim_run() {
  VK_OWNER_DIR="$VK_BASE_DIR/.verify-kit-owners/$VK_RUN_ID"
  mkdir -p "$VK_BASE_DIR/.verify-kit-owners" "$VK_EVIDENCE_ROOT" 2>/dev/null || { vk_fail "cannot write $VK_BASE_DIR or $VK_EVIDENCE_ROOT"; return 1; }
  if ! mkdir "$VK_OWNER_DIR" 2>/dev/null; then
    vk_fail "run $VK_RUN_ID is already owned; cleanup that run before reuse"
    return 1
  fi
  if [ -e "$VK_BASE_DIR/$VK_RUN_ID" ] || [ -L "$VK_BASE_DIR/$VK_RUN_ID" ] || [ -e "$EVIDENCE" ] || [ -L "$EVIDENCE" ]; then
    rmdir "$VK_OWNER_DIR"
    vk_fail "run $VK_RUN_ID already has state or evidence; use a new run id"
    return 1
  fi
}
vk_release_run() { rmdir "$VK_BASE_DIR/.verify-kit-owners/$VK_RUN_ID" 2>/dev/null || true; }
vk_capture_source() {
  VK_SOURCE_REVISION="$(git -C "$VK_ROOT" rev-parse HEAD 2>/dev/null || printf 'not-a-git-checkout')"
  VK_SOURCE_DIGEST=unavailable
  if git -C "$VK_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    VK_SOURCE_DIGEST="$(
      set -o pipefail
      trap - EXIT
      local source_root source_temporary_base source_temporary
      source_root="$(cd "$VK_ROOT" && pwd -P)" || exit 1
      source_temporary_base="$(cd "${TMPDIR:-/tmp}" && pwd -P)" || exit 1
      if [[ "$source_temporary_base/" = "${source_root%/}/"* ]]; then
        vk_err "source capture requires TMPDIR outside the source repository"; exit 1
      fi
      source_temporary="$(mktemp -d "$source_temporary_base/verify-kit-source.XXXXXXXX")" || exit 1
      trap 'rm -rf "$source_temporary"' EXIT
      {
        git -C "$VK_ROOT" diff --binary HEAD 2>"$source_temporary/git.stderr" || {
          cat "$source_temporary/git.stderr" >&2; exit 1;
        }
        if [ -s "$source_temporary/git.stderr" ]; then
          vk_err "cannot capture source: git diff reported diagnostics"
          cat "$source_temporary/git.stderr" >&2; exit 1
        fi
        git -C "$VK_ROOT" ls-files --others --exclude-standard -z >"$source_temporary/paths" 2>"$source_temporary/git.stderr" || {
          cat "$source_temporary/git.stderr" >&2; exit 1;
        }
        if [ -s "$source_temporary/git.stderr" ]; then
          vk_err "cannot capture source: git ls-files reported diagnostics"
          cat "$source_temporary/git.stderr" >&2; exit 1
        fi
        local path
        while IFS= read -r -d '' path; do
          printf '%s\0' "$path"
          if [ -L "$VK_ROOT/$path" ]; then readlink "$VK_ROOT/$path" || exit 1
          elif [ -f "$VK_ROOT/$path" ]; then LC_ALL=C shasum -a 256 "$VK_ROOT/$path" || exit 1
          else vk_err "cannot capture source file: $path"; exit 1
          fi
        done < "$source_temporary/paths"
      } | LC_ALL=C shasum -a 256 | awk '{print $1}'
    )" || { VK_SOURCE_DIGEST=unavailable; return 1; }
  fi
}
vk_write_result() {   # <result> <exit code>
  [ -d "${EVIDENCE:-}" ] || return 0
  # The browser scope is requested scope. Project drivers own completed-feature proof.
  perl -MJSON::PP -e '
    my ($file, $version, $app, $run, $revision, $digest, $browsers, $result, $exit, $cleanup) = @ARGV;
    open my $out, ">", $file or die "write result: $!";
    print {$out} JSON::PP->new->canonical->pretty->encode({
      schemaVersion => 1, kitVersion => $version, app => $app, runId => $run,
      revision => $revision, sourceDigest => $digest, requestedBrowsers => $browsers,
      result => $result, exitCode => 0 + $exit, cleanup => $cleanup,
      completedFeatures => undef,
      featureEvidence => "See project driver artifacts for completed actions and browser versions"
    });
    close $out or die "close result: $!";
  ' "$EVIDENCE/run-result.json" "$VK_KIT_VERSION" "$VK_APP" "$VK_RUN_ID" \
    "${VK_SOURCE_REVISION:-unavailable}" "${VK_SOURCE_DIGEST:-unavailable}" \
    "${VK_REQUESTED_BROWSERS:-not-applicable}" "$1" "$2" "$VK_CLEANUP_RESULT"
}
vk_cleanup_owned() {
  # Keep project cleanup output visible and retain the claim on a failed hook.
  local rc=0 restore_errexit=0
  case $- in *e*) restore_errexit=1 ;; esac
  VK_CLEANUP_ATTEMPTED=1
  set +e
  ( set -e; trap - EXIT; cmd_cleanup )
  rc=$?
  if [ "$restore_errexit" -eq 1 ]; then set -e; fi
  if [ "$rc" -ne 0 ]; then
    VK_CLEANUP_RESULT=failed
    vk_err "cleanup failed run=$VK_RUN_ID exit=$rc; retry --execute cleanup with VERIFY_RUN_ID=$VK_RUN_ID"
    return "$rc"
  fi
  VK_CLEANUP_RESULT=passed
  vk_release_run
}
vk_on_verify_exit() {
  local rc=$?
  trap - EXIT
  if [ "$VK_VERIFY_ACTIVE" -eq 1 ] && [ "$rc" -eq 0 ]; then rc=1; fi
  if [ "$VK_CLEANUP_ATTEMPTED" -eq 0 ]; then
    set +e
    vk_cleanup_owned
  fi
  vk_write_result FAIL "$rc" || vk_err "could not retain run-result.json"
  vk_say "VERIFY FAIL run=$VK_RUN_ID exit=$rc evidence=${EVIDENCE:-unknown}" >&2
  exit "$rc"
}
vk_run_verify() {
  vk_claim_run
  VK_VERIFY_ACTIVE=1
  trap vk_on_verify_exit EXIT
  vk_capture_source
  cmd_launch
  vk_write_result RUNNING 0
  cmd_doctor
  vk_verify_recipes
  local artifact
  local artifacts=()
  [ -d "$EVIDENCE" ] || { vk_fail "missing evidence directory $EVIDENCE"; return 1; }
  # The default evidence root can contain the hook's scratch STATE directory.
  # Inventory proof files while allowing cleanup to remove that scratch subtree.
  while IFS= read -r -d '' artifact; do artifacts[${#artifacts[@]}]="$artifact"; done < <(
    if [ -n "${STATE:-}" ] && [ "$STATE" != "$EVIDENCE" ]; then
      find "$EVIDENCE" -path "$STATE" -prune -o -type f -print0
    else
      find "$EVIDENCE" -type f -print0
    fi
  )
  vk_cleanup_owned
  for artifact in "${artifacts[@]+"${artifacts[@]}"}"; do
    [ -f "$artifact" ] || { vk_fail "evidence removed by cleanup: $artifact"; return 1; }
  done
  [ -d "$EVIDENCE" ] || { vk_fail "evidence removed by cleanup: $EVIDENCE"; return 1; }
  vk_write_result PASS 0
  VK_VERIFY_ACTIVE=0
  trap - EXIT
  vk_say "VERIFY PASS run=$VK_RUN_ID evidence=$EVIDENCE"
}

# ---- entry point -----------------------------------------------------------------------------
vk_main() {
  VK_DRY_RUN=0
  VK_EXECUTE=0
  VK_CMD=""
  while [ $# -gt 0 ]; do
    case "$1" in
      -h|--help) VK_CMD=""; vk_resolve; vk_usage; return 0 ;;
      --dry-run) VK_DRY_RUN=1; shift ;;
      --execute) VK_EXECUTE=1; shift ;;
      --list-commands) vk_sample_commands; return 0 ;;
      --list-browsers) if [ "${VK_BROWSER_SKILL:-0}" = 1 ]; then vk_browsers; fi; return ;;
      --) shift; break ;;
      -*) vk_err "unknown option $1"; return 2 ;;
      *) break ;;
    esac
  done
  VK_CMD="${1:-}"
  if [ $# -gt 0 ]; then shift; fi
  vk_resolve
  if [ "${VK_BROWSER_SKILL:-0}" = 1 ]; then
    if VK_REQUESTED_BROWSERS="$(vk_browsers)"; then :; else return $?; fi
  fi
  vk_paths

  if [ "$VK_EXECUTE" -ne 1 ] || [ "$VK_DRY_RUN" -eq 1 ]; then
    if [ "$VK_DRY_RUN" -ne 1 ]; then vk_usage; echo; fi
    if [ -z "$VK_CMD" ]; then
      vk_plan_line "would run one of the commands above (run=$VK_RUN_ID)"
      return 0
    fi
    if [ "$VK_CMD" = verify ] && [ $# -gt 0 ]; then vk_err "verify takes no arguments"; return 2; fi
    # Call vk_plan as a plain command: errexit is suspended inside functions run from `||` or
    # `if`, so a skill's argument check (return 2 from a helper) must abort the plan right here.
    vk_plan "$VK_CMD" ${@+"$@"}
    return 0
  fi

  case "$VK_CMD" in
    "") vk_err "--execute needs a command"; return 2 ;;
    verify)
      if [ $# -gt 0 ]; then vk_err "verify takes no arguments"; return 2; fi
      vk_run_verify
      ;;
    launch)
      vk_claim_run
      VK_VERIFY_ACTIVE=1
      trap vk_on_verify_exit EXIT
      vk_dispatch "$VK_CMD" ${@+"$@"}
      VK_VERIFY_ACTIVE=0
      trap - EXIT
      ;;
    cleanup)
      vk_dispatch "$VK_CMD" ${@+"$@"}
      vk_release_run
      ;;
    *)
      vk_dispatch "$VK_CMD" ${@+"$@"}
      ;;
  esac
}
