#!/usr/bin/env bash
#
# python-env-report.sh — Detect and report the Python environment on this Mac.
#
# Inventories every Python interpreter the shell can see (active PATH pick,
# uv-managed, Homebrew, conda, python.org framework, macOS system), shows conda
# environments, explains command resolution, and identifies installations that
# merit review. Read-only: it inspects and reports, it never installs or removes
# anything.
#
# Usage:
#   ./python-env-report.sh
#
# The helper functions are defined at the top level so the unit tests in tests/
# can source this file without running the report. main() only runs when the
# script is executed directly (see the guard at the bottom).
#
set -uo pipefail   # no -e: probes are allowed to fail; we handle that per-check
PROBE_TIMEOUT="${PY_ENV_REPORT_TIMEOUT:-3}"
[[ "$PROBE_TIMEOUT" =~ ^[1-9][0-9]*$ ]] || PROBE_TIMEOUT=3
REPORT_TIMEOUT="${PY_ENV_REPORT_MAX_SECONDS:-60}"
[[ "$REPORT_TIMEOUT" =~ ^[1-9][0-9]*$ ]] || REPORT_TIMEOUT=60
REPORT_STARTED=$SECONDS
REPORT_BUDGET_WARNED=0

if command -v gtimeout >/dev/null 2>&1; then
  PROBE_IMPL=gtimeout
elif [[ -x /usr/bin/perl ]]; then
  PROBE_IMPL=perl
else
  PROBE_IMPL=none
fi

