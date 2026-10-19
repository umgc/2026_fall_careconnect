# PR 348 scan follow-up

Reviewed October 17, 2026, Eastern Time.

PR #348 is merged as `b79b9697`. Its latest Actions run is [39045003270](https://github.com/umgc/2026_fall_careconnect/actions/runs/39045003270), for head `aee43d5c`. GitHub records success. The downloaded report says BLOCKED, but the checked-in policy uses `report_only`, which lets the gate exit successfully despite findings. A successful check is not a clean scan.

## Comparison and fix

The comparison used the downloaded normalized findings, the PR diff, its pre-change Team C parent `36dbdf13`, and current Team C `3a95cee5`. Findings were matched by file and changed line; the affected Java file was also scanned before and after with the same Checkstyle 10.12.4 Google rules and PMD 6.55.0 categories as CI.

| Check | Before PR 348 | PR 348 | Follow-up |
| --- | ---: | ---: | ---: |
| Checkstyle, SchemaPatchRunner | 889 | 893 | 889 |
| PMD, SchemaPatchRunner | 81 | 81 | 81 |

Four Checkstyle findings were on newly added lines: two method-body indentation warnings and two lines over 100 characters. This follow-up changes only the two new generated-column calls. SQL contents and H2 behavior stay the same. Existing file-wide style debt remains visible. No gate rule, threshold, or suppression changed.

The scan had 976 findings in files touched by PR 348: 893 Checkstyle, 81 PMD, and two Semgrep findings. The two Semgrep findings point to older SQL-formatting code, not the new constant SQL. No secret alert pointed to a file changed by PR 348. This does not clear the repository's secret alerts or prove all of them false. Other repository-wide findings remain outside this fix.

All seven H2 held-item and consent regression tests passed after the formatting fix, with no failures, errors, or skips. These checks cover duplicate rejection, inactive history, distinct patient keys, and replay. They do not prove PostgreSQL or live deployment behavior.

## Sync branch review

The reviewed sync head is `092fd673`, on `chore/team-c-sync-develop-20261016`. It contains Team C `3a95cee5`, synchronized develop `fa542947`, and the heads of Terence's merged Team C work in PRs #79, #157, #158, #201, #330, #331, #347, #348, and #349. The earlier closed PR #148 head is also in its history through later integration; that does not change its closed-without-merge PR state.

The Cerner mapper/controller/HTTP client and their tests match current Team C. Storage code was adapted to the shared canonical model. The H2 schema uses generated boolean flags in place of Team C's generated nullable text keys; the same seven regression tests pass. The locale provider has formatting changes. The language-picker test moved to `test/widgets/language/language_picker_test.dart` with an identical Git blob, including the visible-text switch test.

Focused sync results:

- 150 backend tests passed: H2 held-item/consent, allergy mapper/controller/configuration/fixtures/HTTP error paths, resource mapper, and storage adapter. No failures, errors, or skips.
- 89 language tests passed after `flutter gen-l10n`, using the moved test path.
- Focused Flutter analysis of five files found no issues.
- No source conflict markers were found in the reviewed paths. The branch-wide whitespace diff is not clean: 49 diagnostics remain even when CRLF line endings are allowed. They are outside this follow-up.

Flutter dependency setup refreshed several local lock entries for the installed SDK. The resolved diff was saved in the local evidence folder and the tracked lock file was restored after testing. The 89 passes therefore apply to that local resolved environment, not a locked CI reproduction.

Terence's Team E Medicare-sharing fix `76582ea5` from PR #350 is not in the sync history. Its new sharing page/service files are absent. That separate Team E feature has not been copied into this Team C follow-up.

These are focused checks. They do not establish full regression, manual accessibility, live EHR connectivity, or release acceptance. Raw scan artifacts are kept in the local course evidence folder; secret values are not copied into this document.
