# Cerner compatibility test results

Date: September 25, 2026 (America/New_York).

Command from `backend/core`:

```sh
mvn -B -o -Dtest=CernerResourceMapperTest,CernerStorageAdapterTest -Dcheckstyle.skip test
```

Result: BUILD SUCCESS; 79 tests, zero failures, errors, or skipped tests. This includes 57 mapper tests and 22 storage adapter tests. Maven compiled 946 production and 534 test sources. Run completed at 16:27:11 -04:00 in 55.571 seconds.

The initial sandboxed run passed 57 mapper tests, but the 22 adapter tests could not initialize Mockito because Java agent attachment was blocked. The same command passed outside the sandbox without changing the code.

Checkstyle was skipped for this focused prototype check. Full application tests, CI scanners, database transactions/concurrency, Spring wiring, and live Cerner access were not tested. Two characterization tests confirm existing shared mapper gaps; passing those tests does not fix the shared branch.

## Review publication

The September 24 review describes the original local-only state. On September 25, the user authorized pushing all unpushed work for review. This branch preserves the experiment for a draft review; it is not a production integration.

The 17 shared Java inputs were byte-checked against upstream commit `75b5f75505f6cb4e8c73070efe9d85ec41d7699b` and committed separately as dependency snapshots. They are other team members' existing work, not new code attributed to Terence. No schema migrations are included. Before any merge, replace this snapshot arrangement with the agreed shared dependency branch and review its Spring configuration and schema needs.
