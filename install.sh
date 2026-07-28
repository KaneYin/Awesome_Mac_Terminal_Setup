#!/usr/bin/env bash
#
# install.sh — Install the Awesome Mac Terminal Setup toolchain.
#
# Installs everything documented in the README via Homebrew, deploys the
# bundled config files (backing up any existing ones with a timestamp), then
# lets you pick which AI coding CLIs to install (Claude Code, Codex, Gemini
# CLI) via an arrow-key + space menu, and optionally installs a set of Claude
# Code agent skills. Safe to re-run: Homebrew skips already-installed formulae
# and unchanged configs are left in place.
#
# Usage:
#   ./install.sh                 # interactive: AI CLI menu + skills prompt
#   ./install.sh --all           # install all AI CLIs and skills, no prompts
#   ./install.sh --no-ai         # skip the AI CLIs and skills entirely
#
set -euo pipefail

# Directory this script lives in, so we can find the sibling configs/ dir even
# when invoked from elsewhere. Empty if the script was streamed (curl | bash).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"

# ---------------------------------------------------------------------------
# Flags
# ---------------------------------------------------------------------------
INSTALL_ALL=0   # --all  : install every AI CLI + skills without prompting
SKIP_AI=0       # --no-ai: skip AI CLIs and skills entirely
for arg in "$@"; do
  case "$arg" in
    --all)   INSTALL_ALL=1 ;;
    --no-ai) SKIP_AI=1 ;;
    -h|--help)
      sed -n '3,14p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "Unknown option: $arg (use --all, --no-ai, or --help)" >&2; exit 1 ;;
  esac
done

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------
BOLD=$'\033[1m'; BLUE=$'\033[34m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RED=$'\033[31m'; RESET=$'\033[0m'

info()  { printf '%s==>%s %s\n' "${BLUE}${BOLD}" "$RESET" "$*"; }
ok()    { printf '%s ok%s %s\n' "${GREEN}${BOLD}" "$RESET" "$*"; }
warn()  { printf '%swarn%s %s\n' "${YELLOW}${BOLD}" "$RESET" "$*"; }
die()   { printf '%serror%s %s\n' "${RED}${BOLD}" "$RESET" "$*" >&2; exit 1; }

# confirm "Question?"  -> returns 0 for yes, 1 for no.
# Honors --all (auto-yes) and --no-ai (auto-no). Defaults to no on empty input
# or when stdin is not a TTY (e.g. piped via curl | bash).
confirm() {
  local prompt="$1" reply
  (( INSTALL_ALL )) && return 0
  (( SKIP_AI ))     && return 1
  if [[ ! -t 0 ]]; then return 1; fi
  printf '%s%s%s [y/N] ' "$BOLD" "$prompt" "$RESET"
  read -r reply
  [[ "$reply" =~ ^[Yy]$ ]]
}

# multiselect "Title" item1 item2 ...
#   Interactive checkbox menu: ↑/↓ (or k/j) to move, Space to toggle,
#   Enter to confirm. Sets the global array MULTISELECT_RESULT to the
#   indexes (0-based) of the chosen items. Requires an interactive TTY.
MULTISELECT_RESULT=()
multiselect() {
  local title="$1"; shift
  local options=("$@")
  local count=${#options[@]}
  local selected=() cursor=0 i key
  for ((i = 0; i < count; i++)); do selected[i]=0; done

  # Restore the terminal no matter how we leave the function.
  local saved_stty; saved_stty="$(stty -g)"
  cleanup() { stty "$saved_stty" 2>/dev/null; printf '\033[?25h'; }
  trap cleanup RETURN
  printf '\033[?25l'   # hide cursor

  printf '%s%s%s\n' "$BOLD" "$title" "$RESET"
  printf '  (↑/↓ move · space toggle · enter confirm)\n'

  while true; do
    for ((i = 0; i < count; i++)); do
      local box="[ ]"; (( selected[i] )) && box="[${GREEN}x${RESET}]"
      if (( i == cursor )); then
        printf '%s> %s %s%s\n' "$BOLD" "$box" "${options[i]}" "$RESET"
      else
        printf '  %s %s\n'      "$box" "${options[i]}"
      fi
    done

    stty -echo -icanon time 0 min 1
    IFS= read -r -n1 key
    if [[ $key == $'\033' ]]; then          # escape sequence (arrow keys)
      read -r -n2 -t 0.01 key || true
      case "$key" in
        '[A') (( cursor = (cursor - 1 + count) % count )) ;;  # up
        '[B') (( cursor = (cursor + 1) % count )) ;;          # down
      esac
    else
      case "$key" in
        k) (( cursor = (cursor - 1 + count) % count )) ;;
        j) (( cursor = (cursor + 1) % count )) ;;
        ' ') selected[cursor]=$(( selected[cursor] ^ 1 )) ;;
        '') break ;;                          # Enter
      esac
    fi

    printf '\033[%dA' "$count"               # move cursor back up to redraw
  done

  MULTISELECT_RESULT=()
  for ((i = 0; i < count; i++)); do
    (( selected[i] )) && MULTISELECT_RESULT+=("$i")
  done
}

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------
[[ "$(uname -s)" == "Darwin" ]] || die "This setup targets macOS. Detected: $(uname -s)"

