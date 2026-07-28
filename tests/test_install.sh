#!/usr/bin/env bash
#
# Unit tests for install.sh (flag parsing, confirm, deploy_config, helpers,
# and the brew-wrapping installers with a mocked `brew`).
#
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$DIR/.." && pwd)"
TARGET="$REPO_ROOT/install.sh"
TEST_SUITE_NAME="install.sh"

# shellcheck source=tests/lib.sh
source "$DIR/lib.sh"

# Source install.sh's functions without running main(). install.sh enables
# `set -euo pipefail`; relax -e/-u so tests can inspect return codes freely.
load() { source "$TARGET"; set +eu; }

# --- flag parsing -----------------------------------------------------------
test_defaults_are_off() {
  load
  assert_eq 0 "$INSTALL_ALL" "INSTALL_ALL defaults off"
  assert_eq 0 "$SKIP_AI" "SKIP_AI defaults off"
}

test_parse_args_all() {
  load
  parse_args --all
  assert_eq 1 "$INSTALL_ALL" "--all sets INSTALL_ALL"
  assert_eq 0 "$SKIP_AI" "--all leaves SKIP_AI off"
}

test_parse_args_no_ai() {
  load
  parse_args --no-ai
  assert_eq 1 "$SKIP_AI" "--no-ai sets SKIP_AI"
}

test_help_flag_exits_zero_with_usage() {
  capture h bash "$TARGET" --help
  assert_status 0 "$h_rc" "--help exits 0"
  assert_contains "$h_out" "Usage:" "--help prints usage block"
}

test_unknown_flag_exits_one() {
  capture u bash "$TARGET" --nope
  assert_status 1 "$u_rc" "unknown flag exits 1"
  assert_contains "$u_out" "Unknown option" "unknown flag explains itself"
}

# --- confirm ----------------------------------------------------------------
test_confirm_yes_when_install_all() {
  load; INSTALL_ALL=1; SKIP_AI=0
  local rc; if confirm "go?" </dev/null; then rc=0; else rc=$?; fi
  assert_status 0 "$rc" "--all auto-confirms"
}

test_confirm_no_when_skip_ai() {
  load; INSTALL_ALL=0; SKIP_AI=1
  local rc; if confirm "go?" </dev/null; then rc=0; else rc=$?; fi
  assert_status 1 "$rc" "--no-ai auto-declines"
}

test_confirm_no_on_non_tty() {
  load; INSTALL_ALL=0; SKIP_AI=0
  local rc; if confirm "go?" </dev/null; then rc=0; else rc=$?; fi
  assert_status 1 "$rc" "non-interactive stdin declines by default"
}

# --- deploy_config ----------------------------------------------------------
# Each test builds an isolated fake SCRIPT_DIR/configs + HOME.
setup_deploy() { # setup_deploy -> sets SCRIPT_DIR, HOME, SRC in the caller
  local t; t="$(mktemp -d)"
  SCRIPT_DIR="$t"
  HOME="$t/home"
  mkdir -p "$SCRIPT_DIR/configs" "$HOME"
}

test_deploy_missing_source_warns_and_skips() {
  load; setup_deploy
  capture d deploy_config "zshrc" "$HOME/.zshrc"
  assert_status 0 "$d_rc" "missing source is non-fatal"
  assert_contains "$d_out" "Config not found" "warns about missing source"
  assert_no_file "$HOME/.zshrc" "no destination created"
}

test_deploy_empty_script_dir_skips() {
  load; setup_deploy
  SCRIPT_DIR=""
  capture d deploy_config "zshrc" "$HOME/.zshrc"
  assert_contains "$d_out" "Config not found" "empty SCRIPT_DIR treated as not found"
  assert_no_file "$HOME/.zshrc" "nothing deployed"
}

