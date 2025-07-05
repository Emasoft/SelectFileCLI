# Sequential Pipeline Setup Guide

A bulletproof solution for preventing process explosions, memory exhaustion, and system lockups during development operations.

## 🎯 What This Solves

- **Process Explosions**: Prevents 70+ concurrent processes from overwhelming your system
- **Memory Exhaustion**: Real-time monitoring kills processes exceeding limits (default 2GB)
- **Git Corruption**: Serializes git operations to prevent index conflicts
- **Pre-commit Deadlocks**: Detects and prevents circular dependencies
- **Blind Debugging**: Real-time logs track every process, memory usage, and execution time

## 🏗️ Architecture

```
User Command
    ↓
wait_all.sh --    OR    sequential-executor.sh
    ↓                           ↓
Actual Command            wait_all.sh --
(with cleanup)                 ↓
                          Actual Command
                          (with cleanup + queue)
```

### Key Components:
- **wait_all.sh**: Atomic execution with complete subprocess cleanup
- **sequential-executor.sh**: Sequential locking with queue management
- **memory_monitor.sh**: Real-time memory tracking and enforcement
- **Logging**: Every operation logged with timestamps and memory usage

## 📋 Prerequisites

### Required Software
```bash
# Check bash version (needs 4.0+)
bash --version

# macOS users must upgrade bash
brew install bash

# Install uv (fast Python package manager)
curl -LsSf https://astral.sh/uv/install.sh | sh

# Install pre-commit with uv support
uv tool install pre-commit --with pre-commit-uv
```

## 🚀 Quick Setup

Copy and run these commands in your project root:

```bash
# 1. Create directories
mkdir -p scripts logs

# 2. Download setup script (or copy from Step 2 below)
cd scripts
# Copy all scripts from Step 2 into this directory

# 3. Make scripts executable
chmod +x *.sh

# 4. Run setup verification
cd ..
./scripts/ensure-sequential.sh

# 5. Install pre-commit hooks
pre-commit install

# 6. Create environment configuration
cat > .env.development << 'EOF'
# Memory limits
MEMORY_LIMIT_MB=2048    # 2GB per process
CHECK_INTERVAL=5        # Check every 5 seconds

# Timeouts
TIMEOUT=1800            # 30 minutes default
PIPELINE_TIMEOUT=7200   # 2 hours for entire pipeline
EOF

# 7. Test the setup
./scripts/wait_all.sh -- echo "✅ Sequential pipeline ready!"
```

## 📝 Step 1: Create Directories

```bash
mkdir -p scripts logs
cd scripts
```

## 📦 Step 2: Create Essential Scripts

### 2.1 `wait_all.sh` - Atomic Process Manager

This is the core building block that ensures complete process cleanup.

<details>
<summary>Click to view wait_all.sh (625 lines)</summary>

```bash
cat > wait_all.sh << 'EOF'
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
#    • Transparently "upgrades" plain invocations to faster launchers
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
#   *    Any other code is the wrapped command's exit status
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
A portable "run-and-really-wait" wrapper
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
    • Transparently "upgrades" plain invocations to faster launchers
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
        plain name (KILL) or "SIGKILL".  Default: SIGTERM.

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
  other  The wrapped command's exit status (last attempt).

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

# Print header until first blank line after "EXAMPLES" (used nowhere now but
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

# ─── System-memory snapshot: "used_kB total_kB compressed_pages" ──────────
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

  # ── Return triple "tmp_out tmp_err exit_code" to caller (NUL-separated) ─
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

EOF
chmod +x wait_all.sh
```
</details>

### 2.2 `sequential-executor.sh` - Queue Manager

Ensures only ONE process runs at a time with queue management.