# ---------------------------------------------------------------------------
# 1. Homebrew
# ---------------------------------------------------------------------------
if ! command -v brew >/dev/null 2>&1; then
  info "Homebrew not found — installing it"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  # Make brew available in this shell session (Apple Silicon vs Intel paths).
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
else
  ok "Homebrew already installed"
fi

command -v brew >/dev/null 2>&1 || die "brew is still not on PATH; open a new terminal and re-run."

info "Updating Homebrew"
brew update

# ---------------------------------------------------------------------------
# 2. Formulae (CLI tools) — everything listed in the README
# ---------------------------------------------------------------------------
FORMULAE=(
  starship                  # cross-shell prompt
  zsh-autosuggestions       # fish-like suggestions
  zsh-syntax-highlighting   # live command coloring
  zsh-completions           # extended completions
  atuin                     # shell history with fuzzy search + sync
  fzf                       # fuzzy finder
  eza                       # modern ls
  bat                       # modern cat
  fd                        # modern find
  ripgrep                   # modern grep (rg)
  zoxide                    # smart cd
  btop                      # system monitor
  lazygit                   # git TUI
  git-delta                 # git diff viewer (delta)
  fnm                       # node version manager
  uv                        # fast python package + version manager
  tldr                      # simplified man pages
  jq                        # json processor
  glow                      # markdown renderer (md alias)
)

# ---------------------------------------------------------------------------
# 3. Casks (apps + fonts)
# ---------------------------------------------------------------------------
CASKS=(
  ghostty                       # GPU-accelerated terminal emulator
  font-jetbrains-mono-nerd-font # JetBrainsMono Nerd Font (icons + ligatures)
)

install_formula() {
  local f="$1"
  if brew list --formula "$f" >/dev/null 2>&1; then
    ok "$f already installed"
  else
    info "Installing $f"
    brew install "$f"
  fi
}

install_cask() {
  local c="$1"
  if brew list --cask "$c" >/dev/null 2>&1; then
    ok "$c already installed"
  else
    info "Installing $c"
    brew install --cask "$c"
  fi
}

info "Installing CLI tools"
for f in "${FORMULAE[@]}"; do install_formula "$f"; done

info "Installing apps and fonts"
for c in "${CASKS[@]}"; do install_cask "$c"; done

# ---------------------------------------------------------------------------
# 4. Deploy config files
# ---------------------------------------------------------------------------
# Copies the bundled configs into place. Existing files are backed up with a
# timestamp before being replaced; identical files are left untouched.
#
# deploy_config <src-relative-to-configs/> <dest-absolute>
deploy_config() {
  local src="$SCRIPT_DIR/configs/$1" dest="$2"

  if [[ -z "$SCRIPT_DIR" || ! -f "$src" ]]; then
    warn "Config not found: configs/$1 (skipping ${dest/#$HOME/~})"
    return 0
  fi

  mkdir -p "$(dirname "$dest")"

  if [[ -f "$dest" ]] && cmp -s "$src" "$dest"; then
    ok "${dest/#$HOME/~} already up to date"
    return 0
  fi

  if [[ -e "$dest" ]]; then
    local backup="${dest}.bak.$(date +%s)"
    mv "$dest" "$backup"
    warn "Backed up existing ${dest/#$HOME/~} -> ${backup/#$HOME/~}"
  fi

  cp "$src" "$dest"
  ok "Deployed ${dest/#$HOME/~}"
}

info "Deploying config files"
deploy_config "zshrc"             "$HOME/.zshrc"
deploy_config "starship.toml"     "$HOME/.config/starship.toml"
deploy_config "ghostty.save"      "$HOME/.config/ghostty.save"
deploy_config "gitconfig"         "$HOME/.gitconfig"
deploy_config "atuin/config.toml" "$HOME/.config/atuin/config.toml"
warn "Set your git identity if you haven't:  git config --global user.name/user.email"

# ---------------------------------------------------------------------------
# 5. AI coding CLIs (Claude Code, Codex, Gemini CLI) — user's choice
# ---------------------------------------------------------------------------
install_claude_code() {
  # Claude Code ships its own native installer (no Node required).
  if command -v claude >/dev/null 2>&1; then
    ok "Claude Code CLI already installed"
  else
    info "Installing Claude Code CLI"
    curl -fsSL https://claude.ai/install.sh | bash
  fi
}

