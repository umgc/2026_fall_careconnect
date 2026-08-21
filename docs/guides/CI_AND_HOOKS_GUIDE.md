# CareConnect — CI & Developer Hooks Guide

This guide covers two complementary layers of quality enforcement:

- **Local hooks (lefthook)** — fast feedback before you commit or push
- **CI pipeline (GitHub Actions)** — the merge gate that runs on every PR

---

## Overview

### Local hooks (lefthook)

| Hook | Checks | Effect |
|---|---|---|
| `pre-commit` | Dart format, Flutter analyze, Maven compile | Blocks commit on failure |
| `commit-msg` | Commit message format `<type>: <description>` | Warns only — commit still proceeds |
| `pre-push` | Branch name pattern | Blocks push on bad branch name |

### CI pipeline (`team_b-ci-rules.yml`)

Triggers on every PR targeting `team-b-develop`. Runs once — no duplicate runs on push.

| Stage | What runs | Effect |
|---|---|---|
| Build | Flutter pub get, analyze, Maven compile, Flutter web build | Blocks PR on failure |
| Unit tests | Changed files only (Flutter + Maven) | Blocks PR on failure |
| Coverage gate | 95% line coverage on changed files | Blocks PR on failure |
| Artifacts | JaCoCo HTML, lcov, Surefire reports | Uploaded for inspection |

> Team D's `build-and-analyze.yml` runs security/SAST scans on **all PRs** repo-wide. It is separate from this pipeline and not duplicated here.

---

## Branch & Commit Naming Rules

### Branch names

Pattern: `<type>/<team>-<description>`

| Part | Allowed values |
|---|---|
| `<type>` | `feature`, `fix`, `hotfix`, `chore`, `docs`, `test` |
| `<team>` | `a`, `b`, `c`, `d`, `e` |
| `<description>` | kebab-case description |

| Type | When to use |
|---|---|
| `feature/` | New functionality |
| `fix/` | Non-urgent bug fixes |
| `hotfix/` | Urgent production fixes |
| `chore/` | Maintenance, dependency updates, config, refactoring |
| `docs/` | Documentation only |
| `test/` | Adding or fixing tests |

Examples:
```
feature/b-athena-patient-fetch
fix/a-dashboard-null-pointer
hotfix/c-auth-token-refresh
chore/d-update-dependencies
docs/b-update-api-guide
test/b-add-coverage-for-vitals
```

Shared branches (`team-b-develop`, `develop`, `main`) bypass the check.

### Commit messages

Pattern: `<type>: <description>`

Allowed types: `feat`, `feature`, `fix`, `hotfix`, `chore`, `docs`, `test`

Examples:
```
feat: add athenahealth patient fetch service
fix: resolve null pointer in dashboard
hotfix: patch auth token expiry bug
chore: update dependencies
docs: update API guide
test: add unit tests for vitals service
```

Commit message format is a **warning only** — the commit will proceed. Branch name is **enforced hard** on push.

---

## Local Hooks Setup (lefthook)

### Step 1 — Install lefthook

Lefthook is a single binary — no Node, Python, or Ruby runtime required.

**Windows — winget (recommended)**

Open PowerShell or Command Prompt (not Git Bash):
```powershell
winget install evilmartians.lefthook
```
After install, **close and reopen your terminal** so the PATH update takes effect.

**Windows — scoop**
```powershell
scoop install lefthook
```

**Windows — direct binary**

In PowerShell (no package manager needed):
```powershell
Invoke-WebRequest `
  -Uri "https://github.com/evilmartians/lefthook/releases/latest/download/lefthook_windows_amd64.exe" `
  -OutFile "C:\Windows\System32\lefthook.exe"
```
No restart needed — it's immediately on PATH.

**macOS — Homebrew (recommended)**
```bash
brew install lefthook
```

**macOS — curl**
```bash
curl -sSL \
  https://github.com/evilmartians/lefthook/releases/latest/download/lefthook_darwin_arm64 \
  -o /usr/local/bin/lefthook && chmod +x /usr/local/bin/lefthook
```
> Use `lefthook_darwin_amd64` for Intel Macs.

