# Awesome Mac Terminal Setup

A modern, aesthetic, and productive macOS terminal setup built on **Ghostty + Zsh + Starship**, themed with **Catppuccin Mocha**. Every tool is installed via Homebrew and configured to work together out of the box.

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

## Tools

### Ghostty — Terminal Emulator

A GPU-accelerated terminal emulator. This setup uses:

- **Font**: JetBrainsMono Nerd Font (size 20) — ligatures + thousands of icons
- **Theme**: Catppuccin Mocha — warm dark palette with pastel accents
- **Tweaks**: semi-transparent background (94% opacity), hidden titlebar, auto copy-on-select

### Starship — Cross-Shell Prompt

A fast, customizable prompt written in Rust. The config defines a **powerline-style multi-segment prompt** with Catppuccin Mocha colors:

```
[OS icon + user] → [directory] → [git branch + status] → [language version] → [conda env] → [time]
                                                                                          ↓
❯ (green = success, red = last command failed)                               command duration
```

**Segments shown**: OS icon, username, current directory (truncated to 3 levels), git branch/status, detected language (C/Rust/Go/Node/Python/Java/Kotlin/PHP/Haskell), conda environment, current time, and command duration.

### Zsh Plugins

**zsh-autosuggestions** — suggests commands as you type based on history and completions. Accept with `→` (right arrow).

**zsh-syntax-highlighting** — colors commands green/red as you type (valid vs invalid), highlights strings, paths, and options in real-time.

**zsh-completions** — additional completion definitions for hundreds of CLI tools beyond Zsh's built-in completions.

### Atuin — Shell History

Replaces the default `Ctrl+R` history search with a full-screen fuzzy search TUI. Features:

- **Fuzzy search** across your entire command history
- **Sync** history across machines (encrypted, optional)
- **Context-aware** — filter by session, directory, or host
- Press `↑` to browse history, `Enter` to execute, `Tab` to edit before running

### fzf — Fuzzy Finder

A general-purpose fuzzy finder. Integrated keybindings:

- `Ctrl+T` — fuzzy find files (uses `fd` for speed)
- `Ctrl+R` — fuzzy search history (overridden by Atuin in this setup)
- `Alt+C` — fuzzy `cd` into directories (uses `fd`)
- Configured with `--height 40% --layout=reverse --border` for inline display

### eza — Modern `ls`

A modern replacement for `ls` with icons, git status, and color. Aliases configured:

| Alias | Command | What It Does |
|-------|---------|--------------|
| `ls` | `eza --icons --group-directories-first` | List with icons, dirs on top |
| `ll` | `eza -lah --icons --group-directories-first --git` | Long list with git status |
| `la` | `eza -a --icons --group-directories-first` | All files including hidden |
| `tree` | `eza --tree --icons --level=2` | Tree view, 2 levels deep |

### bat — Modern `cat`

A `cat` replacement with syntax highlighting, line numbers, and git diff markers. Aliased as `cat`.

- Syntax highlights almost every language automatically
- Shows git changes in the gutter (`+`, `-`, `~`)
- Pipes nicely into other tools (auto-detects non-interactive mode)

### fd — Modern `find`

A fast, user-friendly alternative to `find`. Aliased as `find`.

- Smart case matching by default
- Respects `.gitignore`
- Simpler syntax: `fd pattern` instead of `find . -name "*pattern*"`
- Used by `fzf` as the file source for `Ctrl+T` and `Alt+C`

### ripgrep (rg) — Modern `grep`

A blazing-fast search tool. Aliased as `grep`.

- Searches recursively by default
- Respects `.gitignore`
- Smart case sensitivity
- Example: `grep "TODO"` searches all files in the current directory tree

### zoxide — Smart `cd`

A smarter `cd` that learns your most-used directories. Initialized with `eval "$(zoxide init zsh)"`.

- `z foo` — jump to the highest-ranked directory matching "foo"
- `zi foo` — interactive selection when multiple matches exist
- Learns from your `cd` usage automatically

### btop — System Monitor

A beautiful, feature-rich system monitor. Aliased as `top`. Shows CPU, memory, disks, network, and processes with a rich TUI.

### lazygit — Git TUI

A terminal UI for git. Aliased as `lg`.

- Stage, commit, push, pull, rebase — all from keyboard shortcuts
- Visual diff viewer, branch management, stash management
- Interactive rebase with drag-and-drop commits

### delta — Git Diff Viewer

Configured as the default git pager in `.gitconfig`. Features:

- **Side-by-side diffs** — see old and new code in parallel
- **Line numbers** in diff output
- **Syntax highlighting** in diffs
- **Navigate mode** — use `n`/`N` to jump between files in large diffs

### fnm — Node.js Version Manager

Fast Node.js version manager written in Rust. Configured with `--use-on-cd` to automatically switch Node versions when entering a directory with `.node-version` or `.nvmrc`.

```bash
fnm install 22        # Install Node 22
fnm use 22            # Switch to Node 22
fnm default 22        # Set default version
```

### tldr — Simplified Man Pages

Community-driven simplified help pages. Shows practical examples instead of exhaustive documentation.

```bash
tldr tar              # Quick examples for tar
tldr git rebase       # Quick examples for git rebase
```

### jq — JSON Processor

A lightweight command-line JSON processor.

```bash
cat data.json | jq '.items[0].name'    # Extract fields
curl api.example.com | jq '.'          # Pretty-print API responses
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

## History Configuration

- **50,000 lines** of history retained
- Deduplication enabled (oldest dupes expire first)
- Commands starting with a space are not recorded (useful for sensitive commands)
- History is shared across all open terminal sessions in real-time
- Atuin provides additional fuzzy search and optional cross-machine sync on top
