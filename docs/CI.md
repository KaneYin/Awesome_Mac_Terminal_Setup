# Continuous Integration Overview

This repo runs its shell unit-test suite on GitHub Actions. The pipeline is
**deliberately simple**: check out the repo, print the bash version, run the
tests on two operating systems. No caching, no artifacts, no deploy.

For *what* the tests cover, see [`docs/TESTING.md`](TESTING.md) — this doc is
about *how CI runs them*. The single workflow lives at
[`.github/workflows/tests.yml`](../.github/workflows/tests.yml).

## What triggers it

```yaml
on: [push, pull_request]
```

The workflow runs on **every push** and **every pull request**. In practice:

- Pushing any branch (including a feature branch) kicks off a run.
- Opening or updating a PR kicks off a run against the proposed merge.

A green run does **not** by itself prevent a red PR from being merged into
`main` — that requires branch protection with a required status check, which is
**optional and not currently configured** (see [Adding branch
protection](#adding-branch-protection) below). Today CI is advisory: it tells
you whether the tests pass, but it doesn't block the merge button.

## What it does

Each job runs three steps:

1. **Check out the repository** — `actions/checkout@v4`.
2. **Show the bash version under test** — `bash --version`, so the logs record
   exactly which bash the tests ran on.
3. **Run the test suite** — `bash tests/run.sh`.

`tests/run.sh` discovers and runs every `tests/test_*.sh` suite and aggregates
the result. If any assertion in any suite fails, `run.sh` exits non-zero, which
makes the step fail and the whole job go red. Green means every suite passed.

## The OS matrix

```yaml
strategy:
  fail-fast: false
  matrix:
    os: [ubuntu-latest, macos-latest]
```

| OS | Role | bash |
|----|------|------|
| `ubuntu-latest` | Fast Linux sanity check | bash 5 |
| `macos-latest` | The real target platform | **bash 3.2** |

Why both:

- **ubuntu-latest** is a quick, modern-bash smoke test — it catches obvious
  breakage fast.
- **macos-latest** is the platform this setup actually targets, and GitHub's
  macOS runners still ship the **stock bash 3.2** these scripts must support.
  This is the authoritative leg for macOS-specific behavior.

`fail-fast: false` means the two legs are independent: if one OS fails, the
other still runs to completion and reports its own result. You always see the
status of both, rather than having one cancel the other.

## Concurrency

```yaml
concurrency:
  group: tests-${{ github.ref }}
  cancel-in-progress: true
```

If you push again to the same ref while an earlier run is still in progress, the
older run is cancelled. This avoids wasting Actions minutes on results you're
about to supersede.

## Actions used and pinning

The only external action is **`actions/checkout@v4`**, pinned to a major
version. Pinning (rather than tracking an unpinned/floating tag) means a new
minor/patch release can't silently change build behavior underneath you — you
opt into `v5` deliberately when it lands.

## Running the same checks locally

CI runs `bash tests/run.sh` verbatim, so **green locally ≈ green in CI** —
there's no separate CI-only command to reason about.

```bash
./tests/run.sh              # run every suite
./tests/run.sh install      # run only suites whose filename matches "install"
```

If you're on macOS you're already running against the authoritative **bash
3.2**, so a local pass is the strongest signal short of pushing. See
[`docs/TESTING.md`](TESTING.md) for how to run a single suite directly.

## Reading a failed run

1. Open the **Actions** tab on GitHub and click the failed run (a red ✕).
2. Pick the OS leg you care about — for anything macOS-specific, trust the
   **macos-latest** leg, since it's the one on bash 3.2.
3. Expand the **Run the test suite** step. The failing suite prints
   `FAIL <test_name>` followed by an indented, diff-style message (e.g.
   `assert_eq` with `expected:` / `actual:` lines) showing exactly what
   diverged.

Because the two legs are independent, a failure on only one OS usually points at
platform-specific behavior (often a bash 3.2 vs bash 5 difference).

## Extending CI

- **Adding a test:** drop a new `tests/test_*.sh` file in place. `run.sh`
  discovers it automatically — **no workflow edit is needed**.
- **Adding a new check (e.g. linting):** if you later want something like
  `shellcheck`, add it as an extra `step` (or a separate `job`) in
  `.github/workflows/tests.yml`. This is **not** part of the pipeline today; the
  workflow only runs the test suite.

## Adding branch protection

To actually *block* merges into `main` on a red run, enable a **required status
check** in the repo's branch-protection settings (GitHub UI: Settings →
Branches → Branch protection rules → require status checks to pass). Pick the
`Shell unit tests` job(s) as required. This is **optional and currently not
enabled** — without it, CI reports status but does not gate merges.
