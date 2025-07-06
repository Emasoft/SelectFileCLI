#!/usr/bin/env bash
# wait_all.sh — Execute a command, wait for every descendant, with timeout,
#               retries, JSON/log output, per-process memory tracking, and
#               *automatic runner selection*.
#
# -------------------------------------------------------------------------
# USAGE
#   ./wait_all.sh [OPTIONS] -- <…command and args…>
#
#   (Legacy single-string form, still supported)
#   ./wait_all.sh [OPTIONS] "<…command and args…>"
#
# DESCRIPTION
#  Executes the supplied command in a fresh process group and blocks until
#  *every* descendant terminates. It runs any executable. While running it:
#    • Samples per-PID peak RSS and system-wide memory usage.
#    • Optionally enforces a wall-clock timeout.
#    • Optionally retries the command if it exits non-zero or times out.
#    • Writes a fully timestamped log; can also emit a single JSON blob.
#    • Transparently “upgrades” plain invocations to faster launchers
#      (uv run, uv pip, pnpm run, etc.) when available.
#    • Installs the small helper utilities it relies on with --install-deps.
#
# OPTIONS
#  --verbose
#        Emit progress messages (prefixed with the script name) to stderr.
#
#  --log <file>
#        Write the detailed run log to <file>.  Defaults to
#        ./logs/wait_all_<UTC-timestamp>.log (directory auto-created).
#
#  --json
#        Print a structured JSON object instead of raw stdout/stderr.  If
#        jq(1) is available the JSON contains plain UTF-8 text; otherwise the
#        two streams are base64-encoded (portable).
#
#  --timeout <sec>
#        Kill the whole process group if it runs longer than <sec> seconds.
#        0 disables the timeout entirely (default).
#
#  --kill-signal <sig>
#        Signal delivered when the timeout triggers.  May be a number (9),
#        plain name (KILL) or "SIGKILL".  Default: SIGTERM.
#
#  --retry <N>
#        Retry the command up to N additional times after non-zero exit or a
#        timeout.  A successful run stops the loop immediately.
#
#  --install-deps
#        Attempt to install any missing helper programs using the native
#        package manager (Homebrew, apt, apk, pkg).  Requires sudo on Linux.
#
#  --help
#        Print this help and exit 0.
#
# EXIT CODES
#   0    Success (from last attempt)
#   1    Bad usage / option error
#   124  Command killed by timeout (same as GNU timeout(1))
#   *    Any other code is the wrapped command’s exit status
#
# RELEASE NOTES
#   • A detailed, timestamped log is always written (see --log).  It includes
#     stdout, stderr, exit status, and per-PID *peak* RSS plus system-wide
#     memory utilisation at each peak.
#   • The wrapped command runs in its own **process group**; on timeout the
#     configured signal is delivered to the whole tree so every descendant
#     dies.  If `setsid` is unavailable, the script falls back gracefully.
#   • Portable to Bash ≥ 3.2 (macOS default); *no* namerefs, associative
#     arrays, or GNU-only extensions are used.  Sub-second sleeps work even
#     on BusyBox/dash via a tiny Perl fallback.
#   • v3.1 (2025-07-05): NUL-safe temp-file exchange, robust BusyBox/macOS
#     signal & ps handling, divide-by-zero guard in sys_mem(), safer legacy
#     parsing, stricter error-handling (`set -e` re-enabled), removed `setsid`
#     from auto-install list, and other hardening tweaks.  Help & examples
#     updated accordingly.
#
# -------------------------------------------------------------------------
#
# EXAMPLES
#
# 🔹 Classic
#     ./wait_all.sh -- echo "hello world"
#
# 🔹 Verbose mode
#     ./wait_all.sh --verbose -- bash -c 'sleep 1 & sleep 2 & wait'
#
# 🔹 Logging output (custom path)
#     ./wait_all.sh --log /tmp/run.log -- python3 -c 'print(42)'
#
# 🔹 JSON output
#     ./wait_all.sh --json -- bash -c 'echo out ; echo err >&2 ; exit 3'
#
# 🔹 Kill if it takes too long
#     ./wait_all.sh --timeout 5 -- sleep 10
#
# 🔹 Use SIGKILL instead of SIGTERM on timeout
#     ./wait_all.sh --timeout 5 --kill-signal SIGKILL -- sleep 10
#
# 🔹 Retry command up to 3 times
#     ./wait_all.sh --retry 3 -- bash -c 'echo fail ; exit 1'
#
# 🔹 Retry on timeout
#     ./wait_all.sh --timeout 2 --retry 2 -- sleep 5
#
# 🔹 Combine everything
#     ./wait_all.sh --timeout 3 --kill-signal SIGKILL --retry 2 \
#                   --verbose --log out.log --json -- \
#                   bash -c 'sleep 5 ; echo done'
#
# 🔹 Capture output into a variable
#     result=$(./wait_all.sh -- echo foo)
#     echo "Got: $result"
#
# ----------  Automatic runner examples -----------------------------------
#
#   ./wait_all.sh -- foo.py 1 2                  # → uv run foo.py 1 2
#   ./wait_all.sh -- python script.py -x         # → uv run script.py -x
#   ./wait_all.sh -- python -m pip install rich  # → uv pip install rich
#   ./wait_all.sh -- bash build.sh --fast        # → uv run build.sh --fast
#   ./wait_all.sh -- cleanup.sh                  # → uv run cleanup.sh
#   ./wait_all.sh -- pip install numpy           # → uv pip install numpy
#   ./wait_all.sh -- npm run lint                # → pnpm run lint
#   ./wait_all.sh -- build                       # → pnpm run build
#
# ----------  Dependency-installer example --------------------------------
#
#   ./wait_all.sh --install-deps --verbose -- jq --version
#
# -------------------------------------------------------------------------

