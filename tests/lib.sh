#!/usr/bin/env bash
#
# tests/lib.sh — a tiny, dependency-free unit-test harness for this repo.
#
# Works on the stock macOS bash 3.2. A test file sources this, defines one or
# more `test_*` functions, and calls `run_tests` at the end. Each test runs in
# its own subshell (so environment/`cd`/overrides never leak between tests) and
# fails on the first failing assertion via a non-zero exit.
#
# Assertions available to tests:
#   assert_eq            EXPECTED ACTUAL [msg]
#   assert_contains      HAYSTACK NEEDLE  [msg]
#   assert_not_contains  HAYSTACK NEEDLE  [msg]
#   assert_status        EXPECTED_CODE ACTUAL_CODE [msg]
#   assert_file          PATH [msg]        # file exists
#   assert_no_file       PATH [msg]        # file does not exist
#   fail                 msg
#
# Helper for exit-code capture without tripping `set -e`:
#   capture VAR_PREFIX cmd args...   # sets <VAR_PREFIX>_out and <VAR_PREFIX>_rc

# Colors only when attached to a terminal.
if [[ -t 1 ]]; then
  _G=$'\033[32m'; _R=$'\033[31m'; _Y=$'\033[33m'; _B=$'\033[1m'; _N=$'\033[0m'
else
  _G=''; _R=''; _Y=''; _B=''; _N=''
fi

TESTS_RUN=0
TESTS_FAILED=0

fail() { printf 'FAIL: %s\n' "$*"; exit 1; }

assert_eq() {
  local exp="$1" act="$2" msg="${3:-values should be equal}"
  if [[ "$exp" != "$act" ]]; then
    printf 'assert_eq: %s\n  expected: [%s]\n  actual:   [%s]\n' "$msg" "$exp" "$act"
    exit 1
  fi
}

assert_contains() {
  local hay="$1" needle="$2" msg="${3:-output should contain needle}"
  if [[ "$hay" != *"$needle"* ]]; then
    printf 'assert_contains: %s\n  needle: [%s]\n  in:     [%s]\n' "$msg" "$needle" "$hay"
    exit 1
  fi
}

assert_not_contains() {
  local hay="$1" needle="$2" msg="${3:-output should NOT contain needle}"
  if [[ "$hay" == *"$needle"* ]]; then
    printf 'assert_not_contains: %s\n  needle: [%s]\n  in:     [%s]\n' "$msg" "$needle" "$hay"
    exit 1
  fi
}

assert_status() {
  local exp="$1" act="$2" msg="${3:-exit status}"
  if [[ "$exp" != "$act" ]]; then
    printf 'assert_status: %s\n  expected: %s\n  actual:   %s\n' "$msg" "$exp" "$act"
    exit 1
  fi
}

assert_file() {
  local p="$1" msg="${2:-file should exist}"
  [[ -f "$p" ]] || { printf 'assert_file: %s\n  missing: [%s]\n' "$msg" "$p"; exit 1; }
}

assert_no_file() {
  local p="$1" msg="${2:-file should not exist}"
  [[ ! -e "$p" ]] || { printf 'assert_no_file: %s\n  present: [%s]\n' "$msg" "$p"; exit 1; }
}

# capture PREFIX cmd... — run cmd, storing combined output in <PREFIX>_out and
# its exit code in <PREFIX>_rc, without letting a non-zero code abort the test
# (needed because sourced scripts may enable `set -e`).
capture() {
  local prefix="$1"; shift
  local __out __rc
  __out="$("$@" 2>&1)" && __rc=0 || __rc=$?
  printf -v "${prefix}_out" '%s' "$__out"
  printf -v "${prefix}_rc" '%s' "$__rc"
}

# run_tests — discover every `test_*` function in the sourcing file, run each in
# an isolated subshell, print PASS/FAIL, and exit non-zero if any failed.
run_tests() {
  local fn out
  local fns; fns="$(declare -F | awk '{print $3}' | grep '^test_' | sort || true)"
  printf '%s%s%s\n' "$_B" "${TEST_SUITE_NAME:-tests}" "$_N"
  for fn in $fns; do
    TESTS_RUN=$((TESTS_RUN + 1))
    if out="$( set +e; "$fn" 2>&1 )"; then
      printf '  %sPASS%s %s\n' "$_G" "$_N" "$fn"
    else
      TESTS_FAILED=$((TESTS_FAILED + 1))
      printf '  %sFAIL%s %s\n' "$_R" "$_N" "$fn"
      printf '%s\n' "$out" | sed 's/^/         /'
    fi
  done
  printf '  %d run, %d failed\n' "$TESTS_RUN" "$TESTS_FAILED"
  [[ "$TESTS_FAILED" -eq 0 ]]
}
