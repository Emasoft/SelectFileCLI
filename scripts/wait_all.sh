#!/usr/bin/env bash
# wait_all.sh — Execute a command, wait for every descendant, with optional
#               timeout, retries, JSON/log output, and configurable kill signal.
#
# -------------------------------------------------------------------------
# USAGE
#   ./wait_all.sh [OPTIONS] -- <command and args…>
#
#   (Legacy single-string form, still supported)
#   ./wait_all.sh [OPTIONS] "<command>"
#
# OPTIONS
#   --verbose                Emit internal progress messages to stderr
#   --log <file>             Append per-try stdout, stderr & exit status to <file>
#   --json                   Print a JSON object instead of raw stdout/stderr
#                            (uses jq if available, otherwise base64-encodes)
#   --timeout <sec>          Abort after SEC seconds (0 ⇒ no timeout)
#   --kill-signal <sig>      Signal sent on timeout (default SIGTERM)
#   --retry <N>              Retry up to N additional times after non-zero exit
#                            or timeout (0 ⇒ no retries)
#   --help                   Show this help text and exit 0
#
# EXIT CODES
#   0    Success (from last attempt)
#   1    Bad usage / option error
#   124  Command killed by timeout (same as GNU timeout(1))
#   *    Any other code is the wrapped command's exit status
#
# NOTES
#   • The command is started in its own **process group**; on timeout we send the
#     chosen signal to the whole group so every descendant is terminated.
#   • On macOS the system Bash (3.2) lacks some modern features; using Homebrew
#     Bash ≥ 5 is recommended. The shebang (`/usr/bin/env bash`) will pick it up
#     automatically if it's first in your PATH.
#
# -------------------------------------------------------------------------
# EXAMPLES
#
# 🔹 Basic usage:
#     ./wait_all.sh -- echo echo hello
#
# 🔹 Verbose mode:
#     ./wait_all.sh --verbose -- bash -c 'sleep 1 & sleep 2 & wait'
#
# 🔹 Logging output:
#     ./wait_all.sh --log out.log -- python3 -c 'print(42)'
#
# 🔹 JSON output:
#     ./wait_all.sh --json -- bash -c 'echo out; echo err >&2; exit 3'
#
# 🔹 Kill if it takes too long:
#     ./wait_all.sh --timeout 5 -- sleep 10
#
# 🔹 Use SIGKILL instead of SIGTERM on timeout:
#     ./wait_all.sh --timeout 5 --kill-signal SIGKILL -- sleep 10
#
# 🔹 Retry command up to 3 times:
#     ./wait_all.sh --retry 3 -- bash -c 'echo fail; exit 1'
#
# 🔹 Retry on timeout:
#     ./wait_all.sh --timeout 2 --retry 2 -- sleep 5
#
# 🔹 Combine all features:
#     ./wait_all.sh --timeout 3 --kill-signal SIGKILL --retry 2 \
#                   --verbose --log out.log --json -- \
#                   bash -c 'sleep 5; echo done'
#
# 🔹 Capture output into a variable:
#     result=$(./wait_all.sh -- echo foo)
#     echo "Got: $result"
#
# -------------------------------------------------------------------------

# ─────────────────────────── Strict-mode & traps ──────────────────────────
set -Eeuo pipefail                        # abort on error, unset var, or pipe fail

die()   { printf 'wait_all: %s\n' "$*" >&2; exit 1; }

# Print header up to the first totally blank line *after* EXAMPLES divider
usage() {
  awk '/^# EXAMPLES/{ex=1} ex && /^# *$/{exit} ex' "$0"
}

# List of temporary files created with mktemp; cleaned on any exit
TEMP_FILES=()
cleanup() { rm -f -- "${TEMP_FILES[@]:-}"; }
trap cleanup EXIT
trap 'die "unexpected error on line $LINENO"' ERR

# ───────────────────────── Helpers: validation ────────────────────────────
is_integer() { [[ $1 =~ ^[0-9]+$ ]]; }

is_valid_signal() {
  local sig=$1
  # numeric? → accept if integer
  if [[ $sig =~ ^[0-9]+$ ]]; then
    return 0
  fi
  # name? → check against kill -l output (portable across BSD & GNU)
  kill -l | tr ' ' '\n' | grep -qiE "^${sig}$"
}

# ───────────────────────── Default option values ──────────────────────────
VERBOSE=0
JSON=0
LOG_FILE=""
TIMEOUT=0
KILL_SIGNAL="SIGTERM"
RETRY_MAX=0
CMD=()                           # array; preserves spaces for modern form
LEGACY_CMD_STRING=""             # non-empty only for the old single-string form

# ───────────────────────────── Option parsing ─────────────────────────────
while (( $# )); do
  case $1 in
    --verbose) VERBOSE=1 ;;
    --json)    JSON=1 ;;
    --log)
        shift || die "--log needs a filename"
        LOG_FILE=$1 ;;
    --timeout)
        shift || die "--timeout needs a value"
        is_integer "$1" || die "--timeout must be a non-negative integer"
        TIMEOUT=$1 ;;
    --kill-signal)
        shift || die "--kill-signal needs a value"
        is_valid_signal "$1" || die "unknown signal: $1"
        KILL_SIGNAL=$1 ;;
    --retry)
        shift || die "--retry needs a value"
        is_integer "$1" || die "--retry must be a non-negative integer"
        RETRY_MAX=$1 ;;
    --help)    usage; exit 0 ;;
    --)        shift; CMD=("$@"); break ;;   # modern form: everything after -- is cmd
    --*)       die "unknown option: $1" ;;
    *)         # legacy single-string form (maintained for backward compatibility)
               LEGACY_CMD_STRING=$1; break ;;
  esac
  shift