VERSION='3.1'

# ───────────────────────── Strict-mode & traps ───────────────────────────
set -Eeuo pipefail

SCRIPT_NAME=${0##*/}
printf '\n%s v%s\n' "$SCRIPT_NAME" "$VERSION" >&2

# ──────────────────────────── Help screen ────────────────────────────────
usage() {
  cat <<'EOF'
A portable “run-and-really-wait” wrapper
======================================================

 USAGE
   ./wait_all.sh [OPTIONS] -- <…command and args…>

   (Legacy single-string form, still supported)
   ./wait_all.sh [OPTIONS] "<…command and args…>"

DESCRIPTION
  Executes the supplied command in a fresh process group and blocks until
  *every* descendant terminates.  While running it:
    • Samples per-PID peak RSS and system-wide memory usage.
    • Optionally enforces a wall-clock timeout.
    • Optionally retries the command if it exits non-zero or times out.
    • Writes a fully timestamped log; can also emit a single JSON blob.
    • Transparently “upgrades” plain invocations to faster launchers
      (uv run, uv pip, pnpm run, etc.) when available.
    • Installs the small helper utilities it relies on with --install-deps.

OPTIONS
  --verbose
        Emit progress messages (prefixed with the script name) to stderr.

  --log <file>
        Write the detailed run log to <file>.  Defaults to
        ./logs/wait_all_<UTC-timestamp>.log (directory auto-created).

  --json
        Print a structured JSON object instead of raw stdout/stderr.  If
        jq(1) is available the JSON contains plain UTF-8 text; otherwise the
        two streams are base64-encoded (portable).

  --timeout <sec>
        Kill the whole process group if it runs longer than <sec> seconds.
        0 disables the timeout entirely (default).

  --kill-signal <sig>
        Signal delivered when the timeout triggers.  May be a number (9),
        plain name (KILL) or “SIGKILL”.  Default: SIGTERM.

  --retry <N>
        Retry the command up to N additional times after non-zero exit or a
        timeout.  A successful run stops the loop immediately.

  --install-deps
        Attempt to install any missing helper programs using the native
        package manager (Homebrew, apt, apk, pkg).  Requires sudo on Linux.

  --help
        Print this help and exit 0.

EXIT STATUS
  0      Wrapped command eventually succeeded.
  1      Bad usage or option error.
  124    Command was killed because it exceeded --timeout.
  other  The wrapped command’s exit status (last attempt).

ENVIRONMENT
  TMPDIR     Used for internal temp-files (mktemp).  Paths *may* contain
             spaces thanks to NUL-separated hand-over.
  VIRTUAL_ENV / CONDA_PREFIX
             Presence enables uv-based auto-runner substitutions.

FILES
  ./logs/wait_all_<timestamp>.log (default log path).

SEE ALSO
  timeout(1), jq(1), uv(1), pnpm(1), setsid(2), kill(1).


 --------------------------  USAGE EXAMPLES  -----------------------------

 🔹 Classic
     ./wait_all.sh -- my_executable

 🔹 Verbose mode
     ./wait_all.sh --verbose -- bash -c 'sleep 1 & sleep 2 & wait'

 🔹 Logging output (custom path)
     ./wait_all.sh --log /tmp/run.log -- python3 -c 'print(42)'

 🔹 JSON output
     ./wait_all.sh --json -- bash -c 'echo out ; echo err >&2 ; exit 3'

 🔹 Kill if it takes too long
     ./wait_all.sh --timeout 5 -- sleep 10

 🔹 Use SIGKILL instead of SIGTERM on timeout
     ./wait_all.sh --timeout 5 --kill-signal SIGKILL -- sleep 10

 🔹 Retry command up to 3 times
     ./wait_all.sh --retry 3 -- bash -c 'echo fail ; exit 1'

 🔹 Retry on timeout
     ./wait_all.sh --timeout 2 --retry 2 -- sleep 5

 🔹 Combine everything
     ./wait_all.sh --timeout 3 --kill-signal SIGKILL --retry 2 \
                   --verbose --log out.log --json -- \
                   bash -c 'sleep 5 ; echo done'

 🔹 Capture output into a variable
     result=$(./wait_all.sh -- echo foo)
     echo "Got: $result"

 ----------  Automatic runner examples -----------------------------------

   ./wait_all.sh -- foo.py 1 2                  # → uv run foo.py 1 2
   ./wait_all.sh -- python script.py -x         # → uv run script.py -x
   ./wait_all.sh -- python -m pip install rich  # → uv pip install rich
   ./wait_all.sh -- bash build.sh --fast        # → uv run build.sh --fast
   ./wait_all.sh -- cleanup.sh                  # → uv run cleanup.sh
   ./wait_all.sh -- pip install numpy           # → uv pip install numpy
   ./wait_all.sh -- npm run lint                # → pnpm run lint
   ./wait_all.sh -- build                       # → pnpm run build

 ----------  Dependency-installer example --------------------------------

   ./wait_all.sh --install-deps --verbose -- jq --version

 -------------------------------------------------------------------------

EOF
}

# ──────────────────────── Error & exit helpers ───────────────────────────
die() {
  # Log the fatal error
  if [[ -n "${LOG_FILE:-}" ]]; then
    {
      echo "=== FATAL ERROR ==="
      echo "Time: $(date -u +"%F %T UTC")"
      echo "Message: $*"
      echo "Active PIDs: ${SPAWNED_PIDS[*]:-none}"
      echo "Active PGIDs: ${SPAWNED_PGIDS[*]:-none}"
      echo "================================================================"
    } >>"$LOG_FILE" 2>&1 || true
  fi

  printf '%s: %s\n' "$SCRIPT_NAME" "$*" >&2
  printf "execute '%s --help' for more details.\n" "$SCRIPT_NAME" >&2

  # ALWAYS cleanup before exit
  cleanup
  exit 1
}

# Show help when run with no arguments
(( $# == 0 )) && { usage; exit 0; }

# Print header until first blank line after “EXAMPLES” (used nowhere now but
# kept to avoid touching the remainder of the script logic)
short_usage() {
  awk '
    /^# EXAMPLES/ { ex=1; next }
    ex && /^#[[:space:]]*$/ { exit }
    ex
  ' "$0"
}

# Global tracking for comprehensive cleanup
TEMP_FILES=()
SPAWNED_PIDS=()
SPAWNED_PGIDS=()
CLEANUP_IN_PROGRESS=0

# Store our own PID and parent PID to avoid killing them
WAIT_ALL_PID=$$
WAIT_ALL_PPID=$PPID
# Get our process group ID safely
if WAIT_ALL_PGID=$(ps -p $$ -o pgid= 2>/dev/null); then
  WAIT_ALL_PGID=$(echo "$WAIT_ALL_PGID" | tr -d '[:space:],<')
else
  WAIT_ALL_PGID=0
fi

# Comprehensive cleanup that ALWAYS kills all spawned processes
cleanup() {
  # Prevent recursive cleanup
  if (( CLEANUP_IN_PROGRESS )); then
    return 0
  fi
  CLEANUP_IN_PROGRESS=1

  local exit_code=$?

  # Log cleanup start
  if [[ -n "${LOG_FILE:-}" ]]; then
    echo "=== CLEANUP STARTED at $(date -u +"%F %T UTC") ===" >>"$LOG_FILE" 2>&1 || true
  fi

  # First, try to kill all process groups we created
  local pgid
  for pgid in "${SPAWNED_PGIDS[@]:-}"; do
    if [[ -n "$pgid" ]] && [[ "$pgid" -gt 0 ]]; then
      # Skip our own process group and parent's process group
      if [[ "$pgid" == "$WAIT_ALL_PGID" ]]; then
        continue
      fi
      # Log what we're killing
      if [[ -n "${LOG_FILE:-}" ]]; then
        echo "Killing process group $pgid" >>"$LOG_FILE" 2>&1 || true
        ps -g "$pgid" -o pid,ppid,comm >>"$LOG_FILE" 2>&1 || true
      fi
      # SIGTERM first
      kill -TERM -"$pgid" 2>/dev/null || true
    fi
  done

  # Give processes a moment to exit gracefully
  sleep 0.1

  # Force kill any remaining process groups
  for pgid in "${SPAWNED_PGIDS[@]:-}"; do
    if [[ -n "$pgid" ]] && [[ "$pgid" -gt 0 ]]; then
      # Skip our own process group and parent's process group
      if [[ "$pgid" == "$WAIT_ALL_PGID" ]]; then
        continue
      fi
      # Check if any processes still exist in this group
      if ps -g "$pgid" >/dev/null 2>&1; then
        if [[ -n "${LOG_FILE:-}" ]]; then
          echo "Force killing process group $pgid" >>"$LOG_FILE" 2>&1 || true
        fi
        kill -KILL -"$pgid" 2>/dev/null || true
      fi
    fi
  done

  # Now kill any individual PIDs that might have escaped
  local pid
  for pid in "${SPAWNED_PIDS[@]:-}"; do
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      # Skip our own PID and parent PID
      if [[ "$pid" == "$WAIT_ALL_PID" ]] || [[ "$pid" == "$WAIT_ALL_PPID" ]]; then
        continue
      fi
      if [[ -n "${LOG_FILE:-}" ]]; then
        echo "Killing individual process $pid" >>"$LOG_FILE" 2>&1 || true
      fi
      kill -TERM "$pid" 2>/dev/null || true
      sleep 0.05
      # Force kill if still alive
      if kill -0 "$pid" 2>/dev/null; then
        kill -KILL "$pid" 2>/dev/null || true
      fi
    fi
  done

  # Remove temp files
  rm -f -- "${TEMP_FILES[@]:-}" 2>/dev/null || true

  # Log cleanup completion
  if [[ -n "${LOG_FILE:-}" ]]; then
    echo "=== CLEANUP COMPLETED ===" >>"$LOG_FILE" 2>&1 || true
  fi

  return $exit_code
}

# Enhanced error handler
error_handler() {
  local line=$1
  local exit_code=$?

  # Disable traps to prevent recursion
  trap - ERR EXIT INT TERM

  # Log the error
  if [[ -n "${LOG_FILE:-}" ]]; then
    {
      echo "=== ERROR at line $line (exit code: $exit_code) ==="
      echo "Time: $(date -u +"%F %T UTC")"
      echo "Command: ${BASH_COMMAND:-unknown}"
      echo "Active PIDs: ${SPAWNED_PIDS[*]:-none}"
      echo "Active PGIDs: ${SPAWNED_PGIDS[*]:-none}"
      echo "================================================================"
    } >>"$LOG_FILE" 2>&1 || true
  fi

  # Print to stderr
  printf '%s: ERROR at line %d (exit code: %d)\n' "$SCRIPT_NAME" "$line" "$exit_code" >&2

  # ALWAYS cleanup before exit
  cleanup

  # Force exit
  exit "$exit_code"
}

# Set up signal handlers to ensure cleanup
# Ensure cleanup preserves exit code
trap 'EC=$?; cleanup; exit $EC' EXIT
trap 'error_handler $LINENO' ERR
trap 'echo "Interrupted!" >&2; cleanup; exit 130' INT
trap 'echo "Terminated!" >&2; cleanup; exit 143' TERM

# ───────────────────────── Helpers: validation ───────────────────────────
have()            { command -v "$1" >/dev/null 2>&1; }
is_integer()      { [[ ${1:-x} =~ ^[0-9]+$ ]]; }

# Find all descendant processes of a given PID
find_descendants() {
  local parent_pid=$1
  local found_pids=()

  # Get direct children
  local children
  if [[ $(uname) == "Darwin" ]]; then
    # macOS: use ps with ppid
    children=$(ps -o pid= -o ppid= | awk -v ppid="$parent_pid" '$2 == ppid {print $1}' 2>/dev/null || true)
  else
    # Linux: use ps with ppid
    children=$(ps -o pid= --ppid "$parent_pid" 2>/dev/null || true)
  fi

  # Add children to found list
  local child
  for child in $children; do
    if [[ "$child" =~ ^[0-9]+$ ]]; then
      found_pids+=("$child")
      # Recursively find descendants of this child
      local grandchildren
      grandchildren=$(find_descendants "$child")
      if [[ -n "$grandchildren" ]]; then
        found_pids+=("$grandchildren")
      fi
    fi
  done

  # Return unique PIDs
  if (( ${#found_pids[@]} > 0 )); then
    printf '%s\n' "${found_pids[@]}" | sort -u | tr '\n' ' '
  fi
}

# Accepts numeric, TERM, or SIGTERM (case-insensitive, BSD/Linux/BusyBox)
is_valid_signal() {
  local sig=${1#SIG}
  if [[ $sig =~ ^[0-9]+$ ]]; then kill -l "$sig" >/dev/null 2>&1 && return 0; fi
  kill -l | tr ' ,\t' '\n\n\n' | grep -qiE "^${sig}$"
}

venv_active()     { [[ -n ${VIRTUAL_ENV:-} || -n ${CONDA_PREFIX:-} ]]; }
epoch_s()         { date +%s; }

# Portable short sleep: works even when /bin/sleep lacks fractional support
sleep_short() {
  local dur=$1
  if sleep "$dur" 2>/dev/null; then return; fi
  perl -e "select undef,undef,undef,$dur" 2>/dev/null || sleep 1
}

# ─── System-memory snapshot: “used_kB total_kB compressed_pages” ──────────
sys_mem() {
  if [[ -r /proc/meminfo ]]; then                 # Linux
    local total avail
    total=$(awk '/^MemTotal:/{print $2}' /proc/meminfo)
    avail=$(awk '/^MemAvailable:/{print $2}' /proc/meminfo)
    echo "$((total-avail)) $total 0"
  elif have vm_stat && have sysctl; then          # macOS / FreeBSD
    local page total_b free inactive spec comp
    page=$(sysctl -n hw.pagesize)
    : "${page:=4096}"                             # fallback if empty
    total_b=$(sysctl -n hw.memsize)
    free=$(vm_stat | awk '/Pages free/{print $3}' | tr -d '.')
    inactive=$(vm_stat | awk '/Pages inactive/{print $3}' | tr -d '.')
    spec=$(vm_stat | awk '/Pages speculative/{print $3}' | tr -d '.')
    comp=$(vm_stat | awk '/occupied by compressor/{print $5}' | tr -d '.')
    local used_b
    used_b=$(( total_b - (free+inactive+spec)*page ))
    echo "$((used_b/1024)) $((total_b/1024)) $comp"
  else                                            # fallback
    echo "0 0 0"
  fi
}

# ───────────────────────── Default option values ─────────────────────────
mkdir -p ./logs
TIMESTAMP=$(date -u +"%Y%m%dT%H%M%SZ")
LOG_FILE="./logs/wait_all_${TIMESTAMP}.log"

VERBOSE=0 JSON=0 TIMEOUT=0 KILL_SIGNAL="SIGTERM" RETRY_MAX=0 INSTALL_DEPS=0
CMD=()  LEGACY_CMD_STRING=""

# ───────────────────────────── Option parsing ────────────────────────────
while (( $# )); do
  case $1 in
    --verbose)       VERBOSE=1 ;;
    --json)          JSON=1 ;;
    --install-deps)  INSTALL_DEPS=1 ;;
    --log)     shift || die "--log needs filename"
               LOG_FILE=$1 ;;
    --timeout) shift || die "--timeout needs value"
               is_integer "$1" || die "--timeout must be integer"
               TIMEOUT=$1 ;;
    --kill-signal) shift || die "--kill-signal needs value"
                   is_valid_signal "$1" || die "unknown signal: $1"
                   KILL_SIGNAL=$1 ;;
    --retry)   shift || die "--retry needs value"
               is_integer "$1" || die "--retry must be integer"
               RETRY_MAX=$1 ;;
    --help)    usage; exit 0 ;;
    --)        shift; CMD=("$@"); break ;;
    --*)       die "unknown option: $1" ;;
    *)         LEGACY_CMD_STRING=$1; break ;;
  esac
  shift
