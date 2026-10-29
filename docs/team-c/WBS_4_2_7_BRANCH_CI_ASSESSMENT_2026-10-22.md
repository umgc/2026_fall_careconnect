# WBS 4.2.7 — branch and CI assessment

Checked October 22, 2026 (EDT). Prepared for Terence Boyce.

The available branch-control evidence has been collected. Detailed enforcement settings still need a maintainer's confirmation. Keep 4.2.7 **In Work / 75%**. This report does not close the full build and CI task.

## Verified findings

| Check | Result | Meaning |
| --- | --- | --- |
| Shared branch | `team-c-develop` at `21d5a521e87f70eb9c304bd5d993d24cdad9adad` | Current shared reference for this assessment. |
| Branch protection flag | GitHub branch endpoint reports `protected: true`. | Protection exists. This does not reveal all enforcement details. |
| Detailed protection | Protection endpoint returns HTTP 404. Account has push/triage access, but neither maintain nor admin access. | Detailed protection remains unverified. A 404 does not prove there is no protection. |
| Effective branch rules and rulesets | Both readable endpoints return empty arrays. | No rules were returned through these endpoints. Classic protection and its settings remain unresolved. |
| Branch summary | `enforcement_level: off`, empty status contexts/checks. | This summary is not enough to certify the complete protection policy. |
| Current shared SHA checks | Check-runs: zero. Commit statuses: zero, aggregate `pending`. | No successful check evidence was returned for this exact SHA. This is not a failed test run. |
| Earlier merge CI | [Run 39492352193](https://github.com/umgc/2026_fall_careconnect/actions/runs/39492352193) succeeded at `29ca58e49ab757595061a94ecfcf8b34af789007`. | Valid older evidence, not proof for current `21d5a521` or the final candidate. |
| Cerner feature | [PR #391](https://github.com/umgc/2026_fall_careconnect/pull/391) is open at `0c991bb525fefbdbbed478441450f56fe828d4e9`. Feature CI and quality-gate checks succeeded. | Feature check success does not prove post-merge acceptance. |

## Workflow inspection

Workflow source and quality policy were read at `21d5a521` and saved in the evidence folder.

- `team-merge-ci.yml` runs for pull requests into `team-*-develop`. It builds backend/web, maps changed files to tests, and applies changed-line coverage checks. It has explicit exemptions and a validated upstream-sync path. It is not a full final-release test suite.
- `develop-merge-ci.yml` runs on pull requests into `develop`. It is distinct from the feature-to-Team-C workflow.
- `branch-source-gate.yml` checks source branches for pull requests into `develop` and `staging`. It does not establish a source-branch rule for pull requests into `team-c-develop`.
- `build-and-analyze.yml` runs the quality gate. The saved `quality/ci/gate/policy.yaml` sets `gate.mode: report_only`. A successful quality-gate result alone does not show that findings block a merge.
- Workflow code shows what jobs are set up to do. It does not prove that GitHub requires those jobs before merging.

Source links: [workflow directory](https://github.com/umgc/2026_fall_careconnect/tree/21d5a521e87f70eb9c304bd5d993d24cdad9adad/.github/workflows), [quality policy](https://github.com/umgc/2026_fall_careconnect/blob/21d5a521e87f70eb9c304bd5d993d24cdad9adad/quality/ci/gate/policy.yaml).

## Request for Jonathan or a repository administrator

Maintainer confirmation requested through this PR. No separate chat message has been sent.

> Jonathan, I completed the accessible branch/CI evidence check for WBS 4.2.7. GitHub marks team-c-develop as protected, but my account gets a 404 for the detailed protection settings. Could you provide a dated screenshot or export of the rules that apply to that branch? Please include required check names, PR approval count, stale-review dismissal, code-owner review, latest-push approval, resolved conversations, up-to-date branch requirements, admin/bypass rules, and force-push/deletion settings. Please also confirm which checks are intended to block merging. The current quality policy is report_only. Once #391 is merged, please confirm the resulting team-c-develop SHA for Tiffany's final testing.

## Remaining work before task closure

1. Obtain and assess the maintainer's settings evidence. Record gaps and the owner's decision; do not change repository protections as part of this assessment.
2. Confirm the final candidate after PR #391 review/merge.
3. Link candidate-specific builds, full-suite results, failures, defect decisions, and artifacts. Reuse existing results only when the SHA and coverage match.
4. Obtain the required independent review and acceptance.

## Evidence and scope

Raw API responses, CI metadata, and pinned workflow/policy copies: [evidence folder](evidence/branch-ci-2026-10-22/).

The workflow copies are evidence only and are outside `.github/workflows`. No application tests were executed for this audit. This PR changes documentation only. It does not change repository settings or application behavior. No new labor hours or task closure are claimed.
