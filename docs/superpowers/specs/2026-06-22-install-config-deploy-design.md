# Design: install.sh config deployment + interactive AI CLI menu

Date: 2026-06-22
Status: Approved (pending spec review)

## Problem

`install.sh` installs the toolchain but never configures it: aliases, the Starship
prompt, Ghostty, git/delta, and atuin all stay unconfigured because the repo ships
no config files and the script explicitly "does not touch your config files." The
goal is to match the behavior of the reference repo
(https://github.com/lewislulu/terminal-setup): deploy config files (backing up any
existing ones), using *this* user's configuration. Additionally, replace the three
separate y/N AI-CLI prompts with a single arrow-key + space multi-select menu like
the reference repo's shell picker.

Scope is macOS + Zsh only (per CLAUDE.md). Out of scope: Linux/apt, Fish, Zellij,
dry-run mode, bundled binaries.

## 1. New `configs/` directory

Commit the user's configs so the script can deploy from a sibling directory:

```
configs/
├── zshrc                 # → ~/.zshrc                    (CLEANED, portable)
├── starship.toml         # → ~/.config/starship.toml     (verbatim)
├── ghostty.save          # → ~/.config/ghostty.save      (verbatim)
├── gitconfig             # → ~/.gitconfig                (delta settings; NO [user] block)
└── atuin/config.toml     # → ~/.config/atuin/config.toml (scrubbed of any secrets)
```

### Cleaned `zshrc`
Keep: Homebrew PATH, `starship init`, the three zsh plugins + `compinit`, history
options, fzf + fd integration, `zoxide init`, `fnm env --use-on-cd`, `atuin init`,
and ALL aliases (`ls/ll/la/tree`, `cat/find/grep/top/lg`, git aliases `gs/ga/gc/gp/gl`,
and `md='glow -p'`).

Drop (machine-specific): conda init block, opencode PATH, pnpm block,
`set-ssh-key` function.

### `gitconfig`
Keep `[http]`, `[core] pager=delta`, `[interactive] diffFilter`, `[delta]`,
`[merge]`, `[diff]` verbatim. OMIT the `[user]` name/email block entirely (keeps the
user's email out of the public repo; avoids stamping it onto other machines). The
deploy step prints a reminder to run `git config --global user.name/user.email`.

## 2. Sensitive-info scan (pre-commit)

Before committing `configs/`, scan every file for: email addresses, API keys/tokens,
SSH key filenames, atuin sync address / session keys, and any hardcoded absolute
home paths that leak identity. The atuin `config.toml` is the highest risk. Report
findings; strip or redact anything sensitive before committing. No secrets get
committed.

## 3. install.sh changes

### 3a. Add `glow` to FORMULAE
Add `glow` (markdown renderer) so the `md` alias works.

### 3b. New config-deploy section (auto, every run)
Runs after tools install, before the AI-CLI section.

- Resolve `SCRIPT_DIR` from `$0` (so the script finds `configs/`).
- `deploy_config <src-rel> <dest-abs>` helper:
  1. If `configs/<src-rel>` is missing → warn and skip (handles curl|bash without repo).
  2. `mkdir -p "$(dirname dest)"`.
  3. If dest exists and is **identical** → report "up to date", skip.
  4. If dest exists and **differs** → move to `<dest>.bak.$(date +%s)`, then copy.
  5. If dest absent → copy.
- Invoke for all five configs.
- After deploying gitconfig, print the git user.name/email reminder.

### 3c. Interactive AI-CLI multi-select menu
Replace the three separate `confirm` prompts with one checkbox menu.

- `multiselect` bash function: enter raw mode via `stty`, hide cursor; render a list
  with `[ ]`/`[x]` and a `>` cursor on the active row; handle keys:
  - `↑`/`↓` (and `k`/`j`) → move cursor
  - `Space` → toggle current item
  - `Enter` → confirm and return the selected set
  - always restore terminal state on exit (trap/cleanup).
- Items: `Claude Code`, `Codex`, `Gemini CLI` — all unchecked by default.
- Install each checked item via existing `install_claude_code` / `install_codex` /
  `install_gemini`. Set `CLAUDE_REQUESTED=1` if Claude Code chosen.
- Behavior gates:
  - `--no-ai` → skip menu entirely (warn).
  - `--all` → select all three without showing the menu.
  - Non-TTY (`! -t 0`) → skip menu, print hint to re-run interactively or use `--all`.
  - Interactive default → show the menu.

### 3d. Skills step (unchanged)
Stays a separate y/N `confirm` after the menu; only runs when Claude Code was
selected or `--all`.

### 3e. Header comment + "Next steps" heredoc
- Header: document config deployment with timestamped backups, and the new menu.
- "Next steps": remove the "installs tools only / copy configs yourself" text.
  Replace with: configs deployed (backups noted as `*.bak.<ts>`), set git
  user.name/email, set/confirm Ghostty font, `exec zsh`, authenticate AI CLIs,
  skills fallback note.

## 4. README update (aligned to reference repo)

- Add **Quick Install** near top: clone + `./install.sh`; document `--all` /
  `--no-ai`; note existing configs are backed up with timestamps.
- Add **What the installer does** numbered list: Homebrew → CLI tools →
  casks/font → interactive AI CLI menu → deploy configs (with backup).
- Document `glow` in the tools section; note the `md` alias.
- Note the git `[user]` block must be set manually after install.
- Keep all existing per-tool documentation.

## 5. Testing / verification

- `bash -n install.sh` (syntax).
- ShellCheck if available.
- Dry confirm the `multiselect` renders and toggles in an interactive terminal
  (manual, since it needs a TTY).
- Confirm `deploy_config` backup/identical/copy branches behave (can test against
  temp files).
- Confirm `configs/` contains no secrets (grep scan).
```