```bash
cat > sequential-executor.sh << 'EOF'
#!/usr/bin/env bash
# sequential-executor-strict.sh - TRUE sequential execution
#
# Principles:
# 1. Processes wait INDEFINITELY for their turn - no timeouts on lock acquisition
# 2. Only ONE process runs at a time - no exceptions
# 3. Pipeline timeout applies to the entire execution chain
# 4. If pipeline times out, ALL processes are killed
# 5. Commands should be ATOMIC - smallest possible units of work
#
# CRITICAL: This executor works with wait_all.sh to form a sequential chain.
# Each wait_all.sh command should be atomic to minimize memory usage and
# enable precise failure isolation.
#
# Example of ATOMIC commands (GOOD):
#   sequential-executor.sh ruff format src/main.py
#   sequential-executor.sh pytest tests/test_one.py
#   sequential-executor.sh mypy --strict src/module.py
#
# Example of NON-ATOMIC commands (BAD):
#   sequential-executor.sh ruff format .
#   sequential-executor.sh pytest
#   sequential-executor.sh mypy --strict src/
#
set -euo pipefail

# Check bash version (require 4.0+)
if [ "${BASH_VERSION%%.*}" -lt 4 ]; then
    echo "ERROR: This script requires bash 4.0 or higher" >&2
    exit 1
fi

# Global configuration
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
PROJECT_HASH=$(echo "$PROJECT_ROOT" | shasum | cut -d' ' -f1 | head -c 8)

# Lock and state files
LOCK_DIR="/tmp/seq-exec-${PROJECT_HASH}"
LOCKFILE="${LOCK_DIR}/executor.lock"
QUEUE_FILE="${LOCK_DIR}/queue.txt"
CURRENT_PID_FILE="${LOCK_DIR}/current.pid"
PIPELINE_START_FILE="${LOCK_DIR}/pipeline_start.txt"
PIPELINE_TIMEOUT_FILE="${LOCK_DIR}/pipeline_timeout.txt"

# Pipeline timeout (applies to entire chain)
PIPELINE_TIMEOUT="${PIPELINE_TIMEOUT:-7200}"  # 2 hours default

# Ensure lock directory exists
mkdir -p "$LOCK_DIR"

# Create logs directory
LOGS_DIR="${PROJECT_ROOT}/logs"
mkdir -p "$LOGS_DIR"
EXEC_LOG="${LOGS_DIR}/sequential_executor_strict_$(date '+%Y%m%d_%H%M%S')_$$.log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging functions
log() {
    local level=$1; shift
    local color=""
    case $level in
        ERROR) color=$RED ;;
        WARN)  color=$YELLOW ;;
        INFO)  color=$GREEN ;;
        DEBUG) color=$BLUE ;;
    esac
    local msg="[SEQ-STRICT] $(date '+%Y-%m-%d %H:%M:%S') [$level] $*"
    echo -e "${color}${msg}${NC}" >&2
    echo "$msg" >> "$EXEC_LOG"
}

# Get all descendant PIDs
get_descendants() {
    local pid=$1
    local children=$(pgrep -P "$pid" 2>/dev/null || true)
    for child in $children; do
        echo "$child"
        get_descendants "$child"
    done
}

# Kill entire process tree
kill_process_tree() {
    local pid=$1
    local signal=${2:-TERM}

    # Get all descendants first
    local all_pids="$pid $(get_descendants "$pid")"

    # Send signal to all
    for p in $all_pids; do
        if kill -0 "$p" 2>/dev/null; then
            kill -$signal "$p" 2>/dev/null || true
        fi
    done

    # Give time to terminate gracefully
    sleep 2

    # Force kill any remaining
    for p in $all_pids; do
        if kill -0 "$p" 2>/dev/null; then
            kill -KILL "$p" 2>/dev/null || true
        fi
    done
}

# Check and enforce pipeline timeout
check_pipeline_timeout() {
    if [ ! -f "$PIPELINE_TIMEOUT_FILE" ]; then
        # First process in pipeline - set timeout
        echo "$(date +%s):$PIPELINE_TIMEOUT" > "$PIPELINE_TIMEOUT_FILE"
        log INFO "Pipeline timeout set to ${PIPELINE_TIMEOUT}s"

        # Start timeout monitor in background
        (
            sleep $PIPELINE_TIMEOUT
            if [ -f "$PIPELINE_TIMEOUT_FILE" ]; then
                log ERROR "PIPELINE TIMEOUT after ${PIPELINE_TIMEOUT}s - killing all processes"

                # Kill all processes in queue
                if [ -f "$QUEUE_FILE" ]; then
                    while IFS=: read -r pid ts cmd; do
                        if kill -0 "$pid" 2>/dev/null; then
                            log WARN "Killing queued process PID $pid"
                            kill_process_tree "$pid"
                        fi
                    done < "$QUEUE_FILE"
                fi

                # Kill current process
                if [ -f "$CURRENT_PID_FILE" ]; then
                    current=$(cat "$CURRENT_PID_FILE" 2>/dev/null || echo 0)
                    if [ "$current" -gt 0 ] && kill -0 "$current" 2>/dev/null; then
                        log WARN "Killing current process PID $current"
                        kill_process_tree "$current"
                    fi
                fi

                # Clean up all locks
                rm -rf "$LOCK_DIR"
            fi
        ) &
    else
        # Check if pipeline already timed out
        local timeout_info=$(cat "$PIPELINE_TIMEOUT_FILE" 2>/dev/null || echo "0:0")
        local start_time=$(echo "$timeout_info" | cut -d: -f1)
        local timeout=$(echo "$timeout_info" | cut -d: -f2)
        local now=$(date +%s)
        local elapsed=$((now - start_time))

        if [ $elapsed -gt $timeout ]; then
            log ERROR "Pipeline already timed out (${elapsed}s > ${timeout}s)"
            exit 126  # Pipeline timeout exit code
        fi

        log INFO "Pipeline time remaining: $((timeout - elapsed))s"
    fi
}

# Cleanup function
cleanup() {
    local exit_code=$?

    # Stop memory monitor if running
    if [ -n "${MONITOR_PID:-}" ]; then
        kill $MONITOR_PID 2>/dev/null || true
    fi

    # Remove from queue
    if [ -f "$QUEUE_FILE" ]; then
        grep -v "^$$:" "$QUEUE_FILE" > "${QUEUE_FILE}.tmp" 2>/dev/null || true
        mv -f "${QUEUE_FILE}.tmp" "$QUEUE_FILE" 2>/dev/null || true
    fi

    # Release lock if we hold it
    if [ -f "$CURRENT_PID_FILE" ]; then
        local current=$(cat "$CURRENT_PID_FILE" 2>/dev/null || echo 0)
        if [ "$current" -eq "$$" ]; then
            rm -f "$CURRENT_PID_FILE"
            rmdir "$LOCKFILE" 2>/dev/null || true
            log INFO "Lock released"

            # If queue is empty, pipeline is complete
            if [ ! -s "$QUEUE_FILE" ]; then
                log INFO "Queue empty - pipeline complete"
                rm -f "$PIPELINE_TIMEOUT_FILE"
            fi
        fi
    fi

    log INFO "Sequential executor exiting with code: $exit_code"
    echo "Log saved to: $EXEC_LOG" >&2

    exit $exit_code
}

trap cleanup EXIT INT TERM

# Main execution
log INFO "Starting strict sequential executor for: $*"
log INFO "Project: $PROJECT_ROOT"

# Check pipeline timeout
check_pipeline_timeout

# Add to queue
echo "$$:$(date '+%s'):$*" >> "$QUEUE_FILE"
log INFO "Added to queue (PID $$)"

# Wait for our turn - INDEFINITELY
log INFO "Waiting for exclusive lock (will wait indefinitely)..."
WAIT_COUNT=0

while true; do
    # Try to acquire lock
    if mkdir "$LOCKFILE" 2>/dev/null; then
        echo $$ > "$CURRENT_PID_FILE"
        log INFO "Lock acquired"
        break
    fi

    # Get current lock holder
    HOLDER_PID=$(cat "$CURRENT_PID_FILE" 2>/dev/null || echo 0)

    if [ "$HOLDER_PID" -gt 0 ]; then
        # Check if holder is alive
        if kill -0 "$HOLDER_PID" 2>/dev/null; then
            # Log status periodically
            if [ $((WAIT_COUNT % 60)) -eq 0 ] && [ $WAIT_COUNT -gt 0 ]; then
                local cmd=$(ps -p "$HOLDER_PID" -o args= 2>/dev/null | head -1 || echo "unknown")
                local wait_time=$((WAIT_COUNT))
                log INFO "Still waiting for PID $HOLDER_PID: $cmd (${wait_time}s elapsed)"

                # Show queue position
                if [ -f "$QUEUE_FILE" ]; then
                    position=$(grep -n "^$$:" "$QUEUE_FILE" 2>/dev/null | cut -d: -f1 || echo "?")
                    total=$(wc -l < "$QUEUE_FILE" 2>/dev/null || echo "?")
                    log INFO "Queue position: $position of $total"
                fi
            fi
        else
            # Holder is dead, clean up
            log WARN "Lock holder (PID $HOLDER_PID) died unexpectedly"
            rm -f "$CURRENT_PID_FILE"
            rmdir "$LOCKFILE" 2>/dev/null || true

            # This is an error condition - previous process died
            log ERROR "Previous process died - sequential chain broken"
            # Continue to acquire lock and execute
        fi
    else
        # No PID file but lock exists - clean up
        log WARN "Stale lock detected, cleaning up"
        rmdir "$LOCKFILE" 2>/dev/null || true
    fi

    sleep 1
    ((WAIT_COUNT++))
done

# Execute the command
log INFO "Executing: $*"

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Start memory monitor
if [ -x "${SCRIPT_DIR}/memory_monitor.sh" ]; then
    log INFO "Starting memory monitor"
    "${SCRIPT_DIR}/memory_monitor.sh" --pid $$ --limit "${MEMORY_LIMIT_MB:-2048}" &
    MONITOR_PID=$!
fi

# Execute through wait_all.sh if available
if [ -x "${SCRIPT_DIR}/wait_all.sh" ]; then
    "${SCRIPT_DIR}/wait_all.sh" --timeout "${TIMEOUT:-1800}" -- "$@"
    EXIT_CODE=$?
else
    "$@"
    EXIT_CODE=$?
fi

log INFO "Command completed with exit code: $EXIT_CODE"
exit $EXIT_CODE
EOF
chmod +x sequential-executor.sh
```

