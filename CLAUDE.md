# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A documented Mac terminal setup built on Ghostty + Zsh + Starship with a Catppuccin Mocha theme. All tools are installed via Homebrew. The repo serves as both documentation and a reference for reproducing the setup.

## Key Config Files (on the user's system)

- `~/.zshrc` — Main shell config: plugins, aliases, tool init
- `~/.config/starship.toml` — Starship prompt segments and Catppuccin palette
- `~/.config/ghostty.save` — Ghostty terminal settings
- `~/.gitconfig` — Git config with delta as pager
- `~/.config/atuin/config.toml` — Atuin shell history config

## Tool Stack

Shell: Zsh with zsh-autosuggestions, zsh-syntax-highlighting, zsh-completions
Prompt: Starship (Catppuccin Mocha powerline theme)
Terminal: Ghostty (JetBrainsMono Nerd Font)
CLI replacements: eza (ls), bat (cat), fd (find), ripgrep (grep), zoxide (cd), btop (top), delta (git pager), lazygit (git TUI)
History: Atuin (fuzzy search + sync)
Fuzzy finder: fzf (backed by fd)
Node: fnm (auto-switch on cd)
