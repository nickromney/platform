# Shell Entrypoint Standards

Executable tracked `*.sh` scripts in this repo should expose the same baseline
CLI safety contract.

## Required flags

- `-h`, `--help` prints usage and exits `0`.
- `--dry-run` prints a summary and exits `0` before side effects.
- `--execute` is accepted across executable entrypoints. For read-only, test,
  or query scripts it is the preferred explicit opt-in form for real execution.
  Bare invocation remains supported during the compatibility window, but
  callers and docs should prefer the explicit flag.

## Interface rules

- Use long `--...` flags for public inputs.
- Keep existing positional forms as compatibility shims until repo callers and
  docs have been migrated.
- Makefiles and script-to-script callers should pass `--execute` or
  `--dry-run` explicitly rather than relying on bare invocation.
- Unknown flags should fail fast with a non-zero exit status.
- `--dry-run` should short-circuit before commands that mutate state or hit
  external systems.

## Bash pattern

Bash entrypoints can source
[`scripts/lib/shell-cli.sh`](../scripts/lib/shell-cli.sh) for shared error and
standard-flag handling.

Use `shell_cli_parse_standard_only usage "$@"` for no-argument scripts, then
check `SHELL_CLI_DRY_RUN` before the first side effect.

## POSIX `sh` pattern

POSIX `sh` entrypoints can source
[`scripts/lib/shell-cli-posix.sh`](../scripts/lib/shell-cli-posix.sh), or inline
a small parser that handles:

- `-h|--help`
- `--dry-run`
- `--execute`
- `--`

The parser should finish before any side effects, and `--dry-run` should print
an `INFO dry-run: ...` summary and exit `0`.
