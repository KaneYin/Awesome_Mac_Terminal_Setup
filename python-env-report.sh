#!/usr/bin/env bash
#
# python-env-report.sh — Detect and report the Python environment on this Mac.
#
# Inventories every Python interpreter the shell can see (active PATH pick,
# uv-managed, Homebrew, conda, python.org framework, macOS system), shows conda
# environments, and flags likely-redundant installs. Read-only: it inspects and
# reports, it never installs or removes anything.
#
# Usage:
#   ./python-env-report.sh
#
set -uo pipefail   # no -e: probes are allowed to fail; we handle that per-check

# ---------------------------------------------------------------------------
# Output helpers (mirrors install.sh)
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

echo "${BOLD}Python Environment Report${RESET}  ${DIM}$(date '+%Y-%m-%d %H:%M')${RESET}"

# ---------------------------------------------------------------------------
# 1. The interpreter your shell actually uses
# ---------------------------------------------------------------------------
info "Active interpreter (what 'python3' runs)"
if command -v python3 >/dev/null 2>&1; then
  active="$(command -v python3)"
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

# ---------------------------------------------------------------------------
# 2. Every python3 on PATH (shadowing order)
# ---------------------------------------------------------------------------
info "All 'python3' on PATH (first one wins)"
seen_path=0
while IFS= read -r line; do
  [[ "$line" == *is* ]] || continue
  bin="${line##* }"
  [[ -x "$bin" ]] || continue
  printf '     %s  %s(%s)%s\n' "$bin" "$DIM" "$(ver "$bin")" "$RESET"
  seen_path=1
done < <(type -a python3 2>/dev/null)
(( seen_path )) || row "(none)"

# ---------------------------------------------------------------------------
# 3. uv (package/version manager) + its managed interpreters
# ---------------------------------------------------------------------------
info "uv"
if command -v uv >/dev/null 2>&1; then
  ok "uv installed: $(uv --version 2>/dev/null)"
  if uv python list --only-installed >/dev/null 2>&1; then
    row "${BOLD}Installed interpreters uv can see:${RESET}"
    uv python list --only-installed 2>/dev/null | sed 's/^/       /'
  else
    row "${BOLD}Installed interpreters uv can see:${RESET}"
    uv python list 2>/dev/null | grep -v '<download available>' | sed 's/^/       /'
  fi
else
  warn "uv not installed — run ./install.sh (or: brew install uv)"
fi

# ---------------------------------------------------------------------------
# 4. Homebrew pythons (and why they're here)
# ---------------------------------------------------------------------------
info "Homebrew pythons"
if command -v brew >/dev/null 2>&1; then
  # macOS ships bash 3.2 (no mapfile), so read the list with a while loop.
  brew_py_found=0
  while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    brew_py_found=1
    # Which installed formulae depend on this python? If any, it's NOT redundant.
    deps="$(brew uses --installed "$p" 2>/dev/null | tr '\n' ' ')"
    if [[ -n "${deps// }" ]]; then
      row "${GREEN}keep${RESET}  $p  ${DIM}dependency of:${RESET} ${deps}"
    else
      row "${YELLOW}review${RESET} $p  ${DIM}no formula depends on it (top-level)${RESET}"
    fi
  done < <(brew list --formula 2>/dev/null | grep -E '^python@' || true)
  (( brew_py_found )) || row "(none installed via Homebrew)"
else
  warn "Homebrew not found"
fi

# ---------------------------------------------------------------------------
# 5. conda / miniconda environments
# ---------------------------------------------------------------------------
info "conda environments"
if command -v conda >/dev/null 2>&1; then
  conda env list 2>/dev/null | grep -v '^#' | while read -r name _marker path; do
    [[ -z "$name" ]] && continue
    # `conda env list` prints "name  *  /path" or "name  /path".
    envpath="$path"; [[ -z "$envpath" ]] && envpath="$_marker"
    pybin="$envpath/bin/python"
    v="-"; [[ -x "$pybin" ]] && v="$(ver "$pybin")"
    sz="$(du -sh "$envpath" 2>/dev/null | awk '{print $1}')"
    row "$name  ${DIM}($v, ${sz:-?})${RESET}  ${DIM}$envpath${RESET}"
  done
  warn "conda 'base' auto-activation shadows other python3s. Disable with:"
  row "  conda config --set auto_activate_base false"
else
  row "(conda not installed)"
fi

# ---------------------------------------------------------------------------
# 6. python.org framework installs (manual installers)
# ---------------------------------------------------------------------------
info "python.org framework installs"
fw="/Library/Frameworks/Python.framework/Versions"
if [[ -d "$fw" ]]; then
  for d in "$fw"/*; do
    b="$(basename "$d")"
    [[ "$b" == "Current" ]] && continue
    [[ -x "$d/bin/python3" ]] || continue
    row "${YELLOW}review${RESET} $d  ${DIM}($(ver "$d/bin/python3"))${RESET}"
  done
  row "${DIM}These are manual .pkg installs — often redundant if conda/brew/uv already"
  row "provide the same version. Remove with: sudo rm -rf $fw/<ver>${RESET}"
else
  row "(none)"
fi

# ---------------------------------------------------------------------------
# 7. macOS system Python
# ---------------------------------------------------------------------------
info "macOS system Python"
if [[ -x /usr/bin/python3 ]]; then
  ok "/usr/bin/python3  ${DIM}($(ver /usr/bin/python3))${RESET}  — Apple-managed, do NOT remove"
else
  row "(no /usr/bin/python3)"
fi

# ---------------------------------------------------------------------------
# Redundancy summary
# ---------------------------------------------------------------------------
info "Redundancy check"
# Collect distinct interpreter versions across sources to spot duplicated minors.
tmp="$(mktemp)"
for b in /usr/bin/python3 /usr/local/bin/python3 /opt/homebrew/bin/python3; do
  [[ -x "$b" ]] && ver "$b" >> "$tmp"
done
[[ -d "$fw" ]] && for d in "$fw"/*/bin/python3; do [[ -x "$d" ]] && ver "$d" >> "$tmp"; done
command -v conda >/dev/null 2>&1 && conda env list 2>/dev/null | grep -v '^#' | awk '{print $NF}' | \
  while read -r p; do [[ -x "$p/bin/python" ]] && ver "$p/bin/python"; done >> "$tmp"

if [[ -s "$tmp" ]]; then
  # Group by major.minor to highlight duplicated series (e.g. many 3.13.x).
  awk -F. '{print $1"."$2}' "$tmp" | sort | uniq -c | sort -rn | while read -r n mm; do
    if (( n > 1 )); then
      warn "Python $mm provided by $n separate installs — consolidate if you can."
    else
      ok "Python $mm — single install."
    fi
  done
fi
rm -f "$tmp"

echo
echo "${DIM}Read-only report. Nothing was installed or removed. Prefer 'uv' for new"
echo "project envs: uv venv && uv sync${RESET}"
