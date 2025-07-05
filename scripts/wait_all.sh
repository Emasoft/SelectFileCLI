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
#        Signal delivered when the timeout triggers.  May b#e a number (9),
#        plain name (KILL) or “SIGKILL”.  Default: SIGTERM.#
#
#  --retry <N>
#        Retry the command up to N additional times after non-zero exit or a
#        timeout.  A successful run stops the loop immediately.#
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
  printf '%s: %s\n' "$SCRIPT_NAME" "$*" >&2
  printf "execute '%s --help' for more details.\n" "$SCRIPT_NAME" >&2
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

# Temp-file cleanup on any exit
TEMP_FILES=()
cleanup() { rm -f -- "${TEMP_FILES[@]:-}" 2>/dev/null || true; }
trap cleanup EXIT
trap 'die "unexpected error on line $LINENO"' ERR

# ───────────────────────── Helpers: validation ───────────────────────────
have()            { command -v "$1" >/dev/null 2>&1; }
is_integer()      { [[ ${1:-x} =~ ^[0-9]+$ ]]; }

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
    local total=$(awk '/^MemTotal:/{print $2}' /proc/meminfo)
    local avail=$(awk '/^MemAvailable:/{print $2}' /proc/meminfo)
    echo "$((total-avail)) $total 0"
  elif have vm_stat && have sysctl; then          # macOS / FreeBSD
    local page=$(sysctl -n hw.pagesize)
    : "${page:=4096}"                             # fallback if empty
    local total_b=$(sysctl -n hw.memsize)
    local free=$(vm_stat | awk '/Pages free/{print $3}' | tr -d '.')
    local inactive=$(vm_stat | awk '/Pages inactive/{print $3}' | tr -d '.')
    local spec=$(vm_stat | awk '/Pages speculative/{print $3}' | tr -d '.')
    local comp=$(vm_stat | awk '/occupied by compressor/{print $5}' | tr -d '.')
    local used_b=$(( total_b - (free+inactive+spec)*page ))
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
  eval "local first=\${${in_name}[0]}"
  eval "local -a orig=(\"\${${in_name}[@]}\")"
  eval "${out_name}=(\"\${orig[@]}\")"   # default: unchanged

  set_out() { eval "${out_name}=(\"$@\")"; }

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
  if [[ $first == bash && ${orig[1]:-} == *.sh && have uv ]]; then
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
  if [[ $first == npm && have pnpm ]]; then
    if [[ ${orig[1]:-} == run ]]; then
      set_out pnpm run "${orig[@]:2}"
    else
      set_out pnpm "${orig[@]:1}"
    fi
    return 0
  fi

  # 7) Bare package.json script → pnpm run
  if [[ -f package.json && have pnpm ]]; then
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
    # Preserve quoting/escaping by re-parsing through the shell
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

  # Get process-group ID (macOS needs -p)
  local pgid
  if pgid=$(ps -p "$main_pid" -o pgid= 2>/dev/null); then
    pgid=$(tr -d '[:space:],<' <<<"$pgid")
  else
    pgid=""
  fi

  local timed_out=0 exit_code=0
  local start_s=$(epoch_s)
  local SAMPLE=0.2

  # ── Monitoring loop ────────────────────────────────────────────────────
  while kill -0 "$main_pid" 2>/dev/null; do
    sleep_short "$SAMPLE"

    # Sample memory (only if we know pgid)
    if [[ -n $pgid ]]; then
      # GNU ps accepts " -g $pgid", macOS needs "-g$pgid"
      if ps -o pid= -g "$pgid" >/dev/null 2>&1; then
        ps -o pid=,rss= -g "$pgid"
      else
        ps -g"$pgid" -o pid,rss
      fi | while read -r pid rss; do
          local sys
          sys=$(sys_mem)
          printf '%s %s %s %s\n' "$(epoch_s)" "$pid" "$rss" "$sys" >>"$mem_snap"
        done
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
  wait "$main_pid" 2>/dev/null || true
  local child_rc=$?
  if [[ -n $pgid ]]; then
    while pgrep -g "$pgid" >/dev/null 2>&1; do sleep_short 0.05; done
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
final_out= final_err= final_rc=0
for (( attempt=1; ; ++attempt )); do
  IFS=$'\0' read -r out_f err_f rc < <(run_once "$attempt")
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