done
[[ -n $LEGACY_CMD_STRING || ${#CMD[@]} -gt 0 ]] || { usage; exit 1; }

mkdir -p "$(dirname "$LOG_FILE")" || die "cannot create log dir"
echo "$SCRIPT_NAME v$VERSION" >>"$LOG_FILE"

# ────────── Dependency detection / optional automatic installation ───────
missing_cmds=()
for cmd in jq gawk pnpm uv; do have "$cmd" || missing_cmds+=("$cmd"); done

if (( ${#missing_cmds[@]} )); then
  if (( INSTALL_DEPS )); then
    if [[ $(uname) == Darwin ]]; then
      have brew || die "Homebrew not installed – please install first"
      brew install "${missing_cmds[@]}" || die "brew install failed"
    elif [[ -f /etc/debian_version ]]; then
      sudo apt-get update && sudo apt-get install -y "${missing_cmds[@]}" || die "apt-get failed"
    elif [[ -f /etc/alpine-release ]]; then
      sudo apk add --no-cache "${missing_cmds[@]}" || die "apk add failed"
    elif [[ $(uname) == FreeBSD ]]; then
      sudo pkg install -y "${missing_cmds[@]}" || die "pkg install failed"
    else
      die "automatic dependency install not supported on this OS"
    fi
  else
    echo "Missing dependencies: ${missing_cmds[*]}" >&2
    echo "Re-run with --install-deps to attempt automatic installation" >&2
  fi
fi


# ─────────────────────── JSON helper for stdout/err ──────────────────────
json_encode() {
  local out=$1 err=$2 code=$3
  if have jq; then
    jq -n --arg out "$out" --arg err "$err" --argjson code "$code" \
         '{stdout:$out, stderr:$err, exit_code:$code}'
  else
    printf '{"stdout_b64":"%s","stderr_b64":"%s","exit_code":%d}\n' \
           "$(printf %s "$out" | base64 | tr -d '\n')" \
           "$(printf %s "$err" | base64 | tr -d '\n')" "$code"
    echo "# (streams base64-encoded; jq absent)" >&2
  fi
}

# ╭────────────────── AUTO-RUNNER HEURISTIC (Bash-3.2-safe) ───────────────╮
# | adjust_command IN_ARRAY OUT_ARRAY                                      |
# ╰────────────────────────────────────────────────────────────────────────╯
adjust_command() {
  local in_name=$1 out_name=$2
  # Safer array handling for bash 3.2 compatibility
  # Get first element using nameref-like behavior without bash 4 features
  local first_var="${in_name}[0]"
  local first="${!first_var}"

  # Copy array using indirect expansion
  local array_var="${in_name}[@]"
  local -a orig=("${!array_var}")

  # Set output array to input by default
  eval "${out_name}=(\"\${orig[@]}\")"

  set_out() {
    # Set output array with arguments
    eval "${out_name}=(\"\$@\")"
  }

  # 0) Already a launcher?
  case $first in uv|uvx|pnpm|yarn|node|go|osascript) return 0 ;; esac

  # 1) python → uv run / uv pip
  if [[ $first == python* ]] && have uv; then
    if [[ ${orig[1]:-} == -m && ${orig[2]:-} == pip ]]; then
      set_out uv pip "${orig[@]:3}"
    else
      set_out uv run "${orig[@]:1}"
    fi
    return 0
  fi

  # 2) bash script.sh → uv run
  if [[ $first == bash && ${orig[1]:-} == *.sh ]] && have uv; then
    set_out uv run "${orig[@]:1}"; return 0
  fi

  # 3) Bare *.py
  if [[ $first == *.py ]]; then
    if have uv; then set_out uv run "${orig[@]}"; else set_out python "${orig[@]}"; fi
    return 0
  fi

  # 4) Bare *.sh
  if [[ $first == *.sh ]]; then
    if have uv && venv_active; then set_out uv run "${orig[@]}"; else set_out bash "${orig[@]}"; fi
    return 0
  fi

  # 5) pip / pip3
  if [[ $first == pip* ]]; then
    have uv && set_out uv pip "${orig[@]:1}"; return 0
  fi

  # 6) npm → pnpm
  if [[ $first == npm ]] && have pnpm; then
    if [[ ${orig[1]:-} == run ]]; then
      set_out pnpm run "${orig[@]:2}"
    else
      set_out pnpm "${orig[@]:1}"
    fi
    return 0
  fi

  # 7) Bare package.json script → pnpm run
  if [[ -f package.json ]] && have pnpm; then
    if have jq && jq -e --arg s "$first" '.scripts[$s]?' package.json >/dev/null 2>&1; then
      set_out pnpm run "$first" "${orig[@]:1}"
    fi
  fi
}

# ────────────────── Function: run the command once ───────────────────────
run_once() {
  local attempt=$1

  # Temp files for captured streams & memory samples
  local tmp_out tmp_err mem_snap
  tmp_out=$(mktemp); TEMP_FILES+=("$tmp_out")
  tmp_err=$(mktemp); TEMP_FILES+=("$tmp_err")
  mem_snap=$(mktemp); TEMP_FILES+=("$mem_snap")

  # Build command array from legacy or modern form
  local C_IN=()
  if [[ -n $LEGACY_CMD_STRING ]]; then
    # Parse legacy command string safely
    # Note: eval is required here to handle complex quoting scenarios
    # This is the one place where eval is necessary and safe
    # because LEGACY_CMD_STRING comes from command line arguments
    eval "set -- $LEGACY_CMD_STRING"
    C_IN=("$@")
  else
    C_IN=("${CMD[@]}")
  fi

  local RUN=()
  adjust_command C_IN RUN
  (( VERBOSE )) && printf '[%s] Launching: %q\n' "$SCRIPT_NAME" "${RUN[@]}" >&2

  # Start child; setsid if available
  if have setsid; then
    setsid "${RUN[@]}" >"$tmp_out" 2>"$tmp_err" &
  else
    "${RUN[@]}"        >"$tmp_out" 2>"$tmp_err" &
  fi
  local main_pid=$!

  # IMMEDIATELY track the spawned process
  SPAWNED_PIDS+=("$main_pid")

  # Small delay to ensure process starts
  sleep_short 0.02

  # Get process-group ID (macOS needs -p)
  local pgid=""
  if kill -0 "$main_pid" 2>/dev/null; then
    # Try to get pgid with retries for slow-starting processes
    local retry
    for _ in 1 2 3; do
      if pgid=$(ps -p "$main_pid" -o pgid= 2>/dev/null); then
        pgid=$(echo "$pgid" | tr -d '[:space:],<')
        if [[ -n "$pgid" ]] && [[ "$pgid" -gt 0 ]]; then
          # Track the process group (unless it's our own)
          if [[ "$pgid" != "$WAIT_ALL_PGID" ]]; then
            SPAWNED_PGIDS+=("$pgid")
          fi

          # IMMEDIATELY scan for child processes
          local ps_output
          if [[ $(uname) == "Darwin" ]]; then
            ps_output=$(ps -g "$pgid" -o pid= 2>/dev/null || true)
          else
            ps_output=$(ps -o pid= -g "$pgid" 2>/dev/null || true)
          fi

          if [[ -n "$ps_output" ]]; then
            local child_pid
            for child_pid in $ps_output; do
              if [[ "$child_pid" =~ ^[0-9]+$ ]] && [[ "$child_pid" != "$main_pid" ]]; then
                # Track child processes immediately
                local already_tracked=0
                local p
                for p in "${SPAWNED_PIDS[@]:-}"; do
                  if [[ "$p" == "$child_pid" ]]; then
                    already_tracked=1
                    break
                  fi
                done
                if (( ! already_tracked )); then
                  SPAWNED_PIDS+=("$child_pid")
                  (( VERBOSE )) && echo "[$SCRIPT_NAME] Discovered child process: PID $child_pid" >&2
                fi
              fi
            done
          fi

          break
        fi
      fi
      sleep_short 0.02
    done
  fi

  local timed_out=0 exit_code=0
  local start_s=$(epoch_s)
  local SAMPLE=0.05  # Sample every 50ms to catch short-lived processes

  # ── Monitoring loop ────────────────────────────────────────────────────
  while kill -0 "$main_pid" 2>/dev/null; do
    sleep_short "$SAMPLE"

    # Find all descendants of main process
    local descendants=$(find_descendants "$main_pid")
    if [[ -n "$descendants" ]]; then
      local desc_pid
      for desc_pid in $descendants; do
        if [[ "$desc_pid" =~ ^[0-9]+$ ]]; then
          # Track this descendant if not already tracked
          local already_tracked=0
          local p
          for p in "${SPAWNED_PIDS[@]:-}"; do
            if [[ "$p" == "$desc_pid" ]]; then
              already_tracked=1
              break
            fi
          done
          if (( ! already_tracked )); then
            # Skip our own PID and parent PID
            if [[ "$desc_pid" != "$WAIT_ALL_PID" ]] && [[ "$desc_pid" != "$WAIT_ALL_PPID" ]]; then
              SPAWNED_PIDS+=("$desc_pid")
              (( VERBOSE )) && echo "[$SCRIPT_NAME] Found descendant process: PID $desc_pid" >&2
            fi
          fi
        fi
      done
    fi

    # Sample memory AND track all processes in the group
    if [[ -n $pgid ]] && [[ "$pgid" -gt 0 ]]; then
      # Get all processes in the group
      local ps_output
      if [[ $(uname) == "Darwin" ]]; then
        # macOS: use -g with pgid
        ps_output=$(ps -g "$pgid" -o pid=,rss= 2>/dev/null || true)
      else
        # Linux: use -g with space
        ps_output=$(ps -o pid=,rss= -g "$pgid" 2>/dev/null || true)
      fi

      # Process each PID found (avoiding subshell to preserve array modifications)
      if [[ -n "$ps_output" ]]; then
        # Save to temp file to avoid subshell
        local ps_temp=$(mktemp); TEMP_FILES+=("$ps_temp")
        echo "$ps_output" >"$ps_temp"

        # Read line by line without creating subshell
        while IFS= read -r line; do
          local pid rss
          # Parse the line
          set -- $line
          pid=$1 rss=$2

          if [[ -n "$pid" ]] && [[ "$pid" =~ ^[0-9]+$ ]]; then
            # Track this PID if we haven't seen it before
            local already_tracked=0
            local p
            for p in "${SPAWNED_PIDS[@]:-}"; do
              if [[ "$p" == "$pid" ]]; then
                already_tracked=1
                break
              fi
            done

            # Add new PIDs to our tracking
            if (( ! already_tracked )); then
              # Skip our own PID and parent PID
              if [[ "$pid" != "$WAIT_ALL_PID" ]] && [[ "$pid" != "$WAIT_ALL_PPID" ]]; then
                SPAWNED_PIDS+=("$pid")
                if [[ -n "${LOG_FILE:-}" ]]; then
                  echo "Discovered new process: PID $pid in pgid $pgid" >>"$LOG_FILE" 2>&1 || true
                fi
              fi
            fi

            # Record memory usage
            if [[ -n "$rss" ]] && [[ "$rss" =~ ^[0-9]+$ ]]; then
              local sys
              sys=$(sys_mem)
              printf '%s %s %s %s\n' "$(epoch_s)" "$pid" "$rss" "$sys" >>"$mem_snap"
            fi
          fi
        done <"$ps_temp"

        rm -f "$ps_temp"
      fi
    fi

    # Timeout?
    if (( TIMEOUT > 0 )) && (( $(epoch_s) - start_s >= TIMEOUT )); then
      (( VERBOSE )) && echo "[$SCRIPT_NAME] Timeout → $KILL_SIGNAL pgid $pgid" >&2
      {
        echo "TIMEOUT after ${TIMEOUT}s — killing pgid $pgid"
        ps -o pid,ppid,stat,command -g "$pgid"
      } >>"$LOG_FILE" 2>&1 || true
      [[ -n $pgid ]] && kill "-$KILL_SIGNAL" "-$pgid" 2>/dev/null || \
                       kill "-$KILL_SIGNAL" "$main_pid" 2>/dev/null || true
      timed_out=1
      break
    fi
  done

  # Wait for exit & settle
  # Disable error checking for wait since we want to capture the exit code
  set +e
  wait "$main_pid" 2>/dev/null
  local child_rc=$?
  set -e

  # Wait for all processes in group to exit
  if [[ -n "$pgid" ]] && [[ "$pgid" -gt 0 ]]; then
    local wait_count=0
    while pgrep -g "$pgid" >/dev/null 2>&1 && (( wait_count < 50 )); do
      sleep_short 0.05
      wait_count=$((wait_count + 1))
    done
    # Force kill if still running after 2.5 seconds
    if pgrep -g "$pgid" >/dev/null 2>&1; then
      kill -KILL -"$pgid" 2>/dev/null || true
    fi
  fi

  # Remove completed process from tracking arrays
  local new_pids=()
  local pid
  for pid in "${SPAWNED_PIDS[@]:-}"; do
    if [[ "$pid" != "$main_pid" ]]; then
      new_pids+=("$pid")
    fi
  done
  # Handle empty array case
  if (( ${#new_pids[@]} > 0 )); then
    SPAWNED_PIDS=("${new_pids[@]}")
  else
    SPAWNED_PIDS=()
  fi

  # Remove pgid from tracking
  local new_pgids=()
  local pg
  for pg in "${SPAWNED_PGIDS[@]:-}"; do
    if [[ "$pg" != "$pgid" ]]; then
      new_pgids+=("$pg")
    fi
  done
  if (( ${#new_pgids[@]} > 0 )); then
    SPAWNED_PGIDS=("${new_pgids[@]}")
  else
    SPAWNED_PGIDS=()
  fi

  if (( timed_out )); then exit_code=124; else exit_code=$child_rc; fi

  # Read captured streams
  local stdout stderr
  stdout=$(<"$tmp_out")
  stderr=$(<"$tmp_err")

  # ── Summarise memory peaks (portable awk first; gawk if available) ─────
  {
    echo "=== TRY #$attempt  @ $(date -u +"%F %T UTC")  (v$VERSION) ==="
    echo "CMD : ${RUN[*]}"
    echo "EXIT: $exit_code"
    (( timed_out )) && echo "TIMEOUT: ${TIMEOUT}s"
    echo "--- Peak memory per PID (KiB) ---------------------------------"
    if have gawk && gawk 'BEGIN{ exit !(has="asort") }' </dev/null 2>/dev/null; then
      gawk '
        {
          pid=$2; rss=$3; used=$4; tot=$5;
          if (rss>max[pid]) { max[pid]=rss; ts[pid]=$1; used_s[pid]=used; tot_s[pid]=tot }
        }
        END {
          n=asort(max, idx)
          for (i=1;i<=n;i++) {
            p=idx[i]
            pct=(tot_s[p]>0)?used_s[p]*100/tot_s[p]:0;
            printf "PID %s  peakRSS=%d  epoch=%s  sys=%d/%dKiB (%.1f%%)\n",
                   p,max[p],ts[p],used_s[p],tot_s[p],pct;
          }
        }' "$mem_snap"
    else
      awk '{ if($3>rss[$2]) rss[$2]=$3 }
           END{ for(k in rss) printf "PID %s peakRSS=%dKiB\n",k,rss[k] }' \
           "$mem_snap"
    fi
    echo "----------------------------------------------------------------"
    echo "STDOUT ↓"; printf '%s\n' "$stdout"
    echo "STDERR ↓"; printf '%s\n' "$stderr"
    echo
  } >>"$LOG_FILE"

  # ── Return triple “tmp_out tmp_err exit_code” to caller (NUL-separated) ─
  printf '%s\0%s\0%d' "$tmp_out" "$tmp_err" "$exit_code"
}

# ───────────────────── Retry orchestration loop ──────────────────────────
final_out='' final_err='' final_rc=0
for (( attempt=1; ; ++attempt )); do
  # Check if run_once is defined (removed debug comment that was corrupting output)
  if ! declare -f run_once >/dev/null 2>&1; then
    die "run_once function not defined"
  fi
  # Read NUL-separated output from run_once
  # Use temporary file to handle NUL-separated values
  TEMP_RUN=$(mktemp); TEMP_FILES+=("$TEMP_RUN")
  run_once "$attempt" > "$TEMP_RUN"

  # Extract the three NUL-separated values
  # Use tr to convert NUL to newlines for easier parsing
  tr '\0' '\n' < "$TEMP_RUN" > "${TEMP_RUN}.lines"
  out_f=$(sed -n '1p' "${TEMP_RUN}.lines")
  err_f=$(sed -n '2p' "${TEMP_RUN}.lines")
  rc=$(sed -n '3p' "${TEMP_RUN}.lines")
  rm -f "${TEMP_RUN}.lines"


  # Default values if extraction failed
  : "${out_f:=/dev/null}"
  : "${err_f:=/dev/null}"
  : "${rc:=1}"
  if (( rc == 0 )) || (( attempt > RETRY_MAX )); then
    final_out=$(<"$out_f")
    final_err=$(<"$err_f")
    final_rc=$rc
    break
  fi
  (( VERBOSE )) && \
    echo "[$SCRIPT_NAME] attempt $attempt failed (exit $rc) — retrying…" >&2
done

# ───────────────────────── Emit final result ─────────────────────────────
if (( JSON )); then
  json_encode "$final_out" "$final_err" "$final_rc"
else
  printf '%s' "$final_out"
  [[ -n $final_err ]] && printf '%s' "$final_err" >&2
fi
exit "$final_rc"
