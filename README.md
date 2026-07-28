# Awesome Mac Terminal Setup

A modern, aesthetic, and productive macOS terminal setup built on **Ghostty + Zsh + Starship**, themed with **Catppuccin Mocha**. Every tool is installed via Homebrew and configured to work together out of the box.

## Quick Install

```bash
git clone https://github.com/<you>/Awesome_Mac_Terminal_Setup.git
cd Awesome_Mac_Terminal_Setup
./install.sh
```

The installer is **safe to re-run** — Homebrew skips already-installed tools, and
any existing config file is **backed up with a timestamp** (`<file>.bak.<unix-ts>`)
before a new one is deployed.

Flags:

| Flag | Effect |
|------|--------|
| *(none)* | Install tools + deploy configs, then show an interactive AI-CLI menu |
| `--all` | Install everything including all AI CLIs and skills, no prompts |
| `--no-ai` | Install tools + configs only; skip AI CLIs and skills |

### What the installer does

1. Installs [**Homebrew**](https://brew.sh) if it's missing.
2. Installs all **CLI tools** (`starship`, `eza`, `bat`, `fd`, `ripgrep`, `zoxide`, `btop`, `lazygit`, `git-delta`, `fnm`, `uv`, `atuin`, `fzf`, `tldr`, `jq`, `glow`, and the zsh plugins).
3. Installs the [**Ghostty**](https://ghostty.org) terminal and the [**JetBrainsMono Nerd Font**](https://www.nerdfonts.com/) cask.
4. **Deploys the config files** below, backing up any existing copies.
5. Shows an **interactive menu** (↑/↓ to move, space to toggle, enter to confirm) to pick which AI coding CLIs to install — **Claude Code**, **Codex**, **Gemini CLI**. Selecting Claude Code also deploys the bundled `separated` theme.
6. Optionally installs **Claude Code agent skills** (when Claude Code is selected).
7. Runs [`python-env-report.sh`](python-env-report.sh) to report your current Python environment (read-only — see [uv](#uv--python-package--version-manager) below).

The bundled `.gitconfig` intentionally **omits your name/email** — set them after install:

```bash
git config --global user.name  "Your Name"
git config --global user.email "you@example.com"
```

## What Makes This Special

- **Unified Catppuccin Mocha theme** across terminal, prompt, and git diff viewer — consistent dark aesthetic everywhere
- **Modern Rust-based CLI replacements** — `eza`, `bat`, `fd`, `ripgrep`, `zoxide`, `delta` replace their slower counterparts
- **Zero-friction workflow** — fuzzy search everything (files, history, directories), smart `cd` that learns, fish-like autosuggestions
- **Rich Starship prompt** — powerline-style segments showing OS, user, directory, git status, language versions, conda env, time, and command duration
- **Nerd Font icons** throughout — directory icons in `eza`, language icons in Starship, git symbols everywhere

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│  Ghostty Terminal                                           │
│  (Catppuccin Mocha theme, JetBrainsMono Nerd Font)          │
│                                                             │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  Zsh Shell                                            │  │
│  │  ├── Starship Prompt (powerline segments)             │  │
│  │  ├── zsh-autosuggestions (fish-like suggestions)      │  │
│  │  ├── zsh-syntax-highlighting (live command coloring)  │  │
│  │  ├── zsh-completions (extended completions)           │  │
│  │  ├── Atuin (searchable shell history with sync)       │  │
│  │  └── fzf + fd (fuzzy file/directory finder)           │  │
│  └───────────────────────────────────────────────────────┘  │
│                                                             │
│  CLI Replacements:                                          │
│  ls → eza  │  cat → bat  │  find → fd  │  grep → ripgrep   │
│  cd → zoxide  │  top → btop  │  git diff → delta            │
│  git UI → lazygit                                           │
└─────────────────────────────────────────────────────────────┘
```

## Config Files

| File | Purpose |
|------|---------|
| `.zshrc` | Main shell config — plugins, aliases, tool initialization |
| `.config/starship.toml` | Starship prompt theme and segment layout |
| `.config/ghostty.save` | Ghostty terminal appearance settings |
| `.gitconfig` | Git config with delta as pager (side-by-side diffs) |
| `.config/atuin/config.toml` | Atuin shell history settings |
| `.claude/themes/separated.json` | Claude Code custom theme (deployed when Claude Code is selected) |

> The deployable copies live in the repo's `configs/` directory; the installer
> copies them into the locations above (backing up any existing files).

## Tools

### [Ghostty](https://ghostty.org) — Terminal Emulator

A GPU-accelerated terminal emulator. This setup uses:

- **Font**: JetBrainsMono Nerd Font (size 20) — ligatures + thousands of icons
- **Theme**: Catppuccin Mocha — warm dark palette with pastel accents
- **Tweaks**: semi-transparent background (94% opacity), hidden titlebar, auto copy-on-select

### [Starship](https://starship.rs) — Cross-Shell Prompt

A fast, customizable prompt written in Rust. The config defines a **powerline-style multi-segment prompt** with Catppuccin Mocha colors:

```
[OS icon + user] → [directory] → [git branch + status] → [language version] → [conda env] → [time]
                                                                                          ↓
❯ (green = success, red = last command failed)                               command duration
```

**Segments shown**: OS icon, username, current directory (truncated to 3 levels), git branch/status, detected language (C/Rust/Go/Node/Python/Java/Kotlin/PHP/Haskell), conda environment, current time, and command duration.

### Zsh Plugins

**[zsh-autosuggestions](https://github.com/zsh-users/zsh-autosuggestions)** — suggests commands as you type based on history and completions. Accept with `→` (right arrow).

**[zsh-syntax-highlighting](https://github.com/zsh-users/zsh-syntax-highlighting)** — colors commands green/red as you type (valid vs invalid), highlights strings, paths, and options in real-time.

**[zsh-completions](https://github.com/zsh-users/zsh-completions)** — additional completion definitions for hundreds of CLI tools beyond Zsh's built-in completions.

### [Atuin](https://atuin.sh) — Shell History

Replaces the default `Ctrl+R` history search with a full-screen fuzzy search TUI. Features:

- **Fuzzy search** across your entire command history
- **Sync** history across machines (encrypted, optional)
- **Context-aware** — filter by session, directory, or host
- Press `↑` to browse history, `Enter` to execute, `Tab` to edit before running

### [fzf](https://github.com/junegunn/fzf) — Fuzzy Finder

A general-purpose fuzzy finder. Integrated keybindings:

- `Ctrl+T` — fuzzy find files (uses `fd` for speed)
- `Ctrl+R` — fuzzy search history (overridden by Atuin in this setup)
- `Alt+C` — fuzzy `cd` into directories (uses `fd`)
- Configured with `--height 40% --layout=reverse --border` for inline display

### [eza](https://eza.rocks) — Modern `ls`

A modern replacement for `ls` with icons, git status, and color. Aliases configured:

| Alias | Command | What It Does |
|-------|---------|--------------|
| `ls` | `eza --icons --group-directories-first` | List with icons, dirs on top |
| `ll` | `eza -lah --icons --group-directories-first --git` | Long list with git status |
| `la` | `eza -a --icons --group-directories-first` | All files including hidden |
| `tree` | `eza --tree --icons --level=2` | Tree view, 2 levels deep |

### [bat](https://github.com/sharkdp/bat) — Modern `cat`

A `cat` replacement with syntax highlighting, line numbers, and git diff markers. Aliased as `cat`.

- Syntax highlights almost every language automatically
- Shows git changes in the gutter (`+`, `-`, `~`)
- Pipes nicely into other tools (auto-detects non-interactive mode)

### [fd](https://github.com/sharkdp/fd) — Modern `find`

A fast, user-friendly alternative to `find`. Aliased as `find`.

- Smart case matching by default
- Respects `.gitignore`
- Simpler syntax: `fd pattern` instead of `find . -name "*pattern*"`
- Used by `fzf` as the file source for `Ctrl+T` and `Alt+C`

### [ripgrep (rg)](https://github.com/BurntSushi/ripgrep) — Modern `grep`

A blazing-fast search tool. Aliased as `grep`.

- Searches recursively by default
- Respects `.gitignore`
- Smart case sensitivity
- Example: `grep "TODO"` searches all files in the current directory tree

### [zoxide](https://github.com/ajeetdsouza/zoxide) — Smart `cd`

A smarter `cd` that learns your most-used directories. Initialized with `eval "$(zoxide init zsh)"`.

- `z foo` — jump to the highest-ranked directory matching "foo"
- `zi foo` — interactive selection when multiple matches exist
- Learns from your `cd` usage automatically

### [btop](https://github.com/aristocratos/btop) — System Monitor

A beautiful, feature-rich system monitor. Aliased as `top`. Shows CPU, memory, disks, network, and processes with a rich TUI.

### [lazygit](https://github.com/jesseduffield/lazygit) — Git TUI

A terminal UI for git. Aliased as `lg`.

- Stage, commit, push, pull, rebase — all from keyboard shortcuts
- Visual diff viewer, branch management, stash management
- Interactive rebase with drag-and-drop commits

### [delta](https://github.com/dandavison/delta) — Git Diff Viewer

Configured as the default git pager in `.gitconfig`. Features:

- **Side-by-side diffs** — see old and new code in parallel
- **Line numbers** in diff output
- **Syntax highlighting** in diffs
- **Navigate mode** — use `n`/`N` to jump between files in large diffs

### [fnm](https://github.com/Schniz/fnm) — Node.js Version Manager

Fast Node.js version manager written in Rust. Configured with `--use-on-cd` to automatically switch Node versions when entering a directory with `.node-version` or `.nvmrc`.

```bash
fnm install 22        # Install Node 22
fnm use 22            # Switch to Node 22
fnm default 22        # Set default version
```

### [uv](https://github.com/astral-sh/uv) — Python Package & Version Manager

An extremely fast Python package and project manager written in Rust, replacing `pip`, `pyenv`, `virtualenv`, and `poetry`. It downloads and manages Python interpreters on demand, so you don't need a separate version manager.

```bash
uv python install 3.13   # Install a Python interpreter
uv venv                  # Create a virtual environment
uv sync                  # Install deps from pyproject.toml/uv.lock
uv run python main.py    # Run inside the project environment
uv python list           # List installed + available interpreters
```

### [`python-env-report.sh`](python-env-report.sh) — Python Environment Detector

A bundled, **read-only** helper script (it never installs or removes anything).
`install.sh` runs it at the end, and you can re-run it anytime:

```bash
./python-env-report.sh
```

It reports:

- which interpreter `python3` actually resolves to, and every `python3` on `PATH`
- `uv`-managed, Homebrew, conda, python.org-framework, and macOS-system Pythons
- Homebrew pythons that are safe to keep (a formula depends on them) vs. worth reviewing
- conda environments with their versions and on-disk sizes
- a redundancy check flagging when the same `major.minor` is provided by several installs

### [tldr](https://tldr.sh) — Simplified Man Pages

Community-driven simplified help pages. Shows practical examples instead of exhaustive documentation.

```bash
tldr tar              # Quick examples for tar
tldr git rebase       # Quick examples for git rebase
```

### [jq](https://jqlang.github.io/jq/) — JSON Processor

A lightweight command-line JSON processor.

```bash
cat data.json | jq '.items[0].name'    # Extract fields
curl api.example.com | jq '.'          # Pretty-print API responses
```

### [glow](https://github.com/charmbracelet/glow) — Markdown Renderer

Renders Markdown in the terminal with styling and pager support. Aliased as `md`.

```bash
md README.md          # Render a Markdown file in the pager (glow -p)
```

## Git Aliases

| Alias | Command |
|-------|---------|
| `gs` | `git status` |
| `ga` | `git add` |
| `gc` | `git commit` |
| `gp` | `git push` |
| `gl` | `git log --oneline --graph --decorate --all` |
| `lg` | `lazygit` |
| `md` | `glow -p` |

## Tests

The two shell scripts (`install.sh`, `python-env-report.sh`) have a
dependency-free unit-test suite that runs on the stock macOS bash:

```bash
./tests/run.sh
```

See [`docs/TESTING.md`](docs/TESTING.md) for an overview of all 36 tests and
what each covers.

CI runs this same suite on every push and PR — see [`docs/CI.md`](docs/CI.md).

## History Configuration

- **50,000 lines** of history retained
- Deduplication enabled (oldest dupes expire first)
- Commands starting with a space are not recorded (useful for sensitive commands)
- History is shared across all open terminal sessions in real-time
- Atuin provides additional fuzzy search and optional cross-machine sync on top
