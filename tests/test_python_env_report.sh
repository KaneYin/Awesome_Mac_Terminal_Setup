#!/usr/bin/env bash
#
# Unit tests for python-env-report.sh (pure helpers + black-box behavior).
#
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$DIR/.." && pwd)"
TARGET="$REPO_ROOT/python-env-report.sh"
TEST_SUITE_NAME="python-env-report.sh"

# shellcheck source=tests/lib.sh
source "$DIR/lib.sh"

# Source the target's functions without running the report; -u would trip on the
# test harness's own vars, so relax it after loading.
load() { source "$TARGET"; set +u; }

# --- realpath_p -------------------------------------------------------------
test_realpath_p_plain_file_unchanged() {
  load
  local t; t="$(mktemp -d)"; : > "$t/regular"
  assert_eq "$t/regular" "$(realpath_p "$t/regular")" "plain file returned as-is"
}

test_realpath_p_single_symlink() {
  load
  local t; t="$(mktemp -d)"; : > "$t/target"
  ln -s "$t/target" "$t/link"
  assert_eq "$t/target" "$(realpath_p "$t/link")" "single symlink resolves to target"
}

test_realpath_p_chained_symlinks() {
  load
  local t; t="$(mktemp -d)"; : > "$t/c"
  ln -s "$t/c" "$t/b"
  ln -s "$t/b" "$t/a"
  assert_eq "$t/c" "$(realpath_p "$t/a")" "chained symlinks resolve to final target"
}

test_realpath_p_relative_symlink() {
  load
  local t; t="$(mktemp -d)"; : > "$t/realfile"
  ( cd "$t" && ln -s realfile rel )
  assert_eq "$t/realfile" "$(realpath_p "$t/rel")" "relative symlink resolves against its dir"
}

# --- ver --------------------------------------------------------------------
make_fake_python() { # make_fake_python <dir> <line> [stream]
  local dir="$1" line="$2" stream="${3:-1}"
  cat > "$dir/py" <<EOF
#!/usr/bin/env bash
echo "$line" >&$stream
EOF
  chmod +x "$dir/py"
}

test_ver_parses_stdout_version() {
  load
  local t; t="$(mktemp -d)"; make_fake_python "$t" "Python 3.13.13" 1
  assert_eq "3.13.13" "$(ver "$t/py")" "parses 'Python X.Y.Z' on stdout"
}

test_ver_parses_stderr_version() {
  load
  # Older pythons print --version to stderr; ver merges 2>&1.
  local t; t="$(mktemp -d)"; make_fake_python "$t" "Python 2.7.18" 2
  assert_eq "2.7.18" "$(ver "$t/py")" "parses version printed to stderr"
}

# --- mm_of ------------------------------------------------------------------
test_mm_of_full_version() {
  load
  assert_eq "3.13" "$(mm_of 3.13.13)" "major.minor of 3.13.13"
}

test_mm_of_two_digit_minor() {
  load
  assert_eq "3.9" "$(mm_of 3.9.6)" "major.minor of 3.9.6"
}

test_mm_of_empty_is_empty() {
  load
  assert_eq "" "$(mm_of "")" "empty version yields empty"
}

test_mm_of_major_only_is_empty() {
  load
  assert_eq "" "$(mm_of 3)" "version without a minor yields empty"
}

# --- PATH diagnostics -------------------------------------------------------
test_path_diagnostics_flags_duplicate() {
  load
  local t; t="$(mktemp -d)"
  PATH="$t:$t:/usr/bin:/bin"
  assert_contains "$(path_diagnostics)" "duplicate" "duplicate path is reported"
}

test_path_diagnostics_flags_missing() {
  load
  local t; t="$(mktemp -d)"
  PATH="$t:/definitely/not/a/real/path:/usr/bin:/bin"
  assert_contains "$(path_diagnostics)" "missing" "stale path is reported"
}

test_uv_inventory_failure_is_unknown() {
  load
  local t; t="$(mktemp -d)"; TMPDIR="$t"
  uv() { echo 'cache initialization failed'; return 1; }
  local out; out="$(uv_inventory)"
  assert_contains "$out" "unknown" "uv failure remains unknown"
  assert_contains "$out" "cache initialization failed" "uv failure reason is retained"
}

test_conda_resolution_active_when_both_commands_match() {
  load
  assert_eq active "$(conda_resolution_state /conda /conda/bin/python /conda/bin/python3)" "both commands use conda"
}

test_conda_resolution_split_when_python3_differs() {
  load
  assert_eq split "$(conda_resolution_state /conda /conda/bin/python /brew/bin/python3)" "split resolution is detected"
}

# --- Homebrew dependency state ---------------------------------------------
test_brew_dependency_state_required() {
  load
  brew() { printf 'tool-a\ntool-b\n'; return 0; }
  local out; out="$(brew_dependency_state python@3.13)"
  assert_contains "$out" "required" "successful non-empty probe is required"
  assert_contains "$out" "tool-a" "dependent is retained"
}

test_brew_dependency_state_candidate() {
  load
  brew() { return 0; }
  assert_contains "$(brew_dependency_state python@3.13)" "candidate" "successful empty probe is a candidate"
}

test_brew_dependency_state_failure_is_unknown() {
  load
  brew() { echo 'SHA-256: not-a-dependent'; return 1; }
  local out; out="$(brew_dependency_state python@3.13)"
  assert_contains "$out" "unknown" "failed probe is unknown"
  assert_not_contains "$out" "SHA-256" "failed stdout is never dependency data"
}

# --- summarize_overlap ------------------------------------------------------
test_redundancy_single_install() {
  load
  local out; out="$(printf 'apple|3.9.6\n' | summarize_overlap)"
  assert_contains "$out" "Python 3.9 — one discovered provider (apple)." "single provider is named"
}

test_redundancy_flags_duplicate_series() {
  load
  local out; out="$(printf 'conda|3.13.13\nuv|3.13.5\n' | summarize_overlap)"
  assert_contains "$out" "Python 3.13 has 2 managed providers" "overlapping 3.13 is explained"
  assert_contains "$out" "do not remove by version count alone" "summary avoids unsafe advice"
}

test_redundancy_counts_three() {
  load
  local out; out="$(printf 'homebrew|3.11.1\nconda|3.11.2\nuv|3.11.3\n' | summarize_overlap)"
  assert_contains "$out" "has 3 managed providers" "three managers counted"
}

test_redundancy_mixed_series() {
  load
  local out; out="$(printf 'homebrew|3.13.1\nconda|3.13.2\nuv|3.12.7\n' | summarize_overlap)"
  assert_contains "$out" "Python 3.13 has 2 managed providers" "3.13 overlaps"
  assert_contains "$out" "Python 3.12 — one discovered provider (uv)." "3.12 single"
}

test_redundancy_ignores_blank_lines() {
  load
  local out; out="$(printf '\n\n\n' | summarize_overlap)"
  assert_eq "" "$out" "blank input produces no summary lines"
}

# --- black-box --------------------------------------------------------------
test_report_runs_and_has_sections() {
  capture run bash "$TARGET"
  assert_status 0 "$run_rc" "report exits 0"
  assert_contains "$run_out" "Python Environment Report" "prints report header"
  assert_contains "$run_out" "Installation overlap" "prints overlap section"
  assert_contains "$run_out" "Read-only audit." "prints read-only footer"
}

test_sourcing_does_not_run_report() {
  local out; out="$( source "$TARGET"; echo "SOURCED_MARKER" )"
  assert_contains "$out" "SOURCED_MARKER" "source completes"
  assert_not_contains "$out" "Installation overlap" "sourcing must not emit the report"
}

run_tests
