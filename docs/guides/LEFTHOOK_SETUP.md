# Pre-Commit Hooks Setup (lefthook)

CareConnect uses [**lefthook**](https://github.com/evilmartians/lefthook) to run
local quality checks before every commit and push. The config is committed to the
repo (`lefthook.yml`) so everyone gets the same hooks.

---

## What runs and when

| Hook | Checks | Effect |
|---|---|---|
| `pre-commit` | Dart format, Flutter analyze, Maven compile | Blocks commit on failure |
| `commit-msg` | Commit message format `<type>: <description>` | Warns only — commit still proceeds |
| `pre-push` | Branch name must match `<type>/<team>-*` | Blocks push on bad branch name |

**Commit message allowed types:** `feat`, `feature`, `fix`, `hotfix`, `chore`, `docs`, `test`

**Branch allowed types:** `feature`, `fix`, `hotfix`, `chore`, `docs`, `test`  
**Branch allowed teams:** `a`, `b`, `c`, `d`, `e`

| Type | When to use |
|---|---|
| `feature/` | New functionality |
| `fix/` | Non-urgent bug fixes |
| `hotfix/` | Urgent production fixes |
| `chore/` | Maintenance, dependency updates, config, refactoring |
| `docs/` | Documentation only |
| `test/` | Adding or fixing tests |

Tests are intentionally excluded — they run in CI on every PR to keep the hook fast.

---

## Step 1 — Install lefthook

### Windows

**Option A — winget (recommended)**
Open PowerShell or Command Prompt (not Git Bash):
```powershell
winget install evilmartians.lefthook
```
After install, **close and reopen your terminal** so the PATH update takes effect.

**Option B — scoop**
```powershell
scoop install lefthook
```

**Option C — direct binary**
In PowerShell (no package manager needed):
```powershell
Invoke-WebRequest `
  -Uri "https://github.com/evilmartians/lefthook/releases/latest/download/lefthook_windows_amd64.exe" `
  -OutFile "C:\Windows\System32\lefthook.exe"
```
No restart needed — it's immediately on PATH.

---

### macOS

**Option A — Homebrew (recommended)**
```bash
brew install lefthook
```

**Option B — curl**
```bash
curl -sSL \
  https://github.com/evilmartians/lefthook/releases/latest/download/lefthook_darwin_arm64 \
  -o /usr/local/bin/lefthook && chmod +x /usr/local/bin/lefthook
```
> Use `lefthook_darwin_amd64` if you're on an Intel Mac.

---

### Linux

**Option A — curl (any distro)**
```bash
curl -sSL \
  https://github.com/evilmartians/lefthook/releases/latest/download/lefthook_linux_amd64 \
  -o /usr/local/bin/lefthook && chmod +x /usr/local/bin/lefthook
```

**Option B — apt (Debian/Ubuntu)**
```bash
curl -sSL https://packagecloud.io/evilmartians/lefthook/gpgkey | sudo apt-key add -
sudo add-apt-repository "deb https://packagecloud.io/evilmartians/lefthook/any/ any main"
sudo apt-get update
sudo apt-get install lefthook
```

---

## Step 2 — Activate the hooks

Run this **once** from the repo root after installing lefthook:

```bash
lefthook install
```

Expected output:
```
sync hooks: ✔️(pre-commit, pre-push)
```

That's it. The hooks are now active for every `git commit` and `git push`.

---

## Verifying the hooks work

### Test commit-msg — bad message (warns but still commits)

```bash
git commit --allow-empty -m "added some stuff"
```

Expected output:
```
🥊 lefthook  v2.x.x   hook: commit-msg

  ⚠️  WARNING: Commit message does not follow the recommended format.

  Recommended format:  <type>: <description>

  Allowed types:  feat, feature, fix, hotfix, chore, docs, test

  Examples:
    feat: add athenahealth patient fetch service
    fix: resolve null pointer in dashboard
    chore: update dependencies

  Your message: "added some stuff"
  Commit will proceed — please follow the convention going forward.
```

### Test commit-msg — good message (no warning)

```bash
git commit --allow-empty -m "feat: add athenahealth patient fetch"
# ✔ no warning, commits cleanly
```

### Test pre-push — bad branch name (should fail)

```bash
git checkout -b bad-branch-name
git commit --allow-empty -m "test: branch name check"
git push origin bad-branch-name
```

Expected output:
```
🥊 lefthook  v2.x.x   hook: pre-push

  ERROR: Branch name 'bad-branch-name' does not follow the required naming rules.

  Required pattern:  <type>/<team>-<description>

  Allowed types:  feature, fix, hotfix, chore, docs, test
  Allowed teams:  a, b, c, d, e

  Examples:
    feature/b-athena-patient-fetch
    fix/a-dashboard-null-pointer
    hotfix/c-auth-token-refresh
    chore/d-update-dependencies
    docs/b-update-api-guide
...
error: failed to push some refs
```

### Test pre-push — good branch name (should pass)

```bash
git checkout -b feature/b-test-hook
git commit --allow-empty -m "test: branch name check"
git push origin feature/b-test-hook
# ✔ passes through
```

### Cleanup test branches

```bash
git push origin --delete bad-branch-name
git push origin --delete feature/b-test-hook
git checkout feature/b-add-lefthook-precommit
git branch -D bad-branch-name feature/b-test-hook
```

---

## Skipping hooks (use sparingly)

If you need to bypass hooks for a genuine reason (e.g., WIP commit, fixing a
merge conflict):

```bash
git commit --no-verify -m "wip: ..."
git push --no-verify
```

Do not make `--no-verify` a habit. CI will still catch everything on the PR.

---

## Uninstalling

To remove hooks from your local `.git/hooks/` without deleting the config:

```bash
lefthook uninstall
```

To reinstall at any time:

```bash
lefthook install
```