install_codex() {
  # Codex CLI is distributed as a Homebrew cask.
  if command -v codex >/dev/null 2>&1; then
    ok "Codex CLI already installed"
  else
    install_cask codex
  fi
}

install_gemini() {
  # Gemini CLI is available as a Homebrew formula.
  if command -v gemini >/dev/null 2>&1; then
    ok "Gemini CLI already installed"
  else
    install_formula gemini-cli
  fi
}

# Deploy the bundled Claude Code theme (file only; activate it with /theme or
# by setting "theme": "custom:separated" in ~/.claude/settings.json).
install_claude_theme() {
  deploy_config "claude/themes/separated.json" "$HOME/.claude/themes/separated.json"
  info 'Activate the theme inside Claude Code with /theme (custom:separated).'
}

# Decide which AI CLIs to install: --all selects everything, --no-ai selects
# nothing, a non-interactive shell is skipped, otherwise show the menu.
CLAUDE_REQUESTED=0
WANT_CLAUDE=0; WANT_CODEX=0; WANT_GEMINI=0

if (( SKIP_AI )); then
  warn "Skipping AI CLIs (--no-ai)"
elif (( INSTALL_ALL )); then
  WANT_CLAUDE=1; WANT_CODEX=1; WANT_GEMINI=1
elif [[ ! -t 0 ]]; then
  warn "Non-interactive shell — skipping the AI CLI menu."
  warn "Re-run ./install.sh in a terminal, or use --all, to install AI CLIs."
else
  multiselect "AI coding CLIs — choose which to install:" \
    "Claude Code" "Codex" "Gemini CLI"
  for idx in "${MULTISELECT_RESULT[@]}"; do
    case "$idx" in
      0) WANT_CLAUDE=1 ;;
      1) WANT_CODEX=1 ;;
      2) WANT_GEMINI=1 ;;
    esac
  done
fi

if (( WANT_CLAUDE )); then
  install_claude_code
  install_claude_theme
  CLAUDE_REQUESTED=1
fi
(( WANT_CODEX ))  && install_codex
(( WANT_GEMINI )) && install_gemini

# ---------------------------------------------------------------------------
# 6. Claude Code agent skills (plugins)
# ---------------------------------------------------------------------------
# Skills are installed as Claude Code plugins. This requires the `claude` CLI,
# so we only offer it when Claude Code is available.
install_claude_skills() {
  local marketplace="$1" plugin="$2"
  info "Installing skill: $plugin"
  # Register the marketplace (idempotent) then install the plugin.
  claude plugin marketplace add "$marketplace" >/dev/null 2>&1 || true
  if claude plugin install "$plugin" 2>/dev/null; then
    ok "$plugin installed"
  else
    warn "Could not auto-install $plugin. Run this inside Claude Code:"
    printf '      /plugin install %s\n' "$plugin"
  fi
}

if (( SKIP_AI )); then
  : # nothing to do
elif command -v claude >/dev/null 2>&1 && { (( CLAUDE_REQUESTED )) || (( INSTALL_ALL )); }; then
  if confirm "Install Claude Code agent skills (superpowers, andrej-karpathy-skills)?"; then
    install_claude_skills "claude-plugins-official" "superpowers@claude-plugins-official"
    install_claude_skills "karpathy-skills"         "andrej-karpathy-skills@karpathy-skills"
  fi
fi

# ---------------------------------------------------------------------------
# 7. Python environment report
# ---------------------------------------------------------------------------
# uv is now installed, so surface the current Python picture (interpreters,
# conda/brew/uv installs, and any redundant copies). Read-only.
if [[ -n "$SCRIPT_DIR" && -x "$SCRIPT_DIR/python-env-report.sh" ]]; then
  info "Detecting your Python environment"
  "$SCRIPT_DIR/python-env-report.sh" || warn "Python env report failed (non-fatal)."
fi

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo
ok "All tools installed and configs deployed."
cat <<'EOF'

Next steps:
  • Configs were deployed to ~/.zshrc, ~/.config/starship.toml,
    ~/.config/ghostty.save, ~/.gitconfig, ~/.config/atuin/config.toml.
    Any pre-existing file was backed up as <file>.bak.<timestamp>.
  • Set your git identity (the deployed .gitconfig omits it on purpose):
      git config --global user.name  "Your Name"
      git config --global user.email "you@example.com"
  • Confirm Ghostty's font is "JetBrainsMono Nerd Font".
  • Restart your terminal (or run: exec zsh) to load everything.
  • Authenticate whichever AI CLIs you installed:
      claude   |   codex   |   gemini
  • If you installed Claude Code, activate the bundled theme with /theme
    (custom:separated).
  • If a skill failed to auto-install, open Claude Code and run, e.g.:
      /plugin install superpowers@claude-plugins-official
      /plugin install andrej-karpathy-skills@karpathy-skills
  • Re-check your Python setup anytime with:  ./python-env-report.sh
EOF