### 2.3 `memory_monitor.sh` - Memory Guardian

Real-time memory monitoring with automatic process termination.

```bash
cat > memory_monitor.sh << 'EOF'
#!/usr/bin/env bash
# memory_monitor.sh - Monitor and kill processes exceeding memory limits
#
# Usage: memory_monitor.sh --pid <PID> --limit <MB>
#
# Features:
# - Monitors process tree memory usage
# - Logs warnings at 50% of limit
# - Kills process tree at 100% of limit
# - Real-time logging to ./logs/
#
set -euo pipefail

# Parse arguments
PID=""
LIMIT_MB=2048
CHECK_INTERVAL=5

while [[ $# -gt 0 ]]; do
    case $1 in
        --pid)
            PID="$2"
            shift 2
            ;;
        --limit)
            LIMIT_MB="$2"
            shift 2
            ;;
        --interval)
            CHECK_INTERVAL="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

if [ -z "$PID" ]; then
    echo "ERROR: --pid required" >&2
    exit 1
fi

# Setup logging
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
LOGS_DIR="${PROJECT_ROOT}/logs"
mkdir -p "$LOGS_DIR"
LOG_FILE="${LOGS_DIR}/memory_monitor_$(date '+%Y%m%d_%H%M%S')_$$.log"

# Colors
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

# Logging
log() {
    local level=$1; shift
    local color=""
    case $level in
        ERROR) color=$RED ;;
        WARN)  color=$YELLOW ;;
        INFO)  color=$GREEN ;;
    esac
    local msg="[MEMORY] $(date '+%Y-%m-%d %H:%M:%S') [$level] $*"
    echo -e "${color}${msg}${NC}" >&2
    echo "$msg" >> "$LOG_FILE"
}

# Get memory in MB
get_memory_mb() {
    local pid=$1
    if [ -f "/proc/$pid/status" ]; then
        # Linux: Use VmRSS from status
        awk '/VmRSS:/ {print int($2/1024)}' "/proc/$pid/status" 2>/dev/null || echo 0
    else
        # macOS/BSD: Use ps
        ps -p "$pid" -o rss= 2>/dev/null | awk '{print int($1/1024)}' || echo 0
    fi
}

# Get all descendant PIDs
get_descendants() {
    local parent_pid=$1
    local children=$(pgrep -P "$parent_pid" 2>/dev/null || true)
    for child in $children; do
        echo "$child"
        get_descendants "$child"
    done
}

# Kill process tree
kill_process_tree() {
    local pid=$1
    local signal=${2:-TERM}

    # Get all descendants first
    local all_pids="$pid $(get_descendants "$pid")"

    # Send signal to all
    for p in $all_pids; do
        if kill -0 "$p" 2>/dev/null; then
            kill -$signal "$p" 2>/dev/null || true
            log WARN "Sent $signal to PID $p"
        fi
    done

    # Give time to terminate gracefully
    sleep 2

    # Force kill any remaining
    for p in $all_pids; do
        if kill -0 "$p" 2>/dev/null; then
            kill -KILL "$p" 2>/dev/null || true
            log ERROR "Force killed PID $p"
        fi
    done
}

# Main monitoring loop
log INFO "Starting memory monitor for PID $PID (limit: ${LIMIT_MB}MB)"
log INFO "Check interval: ${CHECK_INTERVAL}s"
log INFO "Log file: $LOG_FILE"

# Initial snapshot
all_pids="$PID $(get_descendants "$PID")"
log INFO "Initial process tree:"
for pid in $all_pids; do
    if kill -0 "$pid" 2>/dev/null; then
        local cmd=$(ps -p "$pid" -o comm= 2>/dev/null || echo "unknown")
        local mem=$(get_memory_mb "$pid")
        log INFO "  PID $pid: $cmd = ${mem}MB"
    fi
done

# Monitor loop
check_count=0
while kill -0 "$PID" 2>/dev/null; do
    ((check_count++))

    # Get all PIDs in tree
    all_pids="$PID $(get_descendants "$PID")"
    total_mem=0
    process_count=0

    # Check each process
    for pid in $all_pids; do
        if kill -0 "$pid" 2>/dev/null; then
            mem=$(get_memory_mb "$pid")
            cmd=$(ps -p "$pid" -o comm= 2>/dev/null || echo "unknown")
            ((total_mem += mem))
            ((process_count++))

            # Log individual process if using significant memory
            if (( mem > LIMIT_MB / 10 )); then
                echo "  PID $pid: $cmd = ${mem}MB" >> "$LOG_FILE"
            fi

            # Warn if individual process is high
            if (( mem > LIMIT_MB / 2 )); then
                log WARN "PID $pid using ${mem}MB (>50% of limit)"
            fi
        fi
    done

    # Log summary every 10 checks
    if (( check_count % 10 == 0 )); then
        log INFO "Total memory: ${total_mem}MB across $process_count processes"
    fi

    # Check total against limit
    if (( total_mem > LIMIT_MB )); then
        log ERROR "MEMORY LIMIT EXCEEDED: ${total_mem}MB > ${LIMIT_MB}MB"
        log ERROR "Killing process tree for PID $PID"

        # Log final state
        for pid in $all_pids; do
            if kill -0 "$pid" 2>/dev/null; then
                mem=$(get_memory_mb "$pid")
                cmd=$(ps -p "$pid" -o args= 2>/dev/null || echo "unknown")
                log ERROR "  PID $pid: ${mem}MB - $cmd"
            fi
        done

        # Kill the tree
        kill_process_tree "$PID"
        log ERROR "Process tree terminated due to memory limit"
        exit 1
    fi

    # Warn at 75%
    if (( total_mem > LIMIT_MB * 3 / 4 )); then
        log WARN "High memory usage: ${total_mem}MB (>75% of ${LIMIT_MB}MB limit)"
    fi

    sleep "$CHECK_INTERVAL"
done

log INFO "Monitored process $PID has exited normally"
log INFO "Final memory usage: ${total_mem}MB"
EOF
chmod +x memory_monitor.sh
```