**Linux — curl (any distro)**
```bash
curl -sSL \
  https://github.com/evilmartians/lefthook/releases/latest/download/lefthook_linux_amd64 \
  -o /usr/local/bin/lefthook && chmod +x /usr/local/bin/lefthook
```

**Linux — apt (Debian/Ubuntu)**
```bash
curl -sSL https://packagecloud.io/evilmartians/lefthook/gpgkey | sudo apt-key add -
sudo add-apt-repository "deb https://packagecloud.io/evilmartians/lefthook/any/ any main"
sudo apt-get update
sudo apt-get install lefthook
```

---

### Step 2 — Activate the hooks

Run this **once** from the repo root:

```bash
lefthook install
```

Expected output:
```
sync hooks: ✔️(pre-commit, commit-msg, pre-push)
```

The hooks are now active for every `git commit` and `git push`.

---

### Skipping hooks (use sparingly)

```bash
git commit --no-verify -m "wip: ..."
git push --no-verify
```

Do not make `--no-verify` a habit. CI will still catch everything on the PR.

### Uninstalling

```bash
lefthook uninstall   # removes hooks from .git/hooks/
lefthook install     # reinstall at any time
```

---

## CI Pipeline

The CI pipeline runs on every PR targeting `team-b-develop`. It will not run on direct pushes to any branch.

### What triggers it

```yaml
on:
  pull_request:
    branches:
      - team-b-develop
```

### Stages

**Stage 1 — Build**
- `flutter pub get`
- `flutter analyze` (informational, non-blocking)
- `mvn compile -DskipTests`
- `flutter build web` (compile check)

**Stage 2 — Unit tests (changed files only)**

Maps changed source files to their test counterparts by naming convention:
- `frontend/lib/foo/bar.dart` → `frontend/test/foo/bar_test.dart`
- `backend/core/src/main/java/com/x/Foo.java` → `src/test/java/com/x/FooTest.java`

If no files map to tests, the step skips gracefully. If tests are found and fail, the PR is blocked.

**Stage 3 — Coverage gate (95% threshold)**

After tests run, `scripts/coverage_gate.py` checks line coverage on changed files only:
- Java: reads `target/site/jacoco/jacoco.xml` (generated by JaCoCo)
- Flutter: reads `coverage/lcov.info` (generated by `flutter test --coverage`)

If any changed file is below 95% line coverage, the PR is blocked with a clear list of failing files.

**Stage 4 — Artifacts**

Uploaded on every run (including failures) for inspection:
- `backend/core/target/surefire-reports/`
- `backend/core/target/site/jacoco/`
- `frontend/test-results/`
- `frontend/coverage/`

Retained for 14 days.

---

## Testing the hooks

### commit-msg — bad message (warns, still commits)

```bash
git commit --allow-empty -m "added some stuff"
```

Expected:
```
⚠️  WARNING: Commit message does not follow the recommended format.
  Your message: "added some stuff"
  Commit will proceed — please follow the convention going forward.
```

### commit-msg — good message (no warning)

```bash
git commit --allow-empty -m "feat: add athenahealth patient fetch"
# ✔ commits cleanly
```

### pre-push — bad branch name (blocked)

```bash
git checkout -b bad-branch-name
git commit --allow-empty -m "test: branch name check"
git push origin bad-branch-name
```

Expected:
```
ERROR: Branch name 'bad-branch-name' does not follow the required naming rules.
  Required pattern: <type>/<team>-<description>
  ...
error: failed to push some refs
```

### pre-push — good branch name (passes)

```bash
git checkout -b feature/b-test-hook
git push origin feature/b-test-hook
# ✔ passes
```

### Cleanup test branches

```bash
git push origin --delete bad-branch-name
git push origin --delete feature/b-test-hook
git branch -D bad-branch-name feature/b-test-hook
```
