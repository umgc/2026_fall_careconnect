# PR 148 CI diagnosis

Elapsed: approximately 3 minutes. September 17, 2026.
Work: Read live bot comment, PR head and check state; downloaded run 35249833864 artifacts; inspected mapper-specific PMD and Checkstyle results and workflow rule selection; verified merge-test SHA.

PR head remains 987b60c265a7b01e2daafacb05a1bb33311adfb1. Report SHA 5f5f868 is a GitHub merge-test commit with the PR head and team-c-develop as parents; this is not an actual merged PR.

CI PMD has 102 mapper findings. Local Maven used quickstart.xml, while CI uses all bestpractices, errorprone and codestyle categories. Thus the earlier local no-findings result does not establish CI compliance. The 102 findings account for the increase from 16180 to 16282 in the supplied reports. Most are final declarations, single-return rules, naming, dataflow and literal conventions. CI Checkstyle lists the mapper with zero findings.

Other counts mostly match the prior report; stylelint increases by 2 and Trivy by 5. Those increases are not attributed to our code without a baseline finding-level comparison. Repository-wide issues are not fixed by this diagnosis. The bot says BLOCKED while the GitHub check concludes SUCCESS. Keep the PR in draft pending rule-aligned remediation and team review.

No code, scan rules, remote comments, merge settings or permissions changed in this diagnosis.
Source: https://github.com/umgc/2026_fall_careconnect/pull/148#issuecomment-5718271579