### 2.4 `git-safe.sh` - Git Operations Wrapper

Prevents concurrent git operations and index corruption.

```bash
cat > git-safe.sh << 'EOF'
#!/usr/bin/env bash
# git-safe.sh - Safe git wrapper that prevents concurrent git operations
# This wrapper ensures only ONE git operation runs at a time
#
# Enhanced to handle pre-commit hooks and prevent deadlocks

set -euo pipefail

# Skip if already in a git hook to prevent deadlocks
if [ -n "${GIT_DIR:-}" ] || [ -n "${GIT_WORK_TREE:-}" ]; then
    # We're inside a git hook - execute directly
    exec git "$@"
fi

# For commits, set flag so pre-commit hooks know they're part of this operation
if [[ "$1" == "commit" ]]; then
    export GIT_COMMIT_IN_PROGRESS=1
    export SEQUENTIAL_EXECUTOR_PID=$$  # Prevent nested sequential execution
fi

# Get project info
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
PROJECT_HASH=$(echo "$PROJECT_ROOT" | shasum | cut -d' ' -f1 | head -c 8)

# Git operation lock (separate from sequential executor lock)
GIT_LOCK_DIR="/tmp/git-safe-${PROJECT_HASH}"
GIT_LOCKFILE="${GIT_LOCK_DIR}/git.lock"
GIT_OPERATION_FILE="${GIT_LOCK_DIR}/current_operation.txt"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Ensure lock directory exists
mkdir -p "$GIT_LOCK_DIR"

# Function to check for existing git operations
check_existing_git_operations() {
    # Check for any running git processes
    local git_procs=$(pgrep -f "git (commit|merge|rebase|cherry-pick|push|pull)" 2>/dev/null || true)

    if [ -n "$git_procs" ]; then
        echo -e "${RED}ERROR: Git operations already in progress:${NC}" >&2
        for pid in $git_procs; do
            local cmd=$(ps -p "$pid" -o args= 2>/dev/null || echo "unknown")
            echo -e "  ${YELLOW}PID $pid:${NC} $cmd" >&2
        done
        return 1
    fi

    # Check for git lock files
    if [ -f "$PROJECT_ROOT/.git/index.lock" ]; then
        echo -e "${RED}ERROR: Git index lock exists - another git process may be running${NC}" >&2
        echo -e "${YELLOW}To force remove: rm -f $PROJECT_ROOT/.git/index.lock${NC}" >&2
        return 1
    fi

    # Check for our own lock
    if [ -d "$GIT_LOCKFILE" ]; then
        if [ -f "$GIT_OPERATION_FILE" ]; then
            local current_op=$(cat "$GIT_OPERATION_FILE" 2>/dev/null || echo "unknown")
            local pid=$(echo "$current_op" | cut -d: -f1)

            # Check if the process is still alive
            if kill -0 "$pid" 2>/dev/null; then
                echo -e "${RED}ERROR: Git operation already in progress:${NC}" >&2
                echo -e "  $current_op" >&2
                return 1
            else
                # Stale lock, clean it up
                echo -e "${YELLOW}Cleaning up stale git lock...${NC}" >&2
                rm -rf "$GIT_LOCKFILE" "$GIT_OPERATION_FILE"
            fi
        fi
    fi

    return 0
}

# Function to acquire git lock
acquire_git_lock() {
    local max_wait=30  # Maximum 30 seconds wait
    local waited=0

    while ! mkdir "$GIT_LOCKFILE" 2>/dev/null; do
        if [ "$waited" -ge "$max_wait" ]; then
            echo -e "${RED}ERROR: Could not acquire git lock after ${max_wait}s${NC}" >&2
            return 1
        fi

        if [ "$waited" -eq 0 ]; then
            echo -e "${YELLOW}Waiting for git lock...${NC}" >&2
        fi

        sleep 1
        waited=$((waited + 1))
    done

    # Record current operation
    echo "$$:$(date '+%Y-%m-%d %H:%M:%S'):git $*" > "$GIT_OPERATION_FILE"
    return 0
}

# Function to release git lock
release_git_lock() {
    rm -rf "$GIT_LOCKFILE" "$GIT_OPERATION_FILE" 2>/dev/null || true
}

# Cleanup function
cleanup() {
    local exit_code=$?
    release_git_lock
    exit $exit_code
}

trap cleanup EXIT INT TERM

# Main execution
echo -e "${GREEN}[GIT-SAFE]${NC} Checking for concurrent git operations..."

# Check for existing operations
if ! check_existing_git_operations; then
    echo -e "${RED}[GIT-SAFE]${NC} Aborting to prevent conflicts" >&2
    exit 1
fi

# Try to acquire lock
if ! acquire_git_lock "$@"; then
    exit 1
fi

echo -e "${GREEN}[GIT-SAFE]${NC} Executing: git $*"

# Get script directory for wait_all.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WAIT_ALL="${SCRIPT_DIR}/wait_all.sh"

# Use wait_all.sh for atomic execution
if [ -x "$WAIT_ALL" ]; then
    # Execute atomically through wait_all.sh
    "$WAIT_ALL" -- git "$@"
else
    # Direct execution (fallback)
    git "$@"
fi

EXIT_CODE=$?

echo -e "${GREEN}[GIT-SAFE]${NC} Git operation completed with exit code: $EXIT_CODE"

exit $EXIT_CODE
EOF
chmod +x git-safe.sh
```

