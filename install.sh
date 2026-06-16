#!/usr/bin/env bash
#
# install.sh — Install the Awesome Mac Terminal Setup toolchain.
#
# Installs everything documented in the README via Homebrew, plus the
# Claude Code CLI and the Codex CLI. Safe to re-run: Homebrew skips
# already-installed formulae and the script never overwrites your configs.
#
# Usage:
#   ./install.sh
#
set -euo pipefail

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------
BOLD=$'\033[1m'; BLUE=$'\033[34m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RED=$'\033[31m'; RESET=$'\033[0m'

info()  { printf '%s==>%s %s\n' "${BLUE}${BOLD}" "$RESET" "$*"; }
ok()    { printf '%s ok%s %s\n' "${GREEN}${BOLD}" "$RESET" "$*"; }
warn()  { printf '%swarn%s %s\n' "${YELLOW}${BOLD}" "$RESET" "$*"; }
die()   { printf '%serror%s %s\n' "${RED}${BOLD}" "$RESET" "$*" >&2; exit 1; }

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
  tldr                      # simplified man pages
  jq                        # json processor
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
# 4. Claude Code CLI + Codex CLI
# ---------------------------------------------------------------------------
# Claude Code ships its own native installer (no Node required).
if command -v claude >/dev/null 2>&1; then
  ok "Claude Code CLI already installed"
else
  info "Installing Claude Code CLI"
  curl -fsSL https://claude.ai/install.sh | bash
fi

# Codex CLI is distributed as a Homebrew cask.
if command -v codex >/dev/null 2>&1; then
  ok "Codex CLI already installed"
else
  install_cask codex
fi

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo
ok "All tools installed."
cat <<'EOF'

Next steps:
  • This script installs tools only — it does not touch your config files.
    Copy the configs referenced in the README into place:
      ~/.zshrc, ~/.config/starship.toml, ~/.config/ghostty.save,
      ~/.gitconfig, ~/.config/atuin/config.toml
  • Set Ghostty's font to "JetBrainsMono Nerd Font".
  • Restart your terminal (or run: exec zsh) to load everything.
  • Authenticate the CLIs:  claude    and    codex
EOF
