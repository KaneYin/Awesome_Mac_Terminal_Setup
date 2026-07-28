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

# --- summarize_redundancy ---------------------------------------------------
test_redundancy_single_install() {
  load
  local out; out="$(printf '3.9.6\n' | summarize_redundancy)"
  assert_contains "$out" "Python 3.9 — single install." "single 3.9 reported as single"
}

test_redundancy_flags_duplicate_series() {
  load
  # Two different patch releases of the same 3.13 series = redundant.
  local out; out="$(printf '3.13.13\n3.13.3\n' | summarize_redundancy)"
  assert_contains "$out" "Python 3.13 provided by 2 separate installs" "duplicate 3.13 flagged"
}

test_redundancy_counts_three() {
  load
  local out; out="$(printf '3.11.1\n3.11.2\n3.11.3\n' | summarize_redundancy)"
  assert_contains "$out" "provided by 3 separate installs" "three installs counted"
}

test_redundancy_mixed_series() {
  load
  local out; out="$(printf '3.13.1\n3.13.2\n3.12.7\n' | summarize_redundancy)"
  assert_contains "$out" "Python 3.13 provided by 2 separate installs" "3.13 duplicated"
  assert_contains "$out" "Python 3.12 — single install." "3.12 single"
}

test_redundancy_ignores_blank_lines() {
  load
  local out; out="$(printf '\n\n\n' | summarize_redundancy)"
  assert_eq "" "$out" "blank input produces no summary lines"
}

# --- black-box --------------------------------------------------------------
test_report_runs_and_has_sections() {
  capture run bash "$TARGET"
  assert_status 0 "$run_rc" "report exits 0"
  assert_contains "$run_out" "Python Environment Report" "prints report header"
  assert_contains "$run_out" "Redundancy check" "prints redundancy section"
  assert_contains "$run_out" "Read-only report." "prints read-only footer"
}

test_sourcing_does_not_run_report() {
  local out; out="$( source "$TARGET"; echo "SOURCED_MARKER" )"
  assert_contains "$out" "SOURCED_MARKER" "source completes"
  assert_not_contains "$out" "Redundancy check" "sourcing must not emit the report"
}

run_tests
