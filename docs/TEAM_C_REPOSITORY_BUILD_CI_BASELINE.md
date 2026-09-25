# Team C Repository, Build, and CI Baseline

**WBS:** C1.2.2  
**Assessment date:** 2026-09-03  
**Repository:** `umgc/2026_fall_careconnect`  
**Local checkout:** `/Volumes/TerenceB/SWEN670/2026_fall_careconnect`  
**Prepared for:** Terence Boyce, Technical Lead

## Status and scope

**Recommended WBS status: In Progress.** This assessment establishes a reproducible Flutter/macOS build and a focused localization test result, inventories the inherited CI configuration, and identifies initial gaps. It is not a clean-checkout, full-stack release qualification: the local checkout contains pre-existing user changes, the complete Flutter and Maven suites were not run in this assessment, and live GitHub branch-rule settings were not re-verified.

## Repository baseline

- Current branch: `main`.
- Current local HEAD: `6161f84671b656560752711268a7f738556b6ce6` (`Complete Team C localization architecture audit`, authored by `TBizzz46`, 2026-08-28).
- Upstream relationship observed: `main...origin/main [ahead 1]`.
- Origin: `https://github.com/umgc/2026_fall_careconnect.git`.
- The checkout was dirty before validation. Modified DOCX, Flutter configuration, Android Gradle, and macOS runner files plus untracked macOS/visualization files were present. They were preserved and are not claimed as output of this assessment.
- `git diff --check` returned no whitespace errors before and after validation.

## Reproducible validation performed

Run from `frontend/`:

```sh
flutter test test/l10n/app_localizations_test.dart test/providers/locale_provider_test.dart test/widgets/language_picker_test.dart
flutter build macos --debug
```

Observed results on 2026-09-03:

- Focused localization suite: **PASS — 88 tests passed**.
- macOS debug build: **PASS** — produced `build/macos/Build/Products/Debug/care_connect_app.app`.
- Build warning: seven plugins do not yet support Swift Package Manager for macOS; Flutter reports this will become an error in a future version. The current build still succeeded.
- No new tracked changes appeared in `git status --short` after validation.

## Inherited CI and protection evidence

- `.github/workflows/team-b-ci.yml` builds Flutter and Maven, compiles Flutter web, runs Flutter and Maven tests, produces coverage, runs a coverage gate, and includes later E2E/accessibility stages.
- Flutter analysis, Flutter unit tests, Flutter coverage, Maven unit tests, and Maven verification are configured with `continue-on-error: true`; those individual steps do not independently block a merge.
- `.github/workflows/build-and-analyze.yml` centralizes scanner output and policy evaluation, but its push trigger is scoped to Team D branches. Pull requests trigger it generally.
- `.github/CODEOWNERS` assigns repository-wide owners. This establishes review routing, not the live protected-branch rule set.
- A prior 2026-08-28 delivery attempt recorded a protected-branch rejection for direct `main` push. That is historical evidence only; current GitHub branch settings were not queried in this assessment.

## Initial gaps and required closure evidence

1. Repeat the build and test baseline from a clean clone or clean worktree at an approved commit.
2. Run and retain results for the full Flutter unit suite and backend Maven test/verify suite.
3. Run the web release build, because web conditional imports differ from native paths.
4. Make localization generation and catalog parity explicit blocking checks before focused localization tests.
5. Remove or justify `continue-on-error` for test and analysis steps whose failure must block delivery.
6. Confirm current required reviews and status checks from the live GitHub branch-protection settings.
7. Record tool versions, executor, date, commit, commands, exit results, and artifact links with the M1 evidence package.

## Evidence paths

- `docs/TEAM_C_FRONTEND_ARCHITECTURE_AUDIT.md`
- `docs/TEAM_C_L10N_AUDIT_COMPLETION_NOTE.md`
- `.github/workflows/team-b-ci.yml`
- `.github/workflows/build-and-analyze.yml`
- `.github/CODEOWNERS`
- `frontend/test/l10n/app_localizations_test.dart`
- `frontend/test/providers/locale_provider_test.dart`
- `frontend/test/widgets/language_picker_test.dart`

## Completion gate

C1.2.2 may move to **Complete** only after the clean-checkout full-stack validation and live branch-protection evidence above are attached and independently reviewed. The successful local macOS build and 88-test result are evidence of progress, not proof of the entire acceptance condition.
