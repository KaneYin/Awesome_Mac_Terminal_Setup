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
  local p="$1"
  while [[ -L "$p" ]]; do
    local t; t="$(readlink "$p")"
    [[ "$t" != /* ]] && t="$(dirname "$p")/$t"
    p="$t"
  done
  printf '%s' "$p"
}

# ver <python-binary> -> "3.13.13" or "" if it won't run.
ver() { "$1" --version 2>&1 | awk '{print $2}'; }

# mm_of "3.13.13" -> "3.13" (major.minor). Empty in -> empty out.
mm_of() { printf '%s' "$1" | awk -F. 'NF>=2{print $1"."$2}'; }

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
  local cache output rc
  cache="$(mktemp -d "${TMPDIR:-/tmp}/python-env-report.XXXXXX" 2>/dev/null || true)"
  if [[ -z "$cache" ]]; then
    printf 'unknown\ncould not create a temporary uv cache'
    return 0
  fi
  output="$(UV_CACHE_DIR="$cache" uv python list --only-installed --managed-python 2>&1)"; rc=$?
  [[ "$cache" == "${TMPDIR:-/tmp}"/python-env-report.* ]] && rm -rf -- "$cache"
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

conda_env_paths() {
  local output
  if command -v jq >/dev/null 2>&1 && output="$(conda env list --json 2>/dev/null)"; then
    printf '%s' "$output" | jq -r '.envs[]' 2>/dev/null
  else
    conda env list 2>/dev/null | grep -v '^#' | awk 'NF{print $NF}'
  fi
}

# brew_dependency_state <formula> — print required/candidate/unknown plus any
# installed dependents. A failed Homebrew probe must never be interpreted as
# dependency data, even if the command happened to write something to stdout.
brew_dependency_state() {
  local formula="$1" output rc
  output="$(brew uses --installed "$formula" 2>/dev/null)"; rc=$?
  if (( rc != 0 )); then
    printf 'unknown\tdependency probe failed'
  elif [[ -n "${output//[$'\t\r\n ']/}" ]]; then
    printf 'required\t%s' "$(printf '%s' "$output" | tr '\n' ' ')"
  else
    printf 'candidate\tno installed Homebrew dependents'
  fi
}

# summarize_overlap reads "manager|version" records. Multiple providers of
# one series are an overlap to explain, not proof that any install is removable.
summarize_overlap() {
  awk -F'[|.]' 'NF>=3{print $1 "|" $2 "." $3}' | sort -u | \
    awk -F'|' '{ managers[$2] = managers[$2] (managers[$2] ? ", " : "") $1; count[$2]++ }
      END { for (mm in count) print count[mm] "|" mm "|" managers[mm] }' | \
    sort -t'|' -k1,1rn -k2,2 | while IFS='|' read -r n mm managers; do
    if (( n > 1 )); then
      warn "Python $mm has $n managed providers ($managers) — review purpose and consumers; do not remove by version count alone."
    else
      ok "Python $mm — one discovered provider ($managers)."
    fi
  done
}

# ---------------------------------------------------------------------------
# main — the actual report (only runs when executed, not when sourced).
# ---------------------------------------------------------------------------
main() {
  echo "${BOLD}Python Environment Report${RESET}  ${DIM}$(date '+%Y-%m-%d %H:%M')${RESET}"

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
  if [[ -n "${VIRTUAL_ENV:-}" ]]; then
    ok "Active virtualenv: ${VIRTUAL_ENV/#$HOME/~}"
  fi
  if [[ -n "${CONDA_DEFAULT_ENV:-}" ]]; then
    ok "Active conda env:  ${CONDA_DEFAULT_ENV}"
  fi

  # --- 2. Every python3 on PATH (shadowing order) ---
  info "All 'python3' on PATH (first one wins)"
  local seen_path=0 line bin
  while IFS= read -r line; do
    [[ "$line" == *is* ]] || continue
    bin="${line##* }"
    [[ -x "$bin" ]] || continue
    printf '     %s  %s(%s)%s\n' "$bin" "$DIM" "$(ver "$bin")" "$RESET"
    seen_path=1
  done < <(type -a python3 2>/dev/null)
  (( seen_path )) || row "(none)"

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
    else
      warn "Could not inventory uv-managed interpreters: $(printf '%s' "$uv_output" | tail -1)"
      local uv_dir
      uv_dir="$(uv python dir 2>/dev/null || true)"
      [[ -n "$uv_dir" ]] && row "Managed directory for manual review: $uv_dir"
    fi
  else
    warn "uv not installed — run ./install.sh (or: brew install uv)"
  fi

  # --- 4. Homebrew pythons (and why they're here) ---
  info "Homebrew pythons"
  if command -v brew >/dev/null 2>&1; then
    # macOS ships bash 3.2 (no mapfile), so read the list with a while loop.
    local brew_py_found=0 p state detail prefix pybin version
    while IFS= read -r p; do
      [[ -z "$p" ]] && continue
      brew_py_found=1
      prefix="$(brew --prefix "$p" 2>/dev/null || true)"
      pybin=""; [[ -n "$prefix" ]] && pybin="$(versioned_python_in_prefix "$prefix" || true)"
      version=""; [[ -n "$pybin" ]] && version="$(ver "$pybin")"
      IFS=$'\t' read -r state detail <<< "$(brew_dependency_state "$p")"
      case "$state" in
        required)  row "${GREEN}keep${RESET}      $p ${version:+($version)}  ${DIM}dependency of:${RESET} $detail" ;;
        candidate) row "${YELLOW}candidate${RESET} $p ${version:+($version)}  ${DIM}$detail; confirm with brew autoremove --dry-run${RESET}" ;;
        *)         row "${YELLOW}unknown${RESET}   $p ${version:+($version)}  ${DIM}$detail; no removal advice${RESET}" ;;
      esac
    done < <(brew list --formula 2>/dev/null | grep -E '^python@' || true)
    (( brew_py_found )) || row "(none installed via Homebrew)"
  else
    warn "Homebrew not found"
  fi

  # --- 5. conda / miniconda environments ---
  info "conda environments"
  if command -v conda >/dev/null 2>&1; then
    local conda_root
    conda_root="$(conda info --base 2>/dev/null || true)"
    conda_env_paths | while IFS= read -r envpath; do
      [[ -z "$envpath" ]] && continue
      local name; name="$(basename "$envpath")"
      [[ -n "$conda_root" && "$envpath" == "$conda_root" ]] && name="base"
      local pybin="$envpath/bin/python"
      local v="-"; [[ -x "$pybin" ]] && v="$(ver "$pybin")"
      local sz; sz="$(du -sh "$envpath" 2>/dev/null | awk '{print $1}')"
      row "$name  ${DIM}($v, ${sz:-?})${RESET}  ${DIM}$envpath${RESET}"
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
    if command -v brew >/dev/null 2>&1; then
      brew list --formula 2>/dev/null | grep -E '^python@' | while read -r p; do
        prefix="$(brew --prefix "$p" 2>/dev/null || true)"
        pybin=""; [[ -n "$prefix" ]] && pybin="$(versioned_python_in_prefix "$prefix" || true)"
        [[ -x "$pybin" ]] && printf 'homebrew|%s\n' "$(ver "$pybin")"
      done
    fi
    [[ -d "$fw" ]] && for d in "$fw"/*/bin/python3; do [[ -x "$d" ]] && printf 'python.org|%s\n' "$(ver "$d")"; done
    if command -v conda >/dev/null 2>&1; then
      conda_env_paths | while IFS= read -r p; do
        [[ -x "$p/bin/python" ]] && printf 'conda|%s\n' "$(ver "$p/bin/python")"
      done
    fi
    if [[ -d "${HOME}/.local/share/uv/python" ]]; then
      for d in "${HOME}/.local/share/uv/python"/cpython-*; do
        [[ -x "$d/bin/python3" ]] && printf 'uv|%s\n' "$(ver "$d/bin/python3")"
      done
    fi
    [[ -x /usr/bin/python3 ]] && printf 'apple|%s\n' "$(ver /usr/bin/python3)"
  } | summarize_overlap

  echo
  echo "${DIM}Read-only audit. Nothing was installed or removed. Prefer 'uv' for new"
  echo "project envs: uv venv && uv sync${RESET}"
}

# Run main() only when executed or piped, not when sourced by the test suite.
if ! (return 0 2>/dev/null); then
  main "$@"
fi
