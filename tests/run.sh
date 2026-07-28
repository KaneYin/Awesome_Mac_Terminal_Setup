#!/usr/bin/env bash
#
# tests/run.sh — run every tests/test_*.sh file and aggregate the result.
#
# Usage:
#   ./tests/run.sh            # run all suites
#   ./tests/run.sh install    # run only suites whose filename matches "install"
#
# Exits non-zero if any suite has a failing test. Pure bash, no dependencies —
# runs on the stock macOS bash 3.2.
#
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
filter="${1:-}"

if [[ -t 1 ]]; then G=$'\033[32m'; R=$'\033[31m'; B=$'\033[1m'; N=$'\033[0m'; else G=''; R=''; B=''; N=''; fi

failed=0
ran=0
for f in "$DIR"/test_*.sh; do
  [[ -e "$f" ]] || continue
  if [[ -n "$filter" && "$f" != *"$filter"* ]]; then continue; fi
  ran=$((ran + 1))
  echo
  if bash "$f"; then :; else failed=$((failed + 1)); fi
done

echo
if [[ "$ran" -eq 0 ]]; then
  echo "${B}No test suites matched '${filter}'.${N}"
  exit 1
elif [[ "$failed" -eq 0 ]]; then
  echo "${G}${B}All $ran test suite(s) passed.${N}"
else
  echo "${R}${B}$failed of $ran test suite(s) failed.${N}"
fi
[[ "$failed" -eq 0 ]]