### 2.5 `make-sequential.sh` - Make Command Wrapper

Prevents concurrent make executions.

```bash
cat > make-sequential.sh << 'EOF'
#!/usr/bin/env bash
# make-sequential.sh - Prevents concurrent make executions
set -euo pipefail

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
PROJECT_HASH=$(echo "$PROJECT_ROOT" | shasum | cut -d' ' -f1 | head -c 8)

# Global make lock
MAKE_LOCK="/tmp/make-lock-${PROJECT_HASH}"
MAKE_QUEUE="/tmp/make-queue-${PROJECT_HASH}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[MAKE-SEQ]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $*"
}

log_error() {
    echo -e "${RED}[MAKE-SEQ]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $*" >&2
}

# Cleanup on exit
cleanup() {
    if [ -f "$MAKE_QUEUE" ]; then
        grep -v "^$$:" "$MAKE_QUEUE" > "${MAKE_QUEUE}.tmp" 2>/dev/null || true
        mv -f "${MAKE_QUEUE}.tmp" "$MAKE_QUEUE" 2>/dev/null || true
    fi

    if [ -d "$MAKE_LOCK" ]; then
        local lock_pid=$(cat "$MAKE_LOCK/pid" 2>/dev/null || echo 0)
        [ "$lock_pid" -eq "$$" ] && rm -rf "$MAKE_LOCK"
    fi
}
trap cleanup EXIT

# Acquire lock
while true; do
    if mkdir "$MAKE_LOCK" 2>/dev/null; then
        echo $$ > "$MAKE_LOCK/pid"
        break
    fi

    local lock_pid=$(cat "$MAKE_LOCK/pid" 2>/dev/null || echo 0)
    if ! kill -0 "$lock_pid" 2>/dev/null; then
        log_info "Removing stale lock"
        rm -rf "$MAKE_LOCK"
        continue
    fi

    # Add to queue if not there
    if ! grep -q "^$$:" "$MAKE_QUEUE" 2>/dev/null; then
        echo "$$:$*" >> "$MAKE_QUEUE"
    fi

    log_info "Waiting for make lock (held by PID $lock_pid)..."
    sleep 1
done

log_info "Lock acquired, executing: make $*"

# Execute through wait_all.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"${SCRIPT_DIR}/wait_all.sh" -- make "$@"
EOF
chmod +x make-sequential.sh
```

### 2.6 `monitor-queue.sh` - Visual Queue Monitor

Real-time visualization of the execution queue.

```bash
cat > monitor-queue.sh << 'EOF'
#!/usr/bin/env bash
# monitor-queue.sh - Real-time queue visualization
set -euo pipefail

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
PROJECT_HASH=$(echo "$PROJECT_ROOT" | shasum | cut -d' ' -f1 | head -c 8)
LOCK_DIR="/tmp/seq-exec-${PROJECT_HASH}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

clear
echo -e "${GREEN}=== Sequential Execution Queue Monitor ===${NC}"
echo "Project: $PROJECT_ROOT"
echo "Lock directory: $LOCK_DIR"
echo ""

while true; do
    # Move cursor to line 5
    tput cup 4 0

    # Clear from cursor to end of screen
    tput ed

    # Current process
    if [ -f "$LOCK_DIR/current.pid" ]; then
        current_pid=$(cat "$LOCK_DIR/current.pid" 2>/dev/null || echo "none")
        if kill -0 "$current_pid" 2>/dev/null; then
            cmd=$(ps -p "$current_pid" -o args= 2>/dev/null | head -1 || echo "unknown")
            echo -e "${GREEN}RUNNING:${NC} PID $current_pid"
            echo -e "  Command: $cmd"

            # Show memory usage if available
            if command -v ps >/dev/null 2>&1; then
                mem=$(ps -p "$current_pid" -o rss= 2>/dev/null | awk '{print int($1/1024)}' || echo "?")
                echo -e "  Memory: ${mem}MB"
            fi
        else
            echo -e "${RED}RUNNING:${NC} Dead process (PID $current_pid)"
        fi
    else
        echo -e "${YELLOW}RUNNING:${NC} None"
    fi

    echo ""
    echo -e "${BLUE}QUEUED:${NC}"

    # Queue
    if [ -f "$LOCK_DIR/queue.txt" ] && [ -s "$LOCK_DIR/queue.txt" ]; then
        position=1
        while IFS=: read -r pid ts cmd; do
            if kill -0 "$pid" 2>/dev/null; then
                echo -e "  $position. PID $pid: $cmd"
                ((position++))
            fi
        done < "$LOCK_DIR/queue.txt"

        if [ $position -eq 1 ]; then
            echo "  (empty)"
        fi
    else
        echo "  (empty)"
    fi

    echo ""
    echo -e "${YELLOW}Press Ctrl+C to exit${NC}"

    sleep 1
done
EOF
chmod +x monitor-queue.sh
```

### 2.7 `kill-orphans.sh` - Emergency Cleanup

Kills orphaned processes from failed executions.

```bash
cat > kill-orphans.sh << 'EOF'
#!/usr/bin/env bash
# kill-orphans.sh - Clean up orphaned processes
set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}Searching for orphaned processes...${NC}"

# Patterns to match
PATTERNS=(
    "pytest"
    "python.*test"
    "uv run"
    "pre-commit"
    "ruff"
    "mypy"
    "wait_all.sh"
    "sequential-executor"
)

killed=0
for pattern in "${PATTERNS[@]}"; do
    pids=$(pgrep -f "$pattern" 2>/dev/null || true)
    for pid in $pids; do
        # Skip self and parent
        [ "$pid" -eq "$$" ] && continue
        [ "$pid" -eq "$PPID" ] && continue

        # Check if orphaned (parent is init)
        ppid=$(ps -o ppid= -p "$pid" 2>/dev/null | xargs || echo 1)
        if [ "$ppid" -eq 1 ]; then
            cmd=$(ps -p "$pid" -o args= 2>/dev/null || echo "unknown")
            echo -e "${RED}Killing orphan:${NC} PID $pid - $cmd"
            kill -TERM "$pid" 2>/dev/null || true
            ((killed++))
        fi
    done
done

echo -e "${GREEN}Killed $killed orphaned process(es)${NC}"

# Clean up stale locks
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
PROJECT_HASH=$(echo "$PROJECT_ROOT" | shasum | cut -d' ' -f1 | head -c 8)

echo -e "${YELLOW}Cleaning up stale locks...${NC}"
rm -rf "/tmp/seq-exec-${PROJECT_HASH}/"* 2>/dev/null || true
rm -rf "/tmp/make-lock-${PROJECT_HASH}/"* 2>/dev/null || true
rm -rf "/tmp/git-safe-${PROJECT_HASH}/"* 2>/dev/null || true

echo -e "${GREEN}Cleanup complete!${NC}"
EOF
chmod +x kill-orphans.sh
```