# ---------------------------------------------------------------------------
# Output helpers (mirrors install.sh). Colors collapse to empty when stdout is
# not a TTY (e.g. under the test harness), keeping output easy to assert on.
# ---------------------------------------------------------------------------
if [[ -t 1 ]]; then
  BOLD=$'\033[1m'; BLUE=$'\033[34m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; DIM=$'\033[2m'; RESET=$'\033[0m'
else
  BOLD=''; BLUE=''; GREEN=''; YELLOW=''; DIM=''; RESET=''
fi

info() { printf '\n%s==>%s %s%s%s\n' "${BLUE}${BOLD}" "$RESET" "$BOLD" "$*" "$RESET"; }
ok()   { printf '%s ok%s %s\n'   "${GREEN}${BOLD}" "$RESET" "$*"; }
warn() { printf '%swarn%s %s\n'  "${YELLOW}${BOLD}" "$RESET" "$*"; }
row()  { printf '     %s\n' "$*"; }

# Resolve symlinks to a real path (readlink -f isn't on stock macOS).
realpath_p() {
  local p="$1" hops=0 dir base
  while [[ -L "$p" && $hops -lt 40 ]]; do
    local t; t="$(readlink "$p")"
    [[ "$t" != /* ]] && t="$(dirname "$p")/$t"
    p="$t"
    hops=$((hops + 1))
  done
  [[ $hops -lt 40 ]] || return 1
  dir="$(dirname "$p")"; base="$(basename "$p")"
  dir="$(cd -P "$dir" 2>/dev/null && pwd)" || return 1
  printf '%s/%s' "$dir" "$base"
}

# ver <python-binary> -> "3.13.13" or "" if it won't run.
ver() {
  local output rc
  output="$(run_local_probe "$1" --version 2>&1)"; rc=$?
  (( rc == 0 )) || return 1
  printf '%s\n' "$output" | awk '$1 ~ /^Python$/ && $2 ~ /^[0-9]+\.[0-9]+/{print $2; exit}'
}

# mm_of "3.13.13" -> "3.13" (major.minor). Empty in -> empty out.
mm_of() { printf '%s' "$1" | awk -F. 'NF>=2{print $1"."$2}'; }

# Execute one command with the best timeout implementation available. Local
# interpreter probes use this without consuming the package-manager budget.
run_with_timeout() {
  local limit="$1"; shift
  case "$PROBE_IMPL" in
    gtimeout)
      LC_ALL=C LANG=C gtimeout --signal=TERM "${limit}s" "$@"
      ;;
    perl)
      LC_ALL=C LANG=C /usr/bin/perl -e '$s=shift; $p=fork(); defined $p or exit 125; if(!$p){setpgrp(0,0); exec {$ARGV[0]} @ARGV; exit 126} $SIG{ALRM}=sub{kill 15,-$p; waitpid($p,0); exit 124}; alarm $s; waitpid($p,0); alarm 0; exit($?>>8)' \
        "$limit" "$@"
      ;;
    none)
      LC_ALL=C LANG=C "$@"
      ;;
  esac
}

run_local_probe() {
  run_with_timeout "$PROBE_TIMEOUT" "$@"
}

report_budget_exhausted() {
  (( SECONDS - REPORT_STARTED >= REPORT_TIMEOUT ))
}

announce_report_budget_exhaustion() {
  if report_budget_exhausted && (( ! REPORT_BUDGET_WARNED )); then
    warn "Time budget exhausted — remaining manager probes skipped"
    REPORT_BUDGET_WARNED=1
  fi
}

# Bound package-manager and login-shell probes by both per-command and total
# deadlines. Exit 124 means the command timed out or the total budget is gone.
run_probe() {
  local remaining=$((REPORT_TIMEOUT - (SECONDS - REPORT_STARTED))) limit="$PROBE_TIMEOUT"
  (( remaining > 0 )) || return 124
  (( remaining < limit )) && limit="$remaining"
  run_with_timeout "$limit" "$@"
}

interpreter_identity() {
  run_local_probe "$1" -c 'import platform,sys; print("|".join((sys.executable or "?",platform.python_version(),platform.python_implementation(),platform.machine(),sys.prefix,sys.base_prefix)))'
}

# path_diagnostics — identify repeated and stale PATH entries. Repetition is a
# shell-configuration problem, not a Python-installation problem, but it often
# explains surprising command resolution.
path_diagnostics() {
  local old_ifs="$IFS" entry seen="" reported=""
  IFS=:
  for entry in $PATH; do
    [[ -z "$entry" ]] && entry="."
    if printf '%s\n' "$seen" | grep -Fqx "$entry"; then
      if ! printf '%s\n' "$reported" | grep -Fqx "$entry"; then
        printf 'duplicate\t%s\n' "$entry"
        reported="${reported}${reported:+$'\n'}${entry}"
      fi
    else
      seen="${seen}${seen:+$'\n'}${entry}"
    fi
    [[ -d "$entry" ]] || printf 'missing\t%s\n' "$entry"
  done
  IFS="$old_ifs"
}

uv_inventory() {
  local output rc
  output="$(run_probe uv --no-cache python list --only-installed --managed-python 2>&1)"; rc=$?
  if (( rc == 0 )); then
    printf 'success\n%s' "$output"
  else
    printf 'unknown\n%s' "$(printf '%s' "$output" | tail -1)"
  fi
}

conda_resolution_state() {
  local prefix="$1" python_path="$2" python3_path="$3"
  if [[ "$python_path" == "$prefix"/* && "$python3_path" == "$prefix"/* ]]; then
    printf 'active'
  else
    printf 'split'
  fi
}

versioned_python_in_prefix() {
  local prefix="$1" candidate name
  [[ -d "$prefix/bin" ]] || return 1
  for candidate in "$prefix"/bin/python3.*; do
    [[ -x "$candidate" ]] || continue
    name="$(basename "$candidate")"
    [[ "$name" =~ ^python3\.[0-9]+$ ]] || continue
    printf '%s' "$candidate"
    return 0
  done
  return 1
}

jq_available() {
  command -v jq >/dev/null 2>&1
}

conda_env_paths() {
  local output
  if jq_available; then
    output="$(run_probe conda env list --json 2>/dev/null)" || return 1
    printf '%s' "$output" | jq -er '.envs | arrays | .[]' 2>/dev/null
  else
    output="$(run_probe conda env list 2>/dev/null)" || return 1
    printf '%s\n' "$output" | awk 'NF && $1 !~ /^#/ {print $NF}'
  fi
}

current_command_resolution() {
  command -v python 2>/dev/null || printf '%s\n' '-'
  command -v python3 2>/dev/null || printf '%s\n' '-'
}

login_shell_resolution() {
  run_probe zsh -lic 'printf "%s\n" "$(command -v python 2>/dev/null || printf -)" "$(command -v python3 2>/dev/null || printf -)"'
}

conda_env_size() {
  local output rc
  output="$(run_local_probe du -sm "$1" 2>/dev/null)"; rc=$?
  if (( rc == 0 )); then
    output="$(printf '%s\n' "$output" | awk 'NR==1 && $1 ~ /^[0-9]+$/ {print $1 " MiB"}')"
  fi
  printf '%s' "${output:-size unavailable}"
}

# brew_dependency_state <formula> <autoremove-list> <requested-list> — trust
# Homebrew's ownership model instead of inferring removability from versions.
brew_dependency_state() {
  local formula="$1" autoremove="$2" requested="$3"
  if printf '%s\n' "$autoremove" | grep -Fxq "$formula"; then
    printf 'orphaned\tlisted by brew autoremove --dry-run'
  elif printf '%s\n' "$requested" | grep -Fxq "$formula"; then
    printf 'user-managed\texplicitly installed'
  else
    printf 'required\tretained as an installed dependency'
  fi
}

# summarize_overlap reads "manager|version" records. Multiple providers of
# one series are an overlap to explain, not proof that any install is removable.
summarize_overlap() {
  local records instances
  records="$(cat)"
  printf '%s\n' "$records" | \
    awk -F'|' 'NF>=2{split($1,m,":"); split($2,v,"."); if(m[1] && v[1] && v[2]) print m[1] "|" v[1] "." v[2]}' | sort -u | \
    awk -F'|' '{ managers[$2] = managers[$2] (managers[$2] ? ", " : "") $1; count[$2]++ }
      END { for (mm in count) print count[mm] "|" mm "|" managers[mm] }' | \
    sort -t'|' -k1,1rn -k2,2 | while IFS='|' read -r n mm managers; do
    if (( n > 1 )); then
      warn "Python $mm has $n managed providers ($managers) — review purpose and consumers; do not remove by version count alone."
      instances="$(printf '%s\n' "$records" | awk -F'|' -v wanted="$mm" '
        NF>=2 { split($2,v,"."); series=v[1] "." v[2] }
        series == wanted { printf "%s%s (%s)", separator, $1, $2; separator=", " }')"
      [[ -n "$instances" ]] && row "Instances: $instances"
    else
      ok "Python $mm — one discovered provider ($managers)."
    fi
  done
}

# ---------------------------------------------------------------------------
# main — the actual report (only runs when executed, not when sourced).
# ---------------------------------------------------------------------------
main() {
  local uv_overlap_records="" brew_overlap_records="" inventory_incomplete=0
  echo "${BOLD}Python Environment Report${RESET}  ${DIM}$(date '+%Y-%m-%d %H:%M')${RESET}"
  [[ "$PROBE_IMPL" == "none" ]] && warn "No timeout utility available; probes will run without timeout protection"

  # --- 1. The interpreter your shell actually uses ---
  info "Active command resolution"
  if command -v python3 >/dev/null 2>&1; then
    local active; active="$(command -v python3)"
    ok "python3 -> $(realpath_p "$active")  ${DIM}($(ver python3))${RESET}"
  else
    warn "No python3 found on PATH"
  fi
  if command -v python >/dev/null 2>&1; then
    ok "python  -> $(realpath_p "$(command -v python)")  ${DIM}($(ver python))${RESET}"
  fi
  local command_name identity executable version implementation machine prefix base_prefix
  for command_name in python python3; do
    command -v "$command_name" >/dev/null 2>&1 || continue
    identity="$(interpreter_identity "$(command -v "$command_name")" 2>/dev/null || true)"
    IFS='|' read -r executable version implementation machine prefix base_prefix <<< "$identity"
    [[ -n "$identity" ]] || { warn "$command_name metadata probe failed"; continue; }
    row "$command_name metadata: $implementation $version $machine"
    [[ "$prefix" != "$base_prefix" ]] && row "  virtual environment: $prefix (base: $base_prefix)"
  done
  if [[ -n "${VIRTUAL_ENV:-}" ]]; then
    ok "Active virtualenv: ${VIRTUAL_ENV/#$HOME/~}"
  fi
  if [[ -n "${CONDA_DEFAULT_ENV:-}" ]]; then
    ok "Active conda env:  ${CONDA_DEFAULT_ENV}"
  fi

  # --- 2. Every python3 on PATH (shadowing order) ---
  info "All 'python3' on current-process PATH (first one wins)"
  local seen_path=0 entry bin seen_bins="" canonical
  while IFS= read -r entry; do
    bin="$entry/python3"; [[ -x "$bin" ]] || continue
    canonical="$(realpath_p "$bin" 2>/dev/null || printf '%s' "$bin")"
    printf '%s\n' "$seen_bins" | grep -Fqx "$canonical" && continue
    seen_bins="${seen_bins}${seen_bins:+$'\n'}${canonical}"
    printf '     %s  %s(%s)%s\n' "$bin" "$DIM" "$(ver "$bin" || printf 'unknown')" "$RESET"
    seen_path=1
  done < <(printf '%s' "$PATH" | tr ':' '\n')
  (( seen_path )) || row "(none)"

  if [[ "${PY_ENV_REPORT_LOGIN_SHELL:-0}" == "1" ]]; then
    local login_resolution login_rc current_resolution
    current_resolution="$(current_command_resolution | paste -sd '|' -)"
    login_resolution="$(login_shell_resolution 2>/dev/null)"; login_rc=$?
    if (( login_rc == 0 )); then
      login_resolution="$(printf '%s\n' "$login_resolution" | paste -sd '|' -)"
      [[ "$login_resolution" == "$current_resolution" ]] || warn "Login-shell resolution differs: ${login_resolution/|/, }"
    else
      warn "Login-shell resolution probe unavailable (status $login_rc)"
    fi
  fi

  info "PATH health"
  local path_issues
  path_issues="$(path_diagnostics)"
  if [[ -z "$path_issues" ]]; then
    ok "No duplicate or stale PATH entries detected"
  else
    while IFS=$'\t' read -r kind path; do
      [[ "$kind" == "duplicate" ]] && warn "Duplicate PATH entry: $path"
      [[ "$kind" == "missing" ]] && warn "Missing PATH directory: $path"
    done <<< "$path_issues"
  fi

  # --- 3. uv (package/version manager) + its managed interpreters ---
  info "uv"
  if command -v uv >/dev/null 2>&1; then
    ok "uv installed: $(uv --version 2>/dev/null)"
    local uv_output uv_state uv_result
    uv_result="$(uv_inventory)"
    uv_state="$(printf '%s\n' "$uv_result" | head -1)"
    uv_output="$(printf '%s\n' "$uv_result" | tail -n +2)"
    row "${BOLD}uv-managed interpreters:${RESET}"
    if [[ "$uv_state" == "success" ]]; then
      [[ -n "$uv_output" ]] && printf '%s\n' "$uv_output" | sed 's/^/       /' || row "  (none)"
      uv_overlap_records="$(printf '%s\n' "$uv_output" | awk '{ split($1,a,"-"); split(a[2],v,"."); if (v[1] && v[2]) print "uv:" $1 "|" a[2] }' | sort -u)"
    else
      warn "Could not inventory uv-managed interpreters: $(printf '%s' "$uv_output" | tail -1)"
      inventory_incomplete=1
      local uv_dir
      uv_dir="$(uv python dir 2>/dev/null || true)"
      [[ -n "$uv_dir" ]] && row "Managed directory for manual review: $uv_dir"
    fi
  else
    warn "uv not installed — run ./install.sh (or: brew install uv)"
  fi
  announce_report_budget_exhaustion

  # --- 4. Homebrew pythons (and why they're here) ---
  info "Homebrew pythons"
  if command -v brew >/dev/null 2>&1; then
    # macOS ships bash 3.2 (no mapfile), so read the list with a while loop.
    local brew_py_found=0 p state detail prefix pybin version brew_autoremove brew_requested brew_formulae formulae_rc=0 auto_rc=0 requested_rc=0
    brew_formulae="$(run_probe brew list --formula 2>/dev/null)" || formulae_rc=$?
    if (( formulae_rc != 0 )); then
      warn "Homebrew Python inventory failed or timed out (status $formulae_rc)"
      inventory_incomplete=1
    fi
    brew_autoremove="$(run_probe brew autoremove --dry-run 2>/dev/null)" || auto_rc=$?
    brew_requested="$(run_probe brew leaves --installed-on-request 2>/dev/null)" || requested_rc=$?
    while IFS= read -r p; do
      [[ -z "$p" ]] && continue
      brew_py_found=1
      prefix="$(run_probe brew --prefix "$p" 2>/dev/null || true)"
      pybin=""; [[ -n "$prefix" ]] && pybin="$(versioned_python_in_prefix "$prefix" || true)"
      version=""; [[ -n "$pybin" ]] && version="$(ver "$pybin")"
      [[ -n "$version" ]] && brew_overlap_records="${brew_overlap_records}${brew_overlap_records:+$'\n'}homebrew:${p}|${version}"
      if (( auto_rc == 0 && requested_rc == 0 )); then
        IFS=$'\t' read -r state detail <<< "$(brew_dependency_state "$p" "$brew_autoremove" "$brew_requested")"
      else
        state="unknown"; detail="Homebrew ownership probes unavailable (autoremove=$auto_rc, requested=$requested_rc)"
      fi
      case "$state" in
        required)     row "${GREEN}keep${RESET}         $p ${version:+($version)}  ${DIM}$detail${RESET}" ;;
        user-managed) row "${GREEN}user-managed${RESET} $p ${version:+($version)}  ${DIM}$detail${RESET}" ;;
        orphaned)     row "${YELLOW}orphaned${RESET}     $p ${version:+($version)}  ${DIM}$detail; review before removal${RESET}" ;;
        *)         row "${YELLOW}unknown${RESET}   $p ${version:+($version)}  ${DIM}$detail; no removal advice${RESET}" ;;
      esac
    done < <(printf '%s\n' "$brew_formulae" | grep -E '^python@' || true)
    (( brew_py_found )) || { (( formulae_rc == 0 )) && row "(none installed via Homebrew)"; }
  else
    warn "Homebrew not found"
  fi
  announce_report_budget_exhaustion

  # --- 5. conda / miniconda environments ---
  info "conda environments"
  if command -v conda >/dev/null 2>&1; then
    local conda_root conda_paths conda_rc=0
    conda_root="$(run_probe conda info --base 2>/dev/null || true)"
    conda_paths="$(conda_env_paths)" || conda_rc=$?
    if (( conda_rc != 0 )); then
      warn "Conda environment inventory failed or returned invalid JSON"
      inventory_incomplete=1
    fi
    printf '%s\n' "$conda_paths" | while IFS= read -r envpath; do
      [[ -z "$envpath" ]] && continue
      local name; name="$(basename "$envpath")"
      [[ -n "$conda_root" && "$envpath" == "$conda_root" ]] && name="base"
      local pybin="$envpath/bin/python"
      local v="-" size=""; [[ -x "$pybin" ]] && v="$(ver "$pybin")"
      if [[ "${PY_ENV_REPORT_SIZES:-0}" == "1" ]]; then
        size="$(conda_env_size "$envpath")"
      fi
      row "$name  ${DIM}($v${size:+, $size})${RESET}  ${DIM}$envpath${RESET}"
    done
    if [[ -n "${CONDA_PREFIX:-}" ]]; then
      local resolved_python resolved_python3
      resolved_python="$(command -v python 2>/dev/null || true)"
      resolved_python3="$(command -v python3 2>/dev/null || true)"
      if [[ "$(conda_resolution_state "$CONDA_PREFIX" "$resolved_python" "$resolved_python3")" == "active" ]]; then
        ok "Active conda environment supplies both python and python3"
      else
        warn "Active conda environment does not control both commands: python=${resolved_python:-missing}, python3=${resolved_python3:-missing}"
        row "Review PATH ordering before changing or removing any interpreter."
      fi
    fi
  else
    row "(conda not installed)"
  fi
  announce_report_budget_exhaustion

  # --- 6. python.org framework installs (manual installers) ---
  info "python.org framework installs"
  local fw="/Library/Frameworks/Python.framework/Versions" d b
  if [[ -d "$fw" ]]; then
    for d in "$fw"/*; do
      b="$(basename "$d")"
      [[ "$b" == "Current" ]] && continue
      [[ -x "$d/bin/python3" ]] || continue
      row "${YELLOW}review${RESET} $d  ${DIM}($(ver "$d/bin/python3"))${RESET}"
    done
    row "${DIM}Manual .pkg installs are review candidates only after checking projects and environments.${RESET}"
  else
    row "(none)"
  fi

  # --- 7. macOS system Python ---
  info "macOS system Python"
  if [[ -x /usr/bin/python3 ]]; then
    ok "/usr/bin/python3  ${DIM}($(ver /usr/bin/python3))${RESET}  — Apple-managed, do NOT remove"
  else
    row "(no /usr/bin/python3)"
  fi

  # --- Installation overlap summary ---
  info "Installation overlap (not automatic redundancy)"
  {
    printf '%s\n' "$brew_overlap_records"
    [[ -d "$fw" ]] && for d in "$fw"/*/bin/python3; do [[ -x "$d" ]] && printf 'python.org:%s|%s\n' "$(basename "$(dirname "$(dirname "$d")")")" "$(ver "$d")"; done
    if command -v conda >/dev/null 2>&1; then
      printf '%s\n' "$conda_paths" | while IFS= read -r p; do
        local instance
        instance="$(basename "$p")"
        [[ -n "$conda_root" && "$p" == "$conda_root" ]] && instance="base"
        [[ -x "$p/bin/python" ]] && printf 'conda:%s|%s\n' "$instance" "$(ver "$p/bin/python")"
      done
    fi
    printf '%s\n' "$uv_overlap_records"
    [[ -x /usr/bin/python3 ]] && printf 'apple:system|%s\n' "$(ver /usr/bin/python3)"
  } | summarize_overlap
  (( inventory_incomplete )) && warn "Overlap summary is partial because one or more inventories were unavailable."

  echo
  echo "${DIM}Read-only audit. Nothing was installed or removed. Prefer 'uv' for new"
  echo "project envs: uv venv && uv sync${RESET}"
}

# Run main() only when executed or piped, not when sourced by the test suite.
if ! (return 0 2>/dev/null); then
  main "$@"
fi
