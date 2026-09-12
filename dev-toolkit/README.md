# CareConnect Dev Toolkit

`dev-toolkit/` is a parallel Go-based terminal front door for local CareConnect
development. It wraps existing scripts without replacing or editing them.

The goal is a friendly first stop for developers who do not remember whether a
task lives in `backend/core`, `quality`, `scripts`, or
`cloudformation-fargate`.

## What It Does

- Presents a simple categorized terminal menu.
- Shows the exact command and working directory before running anything.
- Shows relevant `.env` and shell environment values with secrets masked.
- Wraps curated backend, database, quality, smoke-test, and CloudFormation
  workflows.
- Provides a script browser for `.sh`, `.ps1`, `.bat`, and `.py` helper scripts
  under the main developer-tooling directories.
- Adds a few native helpers, including backend health checks and a simple dev
  patient registration workflow.

Known stale scripts are intentionally kept out of curated menus. For example,
`backend/core/test-ai-chat.sh` is hidden because it was found to target old AI
and auth endpoints.

## Installing Go

Only needed to build from source or run via `go run`. If you just want to *use*
the toolkit, `bootstrap` downloads a prebuilt binary and no Go install is
required — see [Bootstrap](#bootstrap).

### Windows

Pick one:

**Installer (simplest).** Download the `.msi` from <https://go.dev/dl/> and run
it. It installs to `C:\Program Files\Go` and adds `go` to `PATH`
automatically. **Close and reopen your terminal afterwards** — an already-open
PowerShell will not see the new `PATH`.

**winget:**

```powershell
winget install --id GoLang.Go -e
```

**Chocolatey:**

```powershell
choco install golang -y
```

Verify, in a *new* terminal:

```powershell
go version
```

Expect `go version go1.22` or newer. If you get
`'go' is not recognized as the name of a cmdlet`, the `PATH` change has not
reached that shell — reopen it, and if it still fails add `C:\Program Files\Go\bin`
to your user `PATH` manually via System Properties -> Environment Variables.

### macOS

```bash
brew install go
go version
```

### Linux

Use your distribution's package manager, or the official tarball from
<https://go.dev/dl/>. Distribution packages are often several releases behind;
check `go version` reports 1.22 or newer.

## Building From Source

The module has no third-party dependencies, so builds work offline and need no
`go mod download` step.

Build every supported target into `dist/`:

```bash
cd dev-toolkit
sh build.sh          # macOS / Linux / Git Bash
```

```powershell
cd dev-toolkit
.\build.ps1          # Windows PowerShell
```

Both scripts build all six targets and then run the matching bootstrap script,
which creates the repo-root launcher for the machine that ran the build. On
Apple Silicon macOS that looks like:

```text
dev-tool -> dev-toolkit/dist/careconnect-dev-toolkit-darwin-arm64
```

Outputs land in `dev-toolkit/dist/`:

- `careconnect-dev-toolkit-linux-amd64`
- `careconnect-dev-toolkit-linux-arm64`
- `careconnect-dev-toolkit-darwin-amd64`
- `careconnect-dev-toolkit-darwin-arm64`
- `careconnect-dev-toolkit-windows-amd64.exe`
- `careconnect-dev-toolkit-windows-arm64.exe`

`dist/` is gitignored: binaries ship as GitHub release assets rather than in
the repository, and bootstrap fetches the one matching your machine.

To build only for the current machine, skip the build scripts entirely and let
bootstrap do it — with no prebuilt binary present and no release available, it
compiles just the host target:

```bash
DEV_TOOLKIT_OFFLINE=1 sh dev-toolkit/bootstrap.sh
```

After **any** change to `internal/toolkit/catalog.json`, rebuild before using
`./dev-tool`. The catalog is compiled into the binary with `go:embed`, so a
stale `dist/` binary will not show new commands or inputs:

```bash
cd dev-toolkit
go test ./...        # catalog is validated by the Go tests
sh build.sh
```

## Run From Source

Install Go 1.22 or newer, then:

```bash
cd dev-toolkit
go run ./cmd/careconnect-dev
```

You can also run a specific command by id:

```bash
go run ./cmd/careconnect-dev --list
go run ./cmd/careconnect-dev --dry-run backend.start
go run ./cmd/careconnect-dev --run backend.health
```

The toolkit auto-detects the repository root when launched from anywhere inside
the repo. Use `--repo /path/to/2026_fall_careconnect` if needed.

### Skipping prompts with -set

If you already know which values you want for a command's inputs, pass them
with repeated `-set name=value` flags (use `--list` output's id, then check
the interactive prompts once to learn each input's name) — only the inputs
you set are skipped; anything left unset still prompts normally. Combine
with `--yes` to also skip the final "Run this command?" confirmation for a
fully non-interactive invocation:

```bash
go run ./cmd/careconnect-dev --run infra.deploy.app --yes \
  -set environment=dev \
  -set ai_enabled=true \
  -set ai_model=amazon.nova-lite-v1:0 \
  -set frontend_url=https://dev.example.amplifyapp.com \
  -set skip_build=true
```

Choice inputs accept either the literal value (`environment=dev`) or its
1-based menu index (`environment=1`). An unrecognized `-set` name prints a
warning (not an error) so a typo doesn't silently do nothing.

## Bootstrap

Bootstrap is the only step a developer needs after cloning:

```bash
sh dev-toolkit/bootstrap.sh
```

```powershell
.\dev-toolkit\bootstrap.ps1
```

It detects the host OS/architecture and obtains a binary in this order:

1. **Existing binary** in `dev-toolkit/dist/`. A local binary always wins, so
   `build.sh` / `build.ps1` — which call bootstrap after building — never
   re-download what they just produced.
2. **Release asset** downloaded from the GitHub release, into `dev-toolkit/dist/`.
   This is the normal path for a fresh clone and needs no Go toolchain.
3. **Local build from source**, for this platform only, when no release asset is
   available. Requires Go 1.22 or newer.

If all three fail, bootstrap exits non-zero and prints how to install Go or
download the binary by hand. It then creates the repo-root launcher.

### Bootstrap environment variables

| Variable | Default | Purpose |
| --- | --- | --- |
| `DEV_TOOLKIT_REPO` | `umgc/2026_fall_careconnect` | Repository to download release assets from. Point at a fork when testing. |
| `DEV_TOOLKIT_VERSION` | `latest` | Release tag to download. `latest` resolves to the newest published release. |
| `DEV_TOOLKIT_OFFLINE` | `0` | Set to `1` to skip the download and build from source directly. |

### Publishing release binaries

Build all six targets, then attach them to a release so that step 2 works for
everyone:

```bash
cd dev-toolkit && sh build.sh
gh release create v1.0.0 dist/careconnect-dev-toolkit-* \
  --repo umgc/2026_fall_careconnect \
  --title "dev-toolkit v1.0.0" \
  --notes "Prebuilt CareConnect dev toolkit binaries."
```

Asset names must match the `careconnect-dev-toolkit-<goos>-<goarch>[.exe]`
pattern that `build.sh` produces, since bootstrap derives the asset name from
the host platform.

## Run Binaries

Linux:

```bash
./dev-toolkit/dist/careconnect-dev-toolkit-linux-amd64
```

macOS Apple Silicon:

```bash
./dev-toolkit/dist/careconnect-dev-toolkit-darwin-arm64
```

macOS Intel:

```bash
./dev-toolkit/dist/careconnect-dev-toolkit-darwin-amd64
```

Windows:

```powershell
.\dev-toolkit\dist\careconnect-dev-toolkit-windows-amd64.exe
```

Run the binary from inside the repo, or pass `--repo` to point it at the repo
root.

After building on your machine, you can use the repo-root launcher:

```bash
./dev-tool
```

On Windows, `bootstrap.ps1` tries to create `dev-tool` as a symlink and always
creates `dev-tool.cmd` as a fallback launcher:

```powershell
.\dev-tool.cmd
```

## Command Matrix

Every catalog entry, the `dev-tool` invocation, and the underlying command it wraps.
Run `dev-tool` forms from the repository root; the raw forms already include any
`cd` the entry needs. Generated from `internal/toolkit/catalog.json` — regenerate this
section if you add or change an entry.

### Backend smoke tests

| Command | macOS / Linux | Windows | Inputs | Needs |
| --- | --- | --- | --- | --- |
| `smoke.register_patient` | _built-in Go action_ | _built-in Go action_ | — | — |
| `smoke.two_user_call` | `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/verify-two-user-call.ps1` | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\verify-two-user-call.ps1` | `base_url`, `end_call` | `powershell` |

### CloudFormation

| Command | macOS / Linux | Windows | Inputs | Needs |
| --- | --- | --- | --- | --- |
| `frontend.build_amplify_zip` | `cd frontend && bash build-amplify-zip.sh` | `cd frontend && powershell.exe -NoProfile -ExecutionPolicy Bypass -File build-amplify-zip.ps1` | `backend_url`, `app_domain`, `app_port` | `flutter` |
| `infra.deploy.app` | `bash cloudformation-fargate/cdeploy_app_only.sh` | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File cloudformation-fargate\cdeploy_app_only.ps1` | `environment`, `profile`, `region`, `image_tag`, `run_tests`, `ai_enabled`, `ai_model`, `frontend_url`, `skip_build` | `aws`, `docker`, `java` |
| `infra.deploy.full` | `bash cloudformation-fargate/cdeploy_cloudformation.sh` | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File cloudformation-fargate\cdeploy_cloudformation.ps1` | `environment`, `profile`, `region`, `image_tag`, `run_tests`, `ai_enabled`, `ai_model` | `aws`, `docker`, `java` |
| `infra.destroy` | `bash cloudformation-fargate/cdestroy_cloudformation.sh` | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File cloudformation-fargate\cdestroy_cloudformation.ps1` | `environment`, `profile`, `region`, `skip_ecr` | `aws` |

### Database

| Command | macOS / Linux | Windows | Inputs | Needs |
| --- | --- | --- | --- | --- |
| `db.dump` | `cd backend/core/pg_docker && bash scripts/dump-database.sh` | `cd backend/core/pg_docker && cmd /C scripts\dump-database.bat` | — | `docker` |
| `db.migrations` | `cd backend/core/pg_docker && bash scripts/run-migrations.sh` | `cd backend/core/pg_docker && cmd /C scripts\run-migrations.bat` | — | `docker` |
| `db.reset` | `cd backend/core/pg_docker && bash scripts/reset-database.sh` | `cd backend/core/pg_docker && cmd /C scripts\reset-database.bat` | — | `docker` |

### Local development

| Command | macOS / Linux | Windows | Inputs | Needs |
| --- | --- | --- | --- | --- |
| `backend.health` | _built-in Go action_ | _built-in Go action_ | — | — |
| `backend.security` | `cd backend/core && bash security-check.sh` | `cd backend/core && bash security-check.sh` | — | — |
| `backend.start` | `cd backend/core && bash run-dev.sh` | `cd backend/core && cmd /C run-dev-win.bat` | — | `docker`, `java` |
| `frontend.start` | `cd frontend && bash startup.sh` | `cd frontend && bash startup.sh` | — | `flutter` |

### Quality

| Command | macOS / Linux | Windows | Inputs | Needs |
| --- | --- | --- | --- | --- |
| `quality.branch` | `bash scripts/check-branch-name.sh` | `bash scripts/check-branch-name.sh` | — | `git` |
| `quality.coverage.changed` | `python3 scripts/coverage_gate.py` | `py -3 scripts\coverage_gate.py` | `diff_base`, `threshold`, `jacoco`, `lcov`, `repo_root` | — |
| `quality.coverage.module` | `bash scripts/coverage-gate.sh` | `bash scripts/coverage-gate.sh` | `repo_root` | — |
| `quality.local` | `sh quality/Local_Scans/run-local-checks.sh` | `cmd /C quality\Local_Scans\run-local-checks.bat` | — | `java`, `flutter` |

### Scripts

| Command | macOS / Linux | Windows | Inputs | Needs |
| --- | --- | --- | --- | --- |
| `scripts.browser` | _built-in Go action_ | _built-in Go action_ | — | — |
| `scripts.pdf_docs` | `bash scripts/generate-pdf-copies.sh` | `bash scripts/generate-pdf-copies.sh` | — | `pandoc` |

### Testing

| Command | macOS / Linux | Windows | Inputs | Needs |
| --- | --- | --- | --- | --- |
| `backend.test` | `cd backend/core && ./mvnw test` | `cd backend/core && cmd /C mvnw.cmd test` | `tests` | `java` |
| `backend.test.coverage` | `cd backend/core && ./mvnw test jacoco:report` | `cd backend/core && cmd /C mvnw.cmd test jacoco:report` | `tests` | `java` |
| `frontend.test` | `cd frontend && flutter test` | `cd frontend && flutter test` | `target` | `flutter` |
| `frontend.test.coverage` | `cd frontend && flutter test --coverage` | `cd frontend && flutter test --coverage` | `target` | `flutter` |

### Toolkit

| Command | macOS / Linux | Windows | Inputs | Needs |
| --- | --- | --- | --- | --- |
| `toolkit.status` | _built-in Go action_ | _built-in Go action_ | — | — |

Pass inputs non-interactively with `--set name=value` (repeatable). A blank value
omits that input's arguments entirely, so `--set tests=` runs the full suite.
Add `--yes` to skip the confirmation prompt.
## Command Catalog

Curated menu items live in `internal/toolkit/catalog.json` and are embedded
into the compiled binary. To add a command:

1. Add an entry to `dev-toolkit/internal/toolkit/catalog.json`.
2. Prefer wrapping an existing script instead of reimplementing it.
3. Add `env_vars` for any values developers should verify before running.
4. Add `warnings` for destructive, costly, or long-running actions.
5. Run `go test ./...`.
6. Rebuild binaries with `sh build.sh` or `.\build.ps1`.

The JSON command shape supports:

- `shell.posix` and `shell.windows` argv arrays
- `working_dir`
- `inputs` of type `text`, `choice`, or `bool`
- `env_files` and `env_vars`
- `requires` dependency names
- `warnings`
- `platform_support`: `"native"` or `"posix"` — hand-curated, not automated;
  see [Curation: `platform_support`](#curation-platform_support) below
- `generate_secrets_file` and `generate_secrets`: offers to generate random
  values for missing secrets before a real run (see [Generated deploy
  secrets](#generated-deploy-secrets) below); `--dry-run` only warns, never
  writes
- native `action` values for Go-implemented helpers

### Curation: `platform_support`

Every catalog entry must set `platform_support` to either:

- `"native"` — a true equivalent exists on every platform: separate real
  `.ps1`/`.bat`/`python` commands for `shell.windows` vs `shell.posix`, or a
  native Go `action` (which is cross-platform by construction).
- `"posix"` — `shell.windows` just re-invokes the same bash script as
  `shell.posix` (`["bash", "same-script.sh"]`), so it only works on Windows
  with Git Bash or another bash-compatible shell installed. Pair this with a
  `warnings` entry saying so.

This is documentation, not a gate — nothing in the toolkit reads
`platform_support` to hide or block a command on either OS; it's a quick,
at-a-glance signal for `--list` output and for whoever's curating the catalog
next. `TestEveryCommandHasCuratedPlatformSupport` fails the build if a new
entry lands without setting one of the two values, so it can't be forgotten.

### Generated deploy secrets

A command can declare `generate_secrets_file` (a path relative to the repo
root) and `generate_secrets` (a list of `{"key": "ENV_VAR", "bytes": N}`
objects) to offer generating missing values before running. Currently only
`infra.deploy.full` uses this, for `CARECONNECT_DATABASE_MASTER_PASSWORD`
(16 bytes) and `CARECONNECT_JWT_SECRET` (32 bytes) — see
[`cloudformation-fargate/.env.example`](../cloudformation-fargate/.env.example).

On a real run (`--run`), if any listed key is unset both in the current shell
and in the target file, the toolkit names the missing keys and requires an
explicit `y` confirmation before generating (`crypto/rand`, hex-encoded) and
writing them — it never generates silently, and it never prints the
generated values back to the terminal. Declining just skips the step; the
command still runs and any downstream check (e.g. the deploy script's own
placeholder guard) still applies. On `--dry-run`, the same missing-key check
runs but only prints a warning — no prompt, no file write, matching
dry-run's no-side-effects contract.

## Native Actions

Native actions are implemented in `internal/toolkit`:

- `health` checks `GET /v1/api/test/health`.
- `register-patient` posts a simple patient registration payload to
  `/v1/api/auth/register`.
- `browse-scripts` discovers helper scripts in the developer-tooling
  directories.
- `status` prints platform, branch, dependency availability, and backend health.

Backend health defaults to `http://localhost:8080`. Override with one of:

- `CARECONNECT_DEV_TOOLKIT_BASE_URL`
- `BACKEND_BASE_URL`
- `BASE_URL`
- `SERVER_PORT` in `backend/core/.env`

## Source Layout

```text
dev-toolkit/
├── cmd/careconnect-dev/      CLI entry point
├── internal/toolkit/         menu, command runner, env preview, native helpers
│   └── catalog.json          curated command catalog embedded at build time
├── bootstrap.sh              POSIX launcher selector
├── bootstrap.ps1             PowerShell launcher selector
├── build.sh                  POSIX build script
├── build.ps1                 Windows PowerShell build script
└── README.md                 maintainer guide
```

## Safety Boundaries

This toolkit does not replace existing scripts. It shells out to them after
preview and confirmation.

CloudFormation actions still run the existing deployment scripts and can create,
update, or delete AWS resources. The toolkit prompts for environment/profile and
requires confirmation, but it does not make deployment safe by itself.

Database reset is destructive for the local PostgreSQL Docker volume and is
also confirmation-gated.

## Git Symlink Note

Git can store symlinks, and a relative symlink usually works after clone on
Linux and macOS when its target is committed. Windows support depends on
`core.symlinks`, Developer Mode or elevated permissions, and the checkout
environment. Some Windows clones receive a plain text file instead of a real
link.

The generated `dev-tool` link points at the current builder's OS/architecture
binary. Committing that link would make the repo-root launcher platform-specific
for everyone else. Prefer treating it as a generated local convenience. If the
team wants a committed root entry point later, use a tiny wrapper script that
selects the right binary at runtime.