### 2.8 `pre-commit-safe.sh` - Pre-commit Hook Wrapper

Prevents pre-commit deadlocks.

```bash
cat > pre-commit-safe.sh << 'EOF'
#!/usr/bin/env bash
# pre-commit-safe.sh - Wrapper for pre-commit hooks to ensure sequential execution
#
# This script solves the deadlock issue by:
# 1. Detecting if we're already inside a pre-commit execution
# 2. Running commands directly if inside pre-commit (no double-locking)
# 3. Using sequential executor only for the initial pre-commit call
#
set -euo pipefail

# Check if we're already inside a pre-commit execution
if [ -n "${PRE_COMMIT_RUNNING:-}" ]; then
    # We're inside pre-commit, execute directly to avoid deadlock
    exec "$@"
fi

# Check if we're being called by pre-commit directly
if [[ "${BASH_SOURCE[1]:-}" == *"pre-commit"* ]] || [[ "${0}" == *"pre-commit"* ]]; then
    # Set flag for child processes
    export PRE_COMMIT_RUNNING=1
    # Execute directly - pre-commit handles its own serialization
    exec "$@"
fi

# Otherwise, use sequential executor for serialization
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${SCRIPT_DIR}/sequential-executor.sh" "$@"
EOF
chmod +x pre-commit-safe.sh
```

### 2.9 `atomic-hook.sh` - Atomic Pre-commit Helper

Helper for processing files individually in pre-commit hooks.

```bash
cat > atomic-hook.sh << 'EOF'
#!/usr/bin/env bash
# atomic-hook.sh - Helper script for atomic pre-commit operations
#
# Usage: atomic-hook.sh <command> <files...>
#   Example: atomic-hook.sh "ruff format" file1.py file2.py
#
set -euo pipefail

# Get command from first argument
COMMAND="$1"
shift

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WAIT_ALL="${SCRIPT_DIR}/wait_all.sh"

# Check if wait_all.sh exists
if [ ! -x "$WAIT_ALL" ]; then
    echo "ERROR: wait_all.sh not found at: $WAIT_ALL" >&2
    exit 1
fi

# Colors
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# Process each file atomically
for file in "$@"; do
    echo -e "${YELLOW}[ATOMIC]${NC} Processing: $file"
    "$WAIT_ALL" --timeout 60 -- $COMMAND "$file" || exit 1
    echo -e "${GREEN}[ATOMIC]${NC} Completed: $file"
done

echo -e "${GREEN}[ATOMIC]${NC} All files processed successfully"
EOF
chmod +x atomic-hook.sh
```

### 2.10 `example-atomic-pipeline.sh` - Pipeline Example

Demonstrates proper atomic command usage.

```bash
cat > example-atomic-pipeline.sh << 'EOF'
#!/usr/bin/env bash
# example-atomic-pipeline.sh - Example of atomic sequential pipeline
#
# This script demonstrates how to build a proper atomic sequential pipeline
# using wait_all.sh as the atomic building block.
#
set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WAIT_ALL="${SCRIPT_DIR}/wait_all.sh"

# Check if wait_all.sh exists
if [ ! -x "$WAIT_ALL" ]; then
    echo "ERROR: wait_all.sh not found at: $WAIT_ALL" >&2
    exit 1
fi

# Example Python files to process
PYTHON_FILES=(
    "src/main.py"
    "src/module1.py"
    "src/module2.py"
    "tests/test_main.py"
    "tests/test_module1.py"
)

echo "=== Atomic Sequential Pipeline Example ==="
echo "Each command runs in isolation with complete cleanup"
echo

# Step 1: Format each file atomically
echo "Step 1: Formatting files atomically..."
for file in "${PYTHON_FILES[@]}"; do
    if [ -f "$file" ]; then
        echo "  Formatting: $file"
        "$WAIT_ALL" --timeout 30 -- ruff format "$file"
    fi
done

# Step 2: Lint each file atomically
echo -e "\nStep 2: Linting files atomically..."
for file in "${PYTHON_FILES[@]}"; do
    if [ -f "$file" ]; then
        echo "  Linting: $file"
        "$WAIT_ALL" --timeout 60 -- ruff check --fix "$file"
    fi
done

# Step 3: Type check each file atomically
echo -e "\nStep 3: Type checking files atomically..."
for file in "${PYTHON_FILES[@]}"; do
    if [ -f "$file" ]; then
        echo "  Type checking: $file"
        "$WAIT_ALL" --timeout 120 -- mypy --strict "$file"
    fi
done

# Step 4: Run tests atomically
echo -e "\nStep 4: Running tests atomically..."
for file in tests/test_*.py; do
    if [ -f "$file" ]; then
        echo "  Testing: $file"
        "$WAIT_ALL" --timeout 300 -- pytest -v "$file"
    fi
done

echo -e "\n=== Pipeline Complete ==="
echo "All operations executed atomically through wait_all.sh"
echo "Check ./logs/ for detailed execution logs"

# Example of WRONG approach (commented out):
# echo "DON'T DO THIS - Non-atomic batch operations:"
# "$WAIT_ALL" -- ruff format .                    # Formats ALL files at once
# "$WAIT_ALL" -- pytest                           # Runs ALL tests at once
# "$WAIT_ALL" -- pip install -r requirements.txt  # Installs ALL packages at once
EOF
chmod +x example-atomic-pipeline.sh
```

### 2.11 `ensure-sequential.sh` - Setup Verification

Verifies and completes the sequential pipeline setup.