done

if [[ -z $LEGACY_CMD_STRING && ${#CMD[@]} -eq 0 ]]; then
  die "no command specified.  see --help"
fi

(( VERBOSE )) && {
  if [[ -n $LEGACY_CMD_STRING ]]; then
    printf '[wait_all] Legacy command string: %s\n' "$LEGACY_CMD_STRING" >&2
  else
    printf '[wait_all] Command array: %q\n' "${CMD[@]}" >&2
  fi
}

# ─────────────────────── JSON/encoding helper function ────────────────────
json_encode() {
  local out=$1 err=$2 code=$3
  if command -v jq >/dev/null 2>&1; then
    jq -n --arg out "$out" --arg err "$err" --argjson code "$code" \
       '{stdout:$out, stderr:$err, exit_code:$code}'
  else
    printf '{"stdout_b64":"%s","stderr_b64":"%s","exit_code":%d}\n' \
           "$(printf %s "$out" | base64)" \
           "$(printf %s "$err" | base64)" \
           "$code"
    echo "# (stdout/stderr were base64-encoded because jq is absent)" >&2
  fi
}

# ────────────────── Function: run the command once (one try) ──────────────
run_once() {
  local attempt=$1
  local tmp_out tmp_err
  tmp_out=$(mktemp) && TEMP_FILES+=("$tmp_out")
  tmp_err=$(mktemp) && TEMP_FILES+=("$tmp_err")

  (( VERBOSE )) && echo "[wait_all] Try #$attempt → launching…" >&2

  # Start the command in a new session (setsid) so it gets its own PGID
  # On macOS, setsid may not be available, so we fall back to direct execution
  if command -v setsid >/dev/null 2>&1; then
    if [[ -n $LEGACY_CMD_STRING ]]; then
      setsid bash -c "$LEGACY_CMD_STRING" >"$tmp_out" 2>"$tmp_err" &
    else
      setsid "${CMD[@]}" >"$tmp_out" 2>"$tmp_err" &
    fi
  else
    # Fallback for systems without setsid (e.g., macOS)
    if [[ -n $LEGACY_CMD_STRING ]]; then
      bash -c "$LEGACY_CMD_STRING" >"$tmp_out" 2>"$tmp_err" &
    else
      "${CMD[@]}" >"$tmp_out" 2>"$tmp_err" &
    fi
  fi
  local main_pid=$!
  local pgid
  # Give the process a moment to establish its process group
  sleep 0.1
  pgid=$(ps -o pgid= "$main_pid" 2>/dev/null | tr -d ' ' || echo "$main_pid")

  local timed_out=0 exit_code=0
  local start_ns deadline_ns now_ns

  if (( TIMEOUT > 0 )); then
    start_ns=$(date +%s%N)
    (( deadline_ns = start_ns + TIMEOUT*1000000000 ))
  fi

  # ---- monitor main process until it ends or we hit the deadline ----
  while kill -0 "$main_pid" 2>/dev/null; do
    sleep 0.1
    if (( TIMEOUT > 0 )); then
      now_ns=$(date +%s%N)
      if (( now_ns >= deadline_ns )); then
        (( VERBOSE )) && \
          echo "[wait_all] Timeout ${TIMEOUT}s → ${KILL_SIGNAL} PGID $pgid" >&2
        kill "-$KILL_SIGNAL" "-$pgid" 2>/dev/null || true
        timed_out=1
        break
      fi
    fi
  done

  wait "$main_pid" 2>/dev/null || true    # collect exit status quietly

  # spin until every process in the group is gone
  while pgrep -g "$pgid" >/dev/null 2>&1; do sleep 0.05; done

  if (( timed_out )); then
    exit_code=124
  else
    exit_code=$?
  fi

  local stdout stderr
  stdout=$(<"$tmp_out")
  stderr=$(<"$tmp_err")

  # ------------ optional log file -----------------------------------------
  if [[ -n $LOG_FILE ]]; then
    {
      echo "=== TRY #$attempt ==="
      echo "CMD : ${LEGACY_CMD_STRING:-${CMD[*]}}"
      echo "STDOUT:"
      printf '%s\n' "$stdout"
      echo "STDERR:"
      printf '%s\n' "$stderr"
      echo "EXIT : $exit_code"
      (( timed_out )) && echo "TIMEOUT after ${TIMEOUT}s"
      echo
    } >>"$LOG_FILE"
  fi

  # ------------- user-visible output --------------------------------------
  if (( JSON )); then
    json_encode "$stdout" "$stderr" "$exit_code"
  else
    printf '%s' "$stdout"
    [[ -n $stderr ]] && printf '%s' "$stderr" >&2
  fi

  (( VERBOSE )) && \
    echo "[wait_all] Try #$attempt finished with exit $exit_code" >&2
  (( timed_out )) && echo "[wait_all]   (timeout)" >&2

  return "$exit_code"
}

# ───────────────────────── Retry orchestration loop ───────────────────────
for (( attempt=1; ; ++attempt )); do
  run_once "$attempt"
  status=$?
  if (( status == 0 )); then exit 0; fi
  if (( attempt > RETRY_MAX )); then
    (( VERBOSE )) && echo "[wait_all] No retries left; exiting $status" >&2
    exit "$status"
  fi
  (( VERBOSE )) && \
    echo "[wait_all] attempt $attempt failed (exit $status) —" \
         "retrying $(( RETRY_MAX - attempt + 1 )) more time(s)…" >&2
done