test_deploy_creates_new_file() {
  load; setup_deploy
  printf 'SRC\n' > "$SCRIPT_DIR/configs/zshrc"
  capture d deploy_config "zshrc" "$HOME/.zshrc"
  assert_contains "$d_out" "Deployed" "reports deployment"
  assert_file "$HOME/.zshrc" "destination created"
  assert_eq "SRC" "$(cat "$HOME/.zshrc")" "content copied"
}

test_deploy_identical_is_noop_no_backup() {
  load; setup_deploy
  printf 'SAME\n' > "$SCRIPT_DIR/configs/zshrc"
  printf 'SAME\n' > "$HOME/.zshrc"
  capture d deploy_config "zshrc" "$HOME/.zshrc"
  assert_contains "$d_out" "already up to date" "identical file left alone"
  local n; n="$(ls "$HOME"/.zshrc.bak.* 2>/dev/null | wc -l | tr -d ' ')"
  assert_eq 0 "$n" "no backup made for identical file"
}

test_deploy_differing_backs_up_then_replaces() {
  load; setup_deploy
  printf 'NEW\n' > "$SCRIPT_DIR/configs/zshrc"
  printf 'OLD\n' > "$HOME/.zshrc"
  capture d deploy_config "zshrc" "$HOME/.zshrc"
  assert_contains "$d_out" "Backed up" "reports the backup"
  assert_eq "NEW" "$(cat "$HOME/.zshrc")" "destination replaced with source"
  local n; n="$(ls "$HOME"/.zshrc.bak.* 2>/dev/null | wc -l | tr -d ' ')"
  assert_eq 1 "$n" "exactly one backup created"
  assert_eq "OLD" "$(cat "$HOME"/.zshrc.bak.*)" "backup holds the old content"
}

test_deploy_creates_nested_destination_dir() {
  load; setup_deploy
  mkdir -p "$SCRIPT_DIR/configs/atuin"
  printf 'CFG\n' > "$SCRIPT_DIR/configs/atuin/config.toml"
  capture d deploy_config "atuin/config.toml" "$HOME/.config/atuin/config.toml"
  assert_file "$HOME/.config/atuin/config.toml" "nested dirs created and file deployed"
  assert_eq "CFG" "$(cat "$HOME/.config/atuin/config.toml")" "nested content copied"
}

# --- output helpers ---------------------------------------------------------
test_info_ok_warn_carry_message() {
  load
  capture i info "hello-info"; assert_contains "$i_out" "hello-info" "info shows message"
  capture o ok   "hello-ok";   assert_contains "$o_out" "hello-ok"   "ok shows message"
  capture w warn "hello-warn"; assert_contains "$w_out" "hello-warn" "warn shows message"
}

test_die_exits_one_with_message() {
  load
  capture x die "boom"
  assert_status 1 "$x_rc" "die exits 1"
  assert_contains "$x_out" "boom" "die reports the reason"
}

# --- install_formula / install_cask (brew mocked) ---------------------------
test_install_formula_skips_when_present() {
  load
  brew() { [[ "$1 $2" == "list --formula" ]] && return 0; return 0; }
  capture o install_formula starship
  assert_contains "$o_out" "already installed" "present formula is skipped"
  assert_not_contains "$o_out" "Installing" "no install attempted"
}

test_install_formula_installs_when_missing() {
  load
  brew() {
    if [[ "$1 $2" == "list --formula" ]]; then return 1; fi
    if [[ "$1" == "install" ]]; then echo "BREW_INSTALL $2"; return 0; fi
  }
  capture o install_formula starship
  assert_contains "$o_out" "Installing starship" "missing formula triggers install"
  assert_contains "$o_out" "BREW_INSTALL starship" "brew install called with the formula"
}

test_install_cask_installs_when_missing() {
  load
  brew() {
    if [[ "$1 $2" == "list --cask" ]]; then return 1; fi
    if [[ "$1" == "install" && "$2" == "--cask" ]]; then echo "BREW_CASK $3"; return 0; fi
  }
  capture o install_cask ghostty
  assert_contains "$o_out" "BREW_CASK ghostty" "brew install --cask called for the cask"
}

run_tests