```bash
cat > ensure-sequential.sh << 'EOF'
#!/usr/bin/env bash
# ensure-sequential.sh - Ensures ALL operations use sequential executor

set -euo pipefail

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
SEQUENTIAL_EXECUTOR="$PROJECT_ROOT/scripts/sequential-executor.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== Ensuring Sequential Execution Setup ===${NC}"

# 1. Check sequential executor exists and is executable
if [ ! -f "$SEQUENTIAL_EXECUTOR" ]; then
    echo -e "${RED}ERROR: Sequential executor not found at: $SEQUENTIAL_EXECUTOR${NC}"
    exit 1
fi

if [ ! -x "$SEQUENTIAL_EXECUTOR" ]; then
    echo -e "${YELLOW}Making sequential executor executable...${NC}"
    chmod +x "$SEQUENTIAL_EXECUTOR"
fi

# 2. Check wait_all.sh exists and is executable
WAIT_ALL="$PROJECT_ROOT/scripts/wait_all.sh"
if [ -f "$WAIT_ALL" ]; then
    chmod +x "$WAIT_ALL"
    echo -e "${GREEN}✓ wait_all.sh properly configured${NC}"
else
    echo -e "${RED}ERROR: wait_all.sh not found${NC}"
    exit 1
fi

# 3. Check all scripts are executable
for script in "$PROJECT_ROOT"/scripts/*.sh; do
    if [ -f "$script" ] && [ ! -x "$script" ]; then
        echo -e "${YELLOW}Making executable: $(basename "$script")${NC}"
        chmod +x "$script"
    fi
done

# 4. Install/Update pre-commit hook
HOOKS_DIR="$PROJECT_ROOT/.git/hooks"
if [ -d "$HOOKS_DIR" ]; then
    echo -e "${YELLOW}Installing pre-commit hook...${NC}"
    cat > "$HOOKS_DIR/pre-commit" << 'HOOK'
#!/usr/bin/env bash
# Sequential execution safety hook
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
# Sequential executor will use wait_all.sh internally for atomic operations
"$PROJECT_ROOT/scripts/sequential-executor.sh" pre-commit "$@"
HOOK
    chmod +x "$HOOKS_DIR/pre-commit"
    echo -e "${GREEN}✓ pre-commit hook installed${NC}"
fi

# 5. Verify critical scripts exist
CRITICAL_SCRIPTS=("wait_all.sh" "sequential-executor.sh" "memory_monitor.sh")
for script in "${CRITICAL_SCRIPTS[@]}"; do
    if [ ! -f "$PROJECT_ROOT/scripts/$script" ]; then
        echo -e "${RED}ERROR: Missing critical script: $script${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ Found: $script${NC}"
done

# 6. Check environment file
if [ ! -f "$PROJECT_ROOT/.env.development" ]; then
    echo -e "${YELLOW}WARNING: .env.development missing${NC}"
    echo -e "${YELLOW}Create it with environment variables shown in setup guide${NC}"
fi

# 7. Summary
echo -e "\n${GREEN}=== Sequential Execution Setup Summary ===${NC}"
echo "Scripts directory: $PROJECT_ROOT/scripts/"
echo "Logs directory: $PROJECT_ROOT/logs/"
echo ""
echo -e "${GREEN}READY!${NC} Use these commands:"
echo "  make test     - Run tests sequentially"
echo "  make lint     - Run linters sequentially"
echo "  make format   - Format code sequentially"
echo "  ./scripts/wait_all.sh -- <cmd>  - Run any command atomically"
echo "  ./scripts/sequential-executor.sh <cmd>  - Run with sequential locking"
echo ""
echo -e "${YELLOW}Monitor queue:${NC} ./scripts/monitor-queue.sh"
echo -e "${YELLOW}Emergency cleanup:${NC} ./scripts/kill-orphans.sh"
EOF
chmod +x ensure-sequential.sh
```

## 🔍 Step 3: Real-time Monitoring & Debugging

### Understanding the Logs

The sequential pipeline creates detailed logs in `./logs/` for every operation:

1. **wait_all.sh logs**: `wait_all_<timestamp>.log`
   - Complete command output (stdout/stderr)
   - Exit codes
   - Memory usage per process
   - Execution timeline

2. **sequential-executor logs**: `sequential_executor_strict_<timestamp>_<pid>.log`
   - Queue status
   - Lock acquisition/release
   - Wait times
   - Pipeline timeout status

3. **memory_monitor logs**: `memory_monitor_<timestamp>_<pid>.log`
   - Real-time memory tracking
   - Process tree snapshots
   - Memory limit violations
   - Process termination events

### Real-time Monitoring Commands

```bash
# Watch all logs in real-time
tail -f logs/*.log

# Monitor specific operation
tail -f logs/wait_all_*.log | grep -E "CMD|EXIT|memory"

# Watch memory usage
tail -f logs/memory_monitor_*.log | grep -E "WARNING|ERROR|Total memory"

# See queue status
./scripts/monitor-queue.sh

# Check current execution
ps aux | grep -E "wait_all|sequential-executor|memory_monitor"
```

### Debugging Common Issues

```bash
# Find failed commands
grep "EXIT: [^0]" logs/wait_all_*.log

# Find memory violations
grep "MEMORY LIMIT EXCEEDED" logs/memory_monitor_*.log

# Find timeout events
grep "TIMEOUT" logs/*.log

# Find deadlocks
grep -E "died unexpectedly|sequential chain broken" logs/sequential_executor_*.log

# Analyze long-running processes
grep "Still waiting" logs/sequential_executor_*.log
```

### Log Analysis Examples

```bash
# Get execution times for all pytest runs
grep -h "CMD.*pytest" logs/wait_all_*.log | \
  while read line; do
    file=$(echo "$line" | grep -oE "logs/[^:]+")
    echo -n "$line => "
    grep "TRY.*@ " "$file" | tail -1
  done

# Memory usage summary
for f in logs/memory_monitor_*.log; do
    echo "=== $f ==="
    grep "Total memory:" "$f" | tail -5
done

# Queue wait times
grep "Queue position:" logs/sequential_executor_*.log | \
  awk '{print $NF " - Wait: " $(NF-3) "s"}'
```

## ⚙️ Step 4: Configuration

### Environment Variables (.env.development)

```bash
# Memory limits
MEMORY_LIMIT_MB=2048    # 2GB per process
CHECK_INTERVAL=5        # Check every 5 seconds

# Timeouts
TIMEOUT=1800            # 30 minutes per command
PIPELINE_TIMEOUT=7200   # 2 hours for entire pipeline

# Debugging
VERBOSE=1               # Enable verbose output
```

### Pre-commit Configuration (.pre-commit-config.yaml)

