# Unit Tests Overview

This repo ships a small, **dependency-free** unit-test suite for its two shell
scripts, `install.sh` and `python-env-report.sh`. Everything runs on the stock
macOS **bash 3.2** — no `bats`, no `brew install`, nothing to set up.

## Running the tests

```bash
./tests/run.sh              # run every suite
./tests/run.sh install      # run only suites whose filename matches "install"
./tests/run.sh python       # run only the python-env-report suite
```

`run.sh` exits non-zero if any test fails, so it works as a CI gate. You can also
run a single suite directly:

```bash
bash tests/test_install.sh
bash tests/test_python_env_report.sh
```

## Layout

| File | What it is |
|------|------------|
| `tests/lib.sh` | The harness: assertions + a `run_tests` discovery/runner |
| `tests/run.sh` | Runs all `tests/test_*.sh` files and aggregates the result |
| `tests/test_install.sh` | 21 tests for `install.sh` |
| `tests/test_python_env_report.sh` | 25 tests for `python-env-report.sh` |

**46 tests total.**

## How it works

Both scripts are structured so their functions live at the top level and all
side-effecting work happens inside a `main()` guarded by:

```bash
if ! (return 0 2>/dev/null); then main "$@"; fi
```

`return` outside a function only succeeds when a file is **sourced**, so `main`
runs when the script is executed or piped (`curl … | bash`) but **not** when a
test sources it. That lets the tests call individual functions (`deploy_config`,
`confirm`, `ver`, …) in isolation without installing anything.

Each `test_*` function runs in its own subshell, so `cd`, `HOME`/`SCRIPT_DIR`
overrides, and mocked commands never leak between tests. The first failing
assertion aborts that test and prints a diff-style message.

### Assertions (in `tests/lib.sh`)

| Assertion | Checks |
|-----------|--------|
| `assert_eq EXPECTED ACTUAL` | string equality |
| `assert_contains HAY NEEDLE` | substring present |
| `assert_not_contains HAY NEEDLE` | substring absent |
| `assert_status EXPECTED ACTUAL` | exit-code equality |
| `assert_file PATH` / `assert_no_file PATH` | file exists / doesn't |
| `capture PREFIX cmd…` | run `cmd`, store `${PREFIX}_out` + `${PREFIX}_rc` without tripping `set -e` |

## `install.sh` — what's covered

### Flag parsing
- `test_defaults_are_off` — `INSTALL_ALL`/`SKIP_AI` default to `0`.
- `test_parse_args_all` — `--all` sets `INSTALL_ALL`, leaves `SKIP_AI` off.
- `test_parse_args_no_ai` — `--no-ai` sets `SKIP_AI`.
- `test_help_flag_exits_zero_with_usage` — `--help` exits `0` and prints the usage block.
- `test_unknown_flag_exits_one` — an unknown flag exits `1` with an explanation.

### `confirm`
- `test_confirm_yes_when_install_all` — `--all` auto-confirms (returns 0).
- `test_confirm_no_when_skip_ai` — `--no-ai` auto-declines (returns 1).
- `test_confirm_no_on_non_tty` — non-interactive stdin declines by default.
- *Not unit-tested:* the interactive `y/N` read path, which requires a real TTY.

### `deploy_config` (config deployment + backup logic — the highest-value edge cases)
- `test_deploy_missing_source_warns_and_skips` — missing source → warn, no destination, non-fatal.
- `test_deploy_empty_script_dir_skips` — empty `SCRIPT_DIR` (the `curl | bash` case) → treated as "not found".
- `test_deploy_creates_new_file` — absent destination → file copied, "Deployed" reported.
- `test_deploy_identical_is_noop_no_backup` — identical destination → left untouched, **no** backup.
- `test_deploy_differing_backs_up_then_replaces` — differing destination → exactly one `*.bak.*` created holding the old content, destination replaced.
- `test_deploy_creates_nested_destination_dir` — nested destination path is `mkdir -p`'d before copy.

### Output helpers & installers
- `test_info_ok_warn_carry_message` — `info`/`ok`/`warn` echo their message.
- `test_die_exits_one_with_message` — `die` exits `1` and reports the reason.
- `test_install_formula_skips_when_present` — with `brew` mocked as "installed", no install runs.
- `test_install_formula_installs_when_missing` — with `brew` mocked as "missing", `brew install <formula>` is called.
- `test_install_cask_installs_when_missing` — `brew install --cask <cask>` is called for a missing cask.

> The `install_formula`/`install_cask` tests shadow the real `brew`
> with a shell function, so nothing is actually installed.

## `python-env-report.sh` — what's covered

### `realpath_p` (symlink resolution — macOS lacks `readlink -f`)
- `test_realpath_p_plain_file_unchanged` — a non-symlink is returned as-is.
- `test_realpath_p_single_symlink` — one hop resolves to its target.
- `test_realpath_p_chained_symlinks` — `a → b → c` resolves to `c`.
- `test_realpath_p_relative_symlink` — a relative link resolves against its own directory.

### `ver` (version string parsing)
- `test_ver_parses_stdout_version` — `Python 3.13.13` on stdout → `3.13.13`.
- `test_ver_parses_stderr_version` — older pythons print `--version` to stderr; still parsed (merged via `2>&1`).

### `mm_of` (major.minor extraction)
- `test_mm_of_full_version` — `3.13.13` → `3.13`.
- `test_mm_of_two_digit_minor` — `3.9.6` → `3.9`.
- `test_mm_of_empty_is_empty` — empty input → empty output.
- `test_mm_of_major_only_is_empty` — `3` (no minor) → empty.

### PATH and Homebrew probe safety
- Duplicate and missing PATH entries are reported.
- Successful Homebrew probes distinguish dependents from an empty result.
- Failed Homebrew probes remain `unknown`, even when failure writes to stdout.
- Failed uv inventory remains `unknown` and retains a diagnostic reason.
- Active and split Conda command resolution are distinguished.

### `summarize_overlap` (manager-aware installation overlap)
- One provider is named without suggesting removal.
- Multiple managers for the same series are counted and named.
- Matching versions explicitly do not imply that an installation is removable.
- Blank input produces no summary lines.

### Black-box behavior
- `test_report_runs_and_has_sections` — executing the script exits `0` and prints the header, overlap section, and read-only footer.
- `test_sourcing_does_not_run_report` — sourcing the script defines its functions **without** emitting the report (proves the `main()` guard works).

## Adding a test

1. Add a `test_<name>` function to the relevant `tests/test_*.sh` file (or create a new `tests/test_<suite>.sh` that sources `lib.sh` and ends with `run_tests`).
2. Use the assertions above; call `load` first if you need the target script's functions.
3. Run `./tests/run.sh` — new `test_*` functions are discovered automatically.