```yaml
default_language_version:
  python: python3.11

repos:
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v5.0.0
    hooks:
      - id: trailing-whitespace
      - id: end-of-file-fixer
      - id: check-yaml
      - id: check-added-large-files
        args: ['--maxkb=10240']

  - repo: local
    hooks:
      # Atomic formatting - each file individually
      - id: ruff-format-atomic
        name: Format Python (atomic)
        entry: bash -c 'for f in "$@"; do ./scripts/wait_all.sh --timeout 60 -- ruff format "$f" || exit 1; done' --
        language: system
        types: [python]
        require_serial: true
        pass_filenames: true

      # Atomic linting - each file individually
      - id: ruff-check-atomic
        name: Lint Python (atomic)
        entry: bash -c 'for f in "$@"; do ./scripts/wait_all.sh --timeout 60 -- ruff check --fix "$f" || exit 1; done' --
        language: system
        types: [python]
        require_serial: true
        pass_filenames: true

      # Tests can run as batch with timeout
      - id: pytest-fast
        name: Run fast tests
        entry: ./scripts/wait_all.sh --timeout 300 -- pytest -m "not slow" -v
        language: system
        pass_filenames: false
        always_run: true
```

### Makefile Configuration

```makefile
# Atomic execution wrapper
WAIT_ALL := ./scripts/wait_all.sh

# Python source files
PY_FILES := $(shell find src tests -name "*.py" -type f)

# Format each file atomically
format:
	@for f in $(PY_FILES); do \
		echo "Formatting: $$f"; \
		$(WAIT_ALL) --timeout 30 -- ruff format "$$f" || exit 1; \
	done

# Lint each file atomically
lint:
	@for f in $(PY_FILES); do \
		echo "Checking: $$f"; \
		$(WAIT_ALL) --timeout 60 -- ruff check --fix "$$f" || exit 1; \
	done

# Test with timeout
test:
	$(WAIT_ALL) --timeout 1800 -- pytest -v

# Sequential targets
.PHONY: all
all: format lint test
```

### pytest Configuration (pytest.ini)

```ini
[pytest]
# Force sequential execution
addopts =
    -v
    --strict-markers
    --tb=short
    --disable-warnings
    -p no:xdist

# No parallel execution
testpaths = tests
python_files = test_*.py
python_classes = Test*
python_functions = test_*

# Timeout per test
timeout = 300
```

## 📊 Step 5: Usage Patterns

### Basic Command Execution

```bash
# Atomic execution (allows parallel, ensures cleanup)
./scripts/wait_all.sh -- python script.py
./scripts/wait_all.sh -- pytest tests/test_file.py
./scripts/wait_all.sh -- ruff format src/

# Sequential execution (one at a time, with queue)
./scripts/sequential-executor.sh make test
./scripts/sequential-executor.sh git commit -m "message"
```

### With Environment Variables

```bash
# Custom memory limit
MEMORY_LIMIT_MB=512 ./scripts/wait_all.sh -- python memory_intensive.py

# Custom timeout
TIMEOUT=60 ./scripts/wait_all.sh -- pytest tests/slow_test.py

# Verbose output
./scripts/wait_all.sh --verbose -- npm install
```

### Debugging Failed Executions

```bash
# 1. Check the logs
ls -lt logs/ | head -10

# 2. Find the relevant log
grep -l "my_script.py" logs/wait_all_*.log

# 3. Analyze the failure
cat logs/wait_all_20240105T120000Z.log

# 4. Check memory usage
grep "Peak memory" logs/wait_all_20240105T120000Z.log

# 5. Monitor in real-time
tail -f logs/wait_all_*.log | grep -E "CMD|EXIT|TIMEOUT|memory"
```

## 🛠️ Step 6: Troubleshooting

### Common Issues and Solutions

#### Process Explosion Despite Setup
```bash
# Check for direct command usage
ps aux | grep -E "pytest|ruff|mypy" | grep -v wait_all

# Solution: Always use wait_all.sh or sequential-executor.sh
alias pytest='./scripts/wait_all.sh -- pytest'
alias ruff='./scripts/wait_all.sh -- ruff'
```

#### Memory Limit Exceeded
```bash
# Check current limits
grep MEMORY_LIMIT .env.development

# Increase temporarily
MEMORY_LIMIT_MB=4096 ./scripts/wait_all.sh -- python script.py

# Find memory hogs
grep "High memory" logs/memory_monitor_*.log
```

#### Deadlocks
```bash
# Check for circular dependencies
./scripts/monitor-queue.sh

# Emergency cleanup
./scripts/kill-orphans.sh

# Reset all locks
rm -rf /tmp/seq-exec-*
rm -rf /tmp/make-lock-*
rm -rf /tmp/git-safe-*
```

#### Pipeline Timeouts
```bash
# Check pipeline status
cat /tmp/seq-exec-*/pipeline_timeout.txt

# Increase pipeline timeout
PIPELINE_TIMEOUT=14400 make test  # 4 hours
```

## ✅ Step 7: Verification

Run these commands to verify your setup:

```bash
# 1. Test atomic execution
./scripts/wait_all.sh -- echo "✅ Atomic execution works!"

# 2. Test sequential locking
for i in {1..3}; do
    ./scripts/sequential-executor.sh bash -c "echo 'Task $i'; sleep 2" &
done
# Should see tasks run one at a time

# 3. Test memory limiting
MEMORY_LIMIT_MB=100 ./scripts/wait_all.sh -- python -c "x = [0] * 50000000"
# Should be killed for exceeding memory

# 4. Test timeout
TIMEOUT=2 ./scripts/wait_all.sh -- sleep 5
# Should timeout after 2 seconds

# 5. Check logs
ls -la logs/
# Should see detailed logs for each test
```

## 🏁 Summary

You now have a bulletproof sequential pipeline that:
- ✅ Prevents process explosions
- ✅ Monitors and limits memory usage
- ✅ Provides detailed real-time logging
- ✅ Prevents git corruption
- ✅ Handles pre-commit hooks safely
- ✅ Offers visual queue monitoring

Use `wait_all.sh --` for atomic operations and `sequential-executor.sh` when you need strict sequential execution with queue management.

## 📚 Quick Reference

```bash
# Atomic execution (parallel allowed, cleanup guaranteed)
./scripts/wait_all.sh -- <command>

# Sequential execution (one at a time)
./scripts/sequential-executor.sh <command>

# Monitor queue
./scripts/monitor-queue.sh

# View logs
tail -f logs/*.log

# Emergency cleanup
./scripts/kill-orphans.sh

# Make commands (already sequential)
make test
make lint
make format
```
