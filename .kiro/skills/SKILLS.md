---
name: PR Review Skill
description: A structured human-in-the-loop workflow for reviewing pull requests, analyzing staged changes, and optionally implementing fixes. Runs five distinct review passes: security, code quality, architecture, test coverage, and AC coverage. Integrates GitHub and Jira.
---

# PR Review Skill

A structured human-in-the-loop workflow for reviewing pull requests, analyzing staged changes, and optionally implementing fixes. Runs five distinct review passes: security, code quality, architecture, test coverage, and AC coverage. Integrates GitHub and Jira.

## WHEN TO USE

Trigger this skill when the user asks to:

- "Check PRs" or "check prs"
- Review an open pull request
- Analyze staged/uncommitted changes before committing
- Check PR feedback or comments
- Implement fixes for review findings
- Approve or comment on a PR

---

## STAGE 0: Detect Project Context [WAIT FOR USER]

1. Run `git remote get-url origin` to detect the GitHub location. Parse it to extract:
   - `OWNER` — the org or user segment (e.g., HTTPS `https://github.com/acme-org/frontend.git` → `acme-org`; SSH `git@github.com:acme-org/frontend.git` → `acme-org`). For GitHub Enterprise, the host differs (e.g., `github.acme.com`) but the `OWNER/REPO` path is the same.
   - `REPO` — the repo name, with any trailing `.git` stripped (e.g., `frontend`)
2. If `git remote` fails or the URL doesn't match a GitHub pattern, fall back to `pwd` and ask the user for both `OWNER` and `REPO`.
3. Confirm with user:

```
Detected project: <OWNER>/<REPO>
Check PRs for this project? (yes/no)
```

4. WAIT. If "no", ask for the correct `OWNER` and `REPO`. If "yes", continue.
5. Use the confirmed `OWNER` and `REPO` for all GitHub API calls. Never hardcode either.

---

## STAGE 1: Choose Workflow Mode [WAIT FOR USER]

Present options:

```
1. Check PRs - Review open pull requests
2. Analyze staged changes - Analyze local staged/uncommitted changes
```

- Option 1 → Stage 2
- Option 2 → Run `git status` + `git diff --staged`, analyze for code quality/security/TypeScript issues, present findings, offer suggestions. END or loop back.

---

## STAGE 2: Present Open PRs [WAIT FOR USER]

Fetch with `mcp_github_list_pull_requests` (owner=`<OWNER>`, repo=`<REPO>`, state=open). If the user asked for PRs by a specific author (e.g., "My PRs"), use `mcp_github_search_pull_requests` instead — `list_pull_requests` does not filter by author. Show last 5 (or 3 if too large). Display: PR number, Title, Author, Head branch. WAIT for user to select a PR number.

---

## STAGE 3: Choose Review Mode [WAIT FOR USER]

```
1. Diff-only review - Faster, focused on changed lines
2. Full codebase review - Switch to branch, deeper analysis with lint + tests
```

- Option 1: Fetch diff via GitHub API only.
- Option 2: REQUIRES EXPLICIT PERMISSION. Ask before running any git commands:

```
To proceed, I need to: fetch origin, switch to <branch>, pull latest.
This will change your local working directory. Proceed? (yes/no)
```

If "no" → ask what to do next (option 1 or cancel). NEVER auto-fallback. If "yes" → `git fetch origin && git checkout <branch> && git pull origin <branch>`, then run lint and tests using the project's toolchain (see **Test Execution by Ecosystem** below).

---

## STAGE 4: Fetch PR Details & Jira Context [WAIT FOR USER]

1. Fetch via `mcp_github_pull_request_read` (one tool, `method` selects the data): `method=get` (PR details), `method=get_files` (changed files), `method=get_diff` (unified diff). Record the PR's `base` (target) branch and `head` SHA — the head SHA is needed as `commitID` when posting a review.
2. **Parse the diff to build a line map** for every changed file. GitHub anchors inline review comments to a position in the **diff** using `path` + `line` + `side`, where `line` is the line number in the **head (new) version** of the file and `side=RIGHT`. For comments on removed/context lines from the base version, use `side=LEFT`. Record, for each finding, the head-file `line` and the `side` — these come straight from the diff, not from a separately fetched file. (You may still fetch base-branch content via `mcp_github_get_file_contents` with `ref` = base branch for review *context*, but line numbers for comments come from the diff.)
3. Parse PR title/description for Jira key (e.g., `PROJ-1234`). If not found, ask user.
4. Resolve story summary and acceptance criteria — try in order: a. **Jira MCP available + key resolved**: fetch via `mcp_jira_get_issue`, extract summary and AC. b. **Jira MCP unavailable, OR `mcp_jira_get_issue` returned no issue, OR the issue has no AC section**: ask the user to paste the story summary and acceptance criteria:

```
Couldn't fetch Jira context (<reason: MCP not available | issue not found | no AC in ticket>).
Paste the story summary and acceptance criteria so I can run Pass E.
Or reply "skip" to skip AC coverage verification.
```

WAIT. If the user pastes content, treat it as the source-of-truth for Pass E (still cite ACs verbatim from what they provided). If "skip", set `JIRA_LINKED = false` and Pass E will be skipped per the conditional in Stage 6.
5. Detect UI ticket: check for `.tsx/.jsx/.css/.scss/.html` in changed files → set `IS_UI_TICKET = true`.
6. Present summary (PR title, Jira key if any, AC source: Jira / user-provided / skipped, AC list, changed files). WAIT for "yes/no".

---

## STAGE 5: Establish Coding Standards Baseline [AUTOMATIC]

Before reviewing, establish a coding standards baseline by sampling existing files in the same directories as the changed files. Identify:

- Naming conventions (camelCase, PascalCase, etc.)
- Logging patterns (which logger, what format)
- Error handling patterns (custom error classes, error codes)
- Comment style (JSDoc, inline)
- Import organization

How to fetch baseline files depends on Stage 3 mode:

- **Diff-only mode**: Use `mcp_github_get_file_contents` with `ref` = base branch to fetch 2-3 sibling files per changed directory (for convention context only — comment line numbers still come from the diff). Skip if >50 changed files (too expensive — fall back to inferring conventions from the diff itself).
- **Full codebase mode**: Read sibling files directly from the local checkout.

Store findings as context for Stage 6.

---

## STAGE 6: Code Review Analysis [AUTOMATIC — Five Passes]

> ⚠️ **LINE NUMBER RULE (applies to all passes)**: Every inline comment anchors to a position in the **PR diff**, not to a standalone file. Record for each finding: `path` (repo-relative, exactly as in the diff), `line` (the line number in the **head/new** version of the file for added or context lines), and `side` (`RIGHT` for the new version, `LEFT` for lines from the base version). GitHub only accepts comments on lines that appear in the diff — a `line`/`side` combination outside the diff hunks is rejected or silently dropped to a file-level comment. Take the `line` from the diff hunk's new-file numbering, not from the `@@ ... @@` hunk header itself.

Priority levels:

- **P1 Critical**: security, data loss, breaking changes, logic errors, missing security/auth/data-integrity ACs
- **P2 Important**: business logic, missing error handling, performance, dead code, missing/partial ACs
- **P3 Moderate**: coding standards, clean code, maintainability, missing tests, scope creep
- **P4 Minor**: naming, docs, style

### PASS A: Security Scan [MANDATORY]

Scan every changed file for security violations.

#### A1. Secrets & Credentials Detection

Scan the diff for accidentally committed secrets. Flag as **P1 Critical**:

- **API keys & tokens**: AWS access keys (`AKIA...`), GCP service account keys, Azure connection strings, JWT secrets, OAuth client secrets, Bearer tokens, Stripe/Twilio/SendGrid keys.
- **Passwords & connection strings**: Hardcoded passwords in source, database connection strings with embedded credentials, SMTP credentials, LDAP bind passwords.
- **Private keys**: RSA/EC private keys (`-----BEGIN RSA PRIVATE KEY-----`), SSH private keys, TLS certificates with private keys.
- **Environment leaks**: `.env` files committed, `application.properties` / `application.yml` with real credentials, Docker secrets in Dockerfiles, Kubernetes secrets in plain YAML.
- **Config files**: `web.config` with connection strings, `settings.json` with tokens, CI/CD pipeline files with inline secrets.

Detection patterns to search for in the diff:

- Strings matching `password\s*=\s*["'][^"']+["']`, `secret\s*[:=]`, `api[_-]?key\s*[:=]`, `token\s*[:=]`
- Base64-encoded blobs that decode to key-like strings
- High-entropy strings (>4.5 Shannon entropy) in assignment contexts
- Known key prefixes: `AKIA`, `sk_live_`, `sk_test_`, `ghp_`, `glpat-`, `xoxb-`, `xoxp-`

If secrets are found: recommend immediate rotation, `.gitignore` addition, and `git filter-branch` or BFG Repo-Cleaner to purge from history.

#### A2. OWASP Vulnerability Checklist

**Injection (A1)**: String concatenation in SQL/HQL/LDAP queries, unsanitized input in `eval()`, `exec()`, `shell_exec()`, `os.system()`, dynamic SQL in stored procedures, JSON parsed with `eval()` instead of `JSON.parse()`. Verify parameterized queries/prepared statements are used. Check ORM usage — Hibernate HQL and .NET Entity Framework can still be injectable with native SQL.

**Broken Auth & Session (A2)**: Hardcoded credentials, session tokens in URLs or logs, missing session invalidation on logout, session IDs that don't rotate after login, weak token generation (predictable, insufficient entropy, < 128 bits), missing MFA on sensitive operations, password stored without hashing.

**XSS (A3)**: User input rendered without encoding in HTML, JavaScript, URL, or CSS contexts. Check for `innerHTML`, `document.write()`, `dangerouslySetInnerHTML` (React), `[innerHTML]` (Angular), `v-html` (Vue). Verify output encoding matches context (HTML-encode for HTML body, JS-encode for script blocks, URL-encode for href attributes). Check Content-Security-Policy headers.

**Insecure Direct Object Reference (A4)**: User-controlled IDs in URLs/params without authorization checks. Verify the backend checks that the authenticated user owns/has access to the requested resource, not just that they're authenticated.

**Security Misconfiguration (A5)**: Debug mode enabled, default credentials, verbose error messages exposing stack traces/paths/SQL, directory listing enabled, unnecessary HTTP methods (PUT/DELETE), missing security headers (X-Content-Type-Options, X-Frame-Options, Strict-Transport-Security), CORS set to `*`.

**Sensitive Data Exposure (A6)**: Secrets in source code (API keys, passwords, connection strings), sensitive data logged (PII, tokens, passwords), missing encryption for data at rest or in transit, weak crypto algorithms (MD5, SHA1 for passwords — use bcrypt/scrypt/argon2), sensitive data in client-side storage (localStorage, cookies without Secure/HttpOnly flags).

**Missing Access Control (A7)**: Authorization checks only in the UI (not enforced server-side), missing role/permission checks on API endpoints, privilege escalation via parameter tampering (`role=admin`), unused/test endpoints exposed in production.

**CSRF (A8)**: State-changing operations (POST/PUT/DELETE) without anti-CSRF tokens, reliance on Referer header alone, SameSite cookie attribute not set.

#### A3. Advanced Vulnerability Hunting

When security-sensitive code is detected (auth, file handling, URL fetching, XML processing, template rendering, state-changing operations), apply these deeper checks:

- **SSRF**: URL-fetching features where user controls the target URL. Check for internal IP filtering bypasses (IP encoding, DNS rebinding, redirect chains, IPv6 `[::1]`). Cloud metadata endpoint access (`169.254.169.254`).
- **XXE**: XML parsing without disabled external entities. Check all XML upload paths (DOCX/XLSX via Office Open XML, SVG images, SOAP requests, RSS feeds, SAML assertions, GPX files).
- **Template Injection**: Server-side (SSTI) — user input in Jinja2/Twig/Freemarker/ERB templates. Client-side (CSTI) — user input in AngularJS/React/Vue template expressions. Test: `{{7*7}}`, `${7*7}`, `<%= 7*7 %>`.
- **Path Traversal**: User input in file paths. Check for `../` bypass techniques (URL encoding, double encoding, null byte truncation, nested sequences `....//`).
- **Race Conditions**: TOCTOU gaps in state-changing operations (check balance → withdraw). Concurrent request exploitation.
- **OS Command Injection**: User input passed to shell commands. Injection via `;`, `|`, `||`, `&&`, backticks, `$()`, newlines.

#### A4. Security Error Handling & Logging

- **Error handling**: Catch blocks that swallow exceptions silently, error messages that leak internal details (file paths, SQL queries, stack traces), missing generic error pages, `catch(Exception e)` that catches too broadly.
- **Logging**: Sensitive data in logs (passwords, tokens, PII), missing audit logging for auth events and access control failures, log injection via unsanitized user input in log messages.

### PASS B: Code Quality & Clean Code [MANDATORY]

Apply clean code principles. Prioritize readability — if a "clean" refactoring would make code harder to understand, it's not clean. Give concrete before/after examples in inline comments.

#### B1. Business Logic & Functionality

Logical errors, wrong AC implementation, dead code, race conditions, incorrect async/await, wrong return values.

> ⚠️ **TRACE BEFORE FLAGGING NULL/UNDEFINED**: Before flagging removed `?.` or null checks, trace the upstream method. If it throws on not-found, null is unreachable — do NOT flag it. Use local file search to verify.

#### B2. Error Handling & Resilience

- Missing try/catch, unhandled promises, silent failures.
- Use exceptions, not return codes. Return codes clutter the caller.
- Write try-catch-finally first — catch must leave the program in a consistent state.
- Provide context in exceptions — include the operation that failed and the type of failure.
- Wrap third-party APIs to return a single exception type — minimizes dependencies, simplifies mocking.
- Don't return null — return empty collections, Special Case objects, or throw.
- Don't pass null — forbid by convention.

#### B3. Performance

N+1 queries, memory leaks, unnecessary re-renders, inefficient algorithms.

#### B4. Coding Standards & Formatting

From Stage 5 baseline + clean code principles. Only flag clear inconsistencies, not minor style differences.

- **Naming deviations**: Inconsistent casing conventions, logging patterns, error handling patterns, import organization.
- **Vertical formatting**: Dependent functions should be close together — caller above callee. Variables declared far from usage. Conceptually related functions scattered across the file.
- **Horizontal formatting**: Lines exceeding project convention (aim 80-120 chars). Collapsed scopes on one line.
- **Newspaper rule**: High-level functions at top, detail increases downward.

#### B5. Naming

- **Intention-revealing**: If a name needs a comment to explain it, the name is wrong. `int d;` → `int elapsedTimeInDays;`
- **Disinformation**: `accountList` when it's not a `List`. Names that differ in tiny ways.
- **Meaningful distinctions**: `a1, a2` → `source, destination`. Noise words: `NameString` vs `Name`.
- **Pronounceable & searchable**: `genymdhms` → `generationTimestamp`. Magic numbers → named constants.
- **No encodings**: No Hungarian notation (`strName`), no member prefixes (`m_description`), no interface prefixes (`IShapeFactory`).

#### B6. Functions

- **Size**: Rarely over 20 lines. Blocks in `if`/`else`/`while` should be one line — probably a function call.
- **Do one thing**: If you can extract a function with a name that isn't a restatement of its implementation, the original does more than one thing.
- **One abstraction level per function**: Don't mix `getHtml()` (high) with `.append("\n")` (low).
- **Stepdown rule**: Code reads top-down. Each function introduces the next level of abstraction.
- **Arguments**: Zero is ideal, three is questionable. Group related params into argument objects. Flag arguments (`render(boolean isSuite)`) = function does two things.
- **No side effects**: `checkPassword` shouldn't initialize a session.
- **Command-query separation**: Functions either do something or answer something, not both.
- **Dead functions**: Never called → delete them.
- **Switch statements**: Should appear once, in an abstract factory. Prefer polymorphism.

#### B7. Comments

- **Redundant**: Restating what code already says (`// Returns the day of the month` above `getDayOfMonth()`).
- **Misleading**: Subtly inaccurate descriptions that cause debugging sessions.
- **Commented-out code**: Delete it. Version control remembers.
- **Journal comments**: Change logs in source files belong in version control.
- **Noise comments**: `/** Default constructor */`, `/** The name */`.
- **Replace with code**: `if ((employee.flags & HOURLY_FLAG) && (employee.age > 65))` → `if (employee.isEligibleForFullBenefits())`.
- **Acceptable**: Legal headers, explanation of intent, clarification of obscure library returns, warning of consequences, TODOs (if actionable), public API Javadocs.

#### B8. Objects, Data Structures & Law of Demeter

- **Train wrecks**: `ctxt.getOptions().getScratchDir().getAbsolutePath()` violates Law of Demeter. Tell the object to do something: `ctxt.createScratchFileStream(classFileName)`.
- **Hybrids**: Half object, half data structure — worst of both worlds.
- **Feature envy**: Method uses another class's data more than its own — move it or extract.
- **Encapsulate conditionals**: `if (shouldBeDeleted(timer))` not `if (timer.hasExpired() && !timer.isRecurrent())`.
- **Encapsulate boundary conditions**: `nextLevel = level + 1` — put boundary math in a named variable.

#### B9. Classes & Design

- **SRP**: Can't describe the class in 25 words without "and" → too many responsibilities. Extract.
- **Cohesion**: When a subset of variables is used by a subset of methods → extract a new class.
- **God classes**: Dozens of methods, hundreds of lines. Flag and suggest decomposition.
- **OCP**: If adding behavior requires modifying existing code instead of extending, flag the design.
- **DIP**: Concrete dependencies where an interface would enable testing and flexibility.

#### B10. Duplication & General Smells

- **Copy-pasted code**: Similar blocks that could be unified into a shared function.
- **Repeated if/else chains**: Should be polymorphism or strategy pattern.
- **Multiple languages in one file**: SQL in TypeScript strings, HTML in JavaScript, etc.
- **Overridden safeties**: `@ts-ignore`, `eslint-disable`, `// noinspection` without justification.
- **Magic numbers**: Use named constants.
- **Prefer structure over convention**: If a design decision can be enforced by the type system, don't rely on comments.

#### B11. TypeScript-Specific

`any` abuse, missing types, incorrect assertions, unnecessary type casts.

#### B12. UI Only (when IS_UI_TICKET = true)

Accessibility (ARIA, keyboard nav, contrast), responsive design, state management.

### PASS C: Architecture Review [CONDITIONAL — when PR touches data layer, APIs, or distributed system concerns]

Apply when the PR modifies database queries, replication logic, caching, event/message handling, API contracts, or transaction boundaries.

#### C1. Downstream Impact Verification [MANDATORY — run before architecture checks]

For every modified function, method, interface, or type in the diff:

1. **Identify modified signatures**: Extract every function/method whose signature changed (parameters added/removed/reordered, return type changed) and every interface/type whose shape changed (fields added, removed, or made optional).
2. **Search for callers**: For each modified symbol, search the local codebase for all call sites:
   - `grep -rn "<functionName>" src/ test/` to find direct callers
   - For interface/type changes, search for all files that import or reference the type
3. **Search for consumers across service boundaries**: If the changed code is in a shared module (e.g., `common/`), search ALL services in the monorepo that depend on it — not just the service being modified.
4. **Check event/message contracts**: If the PR modifies event payloads (SNS/SQS publish shapes), search for all consumers/handlers of that event across the repo.
5. **Flag breaking changes**: If any caller or consumer would break or behave differently due to the change, flag it as P1 Critical. Include the modified symbol, what changed, each affected caller/consumer file and line, and whether the caller has been updated in this PR.
6. **Flag interface contract drift**: If a shared interface field was made optional or removed, verify that all consumers handle the `undefined` case.

#### C1.5. Cross-PR Frontend Impact Check [CONDITIONAL — when backend changes may affect clients]

When the diff contains changes that could impact frontend consumers — GraphQL query/mutation renames, field additions/removals/renames, input type changes, guard/permission changes, enum value changes, response shape changes, or DTO/interface renames — perform a cross-PR check:

1. **Detect impactful changes**: Scan the diff for:
   - Renamed or removed GraphQL fields, queries, mutations, or subscriptions
   - Changed `@InputType()` or `@ObjectType()` field names or types
   - Modified `@Guard()` decorators or permission requirements
   - Renamed exported interfaces, types, or enums consumed by clients
   - Changed API response shapes or error codes
2. **If Jira MCP is available AND a Jira ticket is linked to this PR (from Stage 4)**:
   - Fetch the Jira story via `mcp_jira_get_issue` and read its development/links panel (or remote links) for other pull requests attached to the same key
   - If other PRs are linked to the same story (especially in frontend repos), briefly review their changed files list via `mcp_github_pull_request_read` (`method=get_files`) to verify the frontend PR accounts for the backend rename/change
   - If a corresponding frontend PR exists and covers the change → note as "Frontend PR #X covers this change" in the review
   - If NO corresponding frontend PR exists → flag as **P1 Critical BREAKING-CHANGE**: "Backend [describe change] has no matching frontend PR linked to [JIRA-KEY]. Client code may break."
3. **If Jira MCP or Jira ticket is NOT available**: skip this check and proceed — do not block the review.

Present any cross-PR findings in the Architecture section of the draft review.

#### C2. Transaction & Isolation

Does the code assume serializable isolation when the DB uses read committed or snapshot isolation? Look for read-modify-write cycles without `SELECT FOR UPDATE` or atomic operations (write skew / lost update risk). Flag dual writes to multiple datastores without atomic commit or CDC.

#### C3. Replication & Consistency

Does the code read from a replica after writing to the leader? Flag missing read-after-write consistency patterns. Check for timestamp-based ordering (LWW) that breaks under clock skew.

#### C4. Partitioning & Hot Spots

Does a new key design risk hot spots (e.g., monotonic timestamps as partition keys)? Flag sequential keys that funnel writes to a single partition.

#### C5. Encoding & Schema Evolution

Does a schema change maintain backward/forward compatibility? Flag removed required fields, reused field tag numbers (Protobuf/Thrift), or missing default values for new fields.

#### C6. Stream/Event Contracts

Does a change to an event payload break downstream consumers? Flag missing versioning on event schemas. Check for idempotency on event handlers (safe to retry?).

#### C7. Fault Tolerance

Missing retry/backoff on network calls, missing circuit breakers, unbounded queues, missing fencing tokens on distributed locks, lease expiry assumptions that ignore GC pauses.

### PASS D: Test Coverage [MANDATORY]

Test code deserves the same rigor as production code. Dirty tests are worse than no tests — they become a liability, get abandoned, and then production code rots because nobody dares refactor without coverage.

#### D1. Test Presence Check

For every changed production file, verify corresponding test files exist and were updated:

- **Unit tests**: Check for `*.spec.ts`, `*.test.ts`, `*.spec.js`, `*.test.js` files matching the changed source files. If new logic was added without a corresponding unit test file, flag as P2 Important.
- **Integration tests**: If the PR modifies API endpoints, database queries, or service-to-service communication, check for integration test coverage. Look for files in `test/integration/`, `e2e/`, or `*.integration.spec.ts` patterns.
- **Mutation tests**: Check if the project uses mutation testing (Stryker, PIT, mutmut). If configured, verify mutation score hasn't degraded. If not configured but the project has significant business logic, suggest adding mutation testing as a follow-up.
- **Regression tests**: If the PR fixes a bug, a test that would have caught the bug MUST exist. Flag its absence as P2 Important.

#### D2. Test Quality — TDD Principles

Evaluate test quality against these TDD principles:

**Single Concept per Test** Each test function should test exactly one behavior. Tests asserting multiple unrelated things must be split. A test that checks creation, validation, AND error handling is three tests pretending to be one. Flag as P3 Moderate.

**Evident Data** The relationship between inputs and expected outputs should be obvious in the test body. Include the calculation in the assertion when it clarifies intent:

```
// Good — shows the exchange rate math
expect(convert(CHF(5.00), 'USD', rate(0.5))).toEqual(USD(2.50));
// Bad — magic number, reader must reverse-engineer why 2.50
expect(result).toEqual(USD(2.50));
```

Flag tests with unexplained magic numbers or opaque expected values as P3 Moderate.

**Test Data Minimalism** Use the simplest data that makes the test readable. If there is no conceptual difference between 1 and 2, use 1. A list of 3 items is sufficient if it leads to the same design decisions as a list of 10. Flag tests with unnecessarily complex setup data as P4 Minor.

**Domain-Specific Test Language** Tests should read like specifications. Build helper functions that express intent rather than exposing raw construction:

```
// Good — reads like a spec
givenAnEmployee().withSalary(50000).build();
// Bad — implementation noise
new Employee('John', 'Doe', 50000, 'USD', 'ACTIVE', dept.id, null, null);
```

Flag tests with verbose, repetitive setup that could be extracted into builders or fixtures as P4 Minor.

**Test Naming** Names should describe the scenario and expected outcome, not `test1`, `test2`. Prefer patterns like:

- `should [expected behavior] when [condition]`
- `[method]_[scenario]_[expectedResult]`

Flag generic or numbered test names as P4 Minor.

#### D3. Test Smells — F.I.R.S.T. + TDD Red Flags

**F.I.R.S.T. Violations:**

- **Fast**: Slow tests don't get run. If they don't get run, they won't be valuable. If they aren't valuable, they won't continue to be written. Flag tests with real network calls, large data setup, or unnecessary I/O when mocks would suffice. (P2 Important for tests > 1s)
- **Independent**: Tests dependent on execution order or shared mutable state. One test breaking should not cascade failures across the suite. (P2 Important)
- **Repeatable**: Tests that only pass in specific environments (hardcoded paths, ports, credentials, timestamps). (P2 Important)
- **Self-Validating**: Tests requiring manual log inspection. Overly broad assertions (`toBeTruthy()` when a specific value should be checked). A test must produce a boolean pass/fail — no human interpretation. (P3 Moderate)
- **Timely**: Tests written long after the code — flag if test coverage was clearly an afterthought (testing only the happy path, missing edge cases the code handles). (P3 Moderate)

**TDD Red Flags (from Beck):**

- **Tests that test implementation, not behavior**: Asserting on internal state (`expect(obj.internalFlag).toBe(true)`) instead of observable behavior. Tests coupled to implementation break on every refactor. (P3 Moderate)
- **Missing error path tests**: Use the Crash Test Dummy pattern — error handling code that isn't tested doesn't work. For every catch block or error branch in the PR, verify a test exercises it by injecting a failure (mock that throws, invalid input). (P2 Important)
- **Fixture bloat**: Overly complex `beforeEach`/`setUp` that creates dozens of objects. Per Beck: if the fixture is complex, the design may need simplification. Flag and suggest extracting a focused fixture or splitting the test class. (P3 Moderate)
- **Log String pattern missing**: When the PR tests that methods are called in a specific order (e.g., setUp → process → tearDown), verify the test uses a deterministic approach (log string, ordered mock verification) rather than timing-dependent assertions. (P3 Moderate)
- **Missing triangulation for complex logic**: When the PR adds non-trivial calculation logic with only one test case, flag that a single example may not sufficiently constrain the implementation. Suggest at least two examples that force generalization. (P3 Moderate)

#### D4. Coverage Gaps & Boundary Conditions

- Use coverage tools when available. Flag untested branches.
- **Test boundary conditions**: Take special care with boundaries — the middle of an algorithm is usually correct, but edges are where bugs hide. For numeric inputs: 0, 1, -1, MAX, MIN. For collections: empty, single element, many. For strings: empty, whitespace, max length. (P2 Important for missing boundary tests on new logic)
- **Exhaustively test near bugs**: Bugs congregate. When a test reveals a bug in a function, verify the PR includes thorough testing of that function — the bug was probably not alone. (P2 Important)
- **Patterns of failure are revealing**: If multiple tests fail in a pattern (all inputs > N, all strings with special chars), flag the pattern — it points to a systematic issue.
- **Hardcoded sleeps/timeouts**: Use deterministic waits or event-driven assertions. (P3 Moderate)
- **Don't skip trivial tests**: They serve as documentation and catch regressions. A test that seems too simple to write is too simple to skip.

#### D5. Mock & Test Double Hygiene (Beck + Clean Code)

- **Mock Object overuse**: Mocking everything creates tests that pass but verify nothing real. Flag tests where the mock setup is longer than the assertion — the test may be testing the mocks, not the code. (P3 Moderate)
- **Self Shunt opportunity**: When a test creates a separate mock class just to capture a callback or notification, suggest using the test class itself as the listener (Self Shunt pattern) for cleaner, more readable tests. (P4 Minor)
- **Crash Test Dummy for error paths**: When error handling is tested by creating elaborate failure scenarios, suggest a simpler Crash Test Dummy — a subclass that overrides one method to throw. (P4 Minor)
- **Stale mocks**: Mock return values that no longer match the real implementation's contract. If the PR changes a method signature or return type, verify all mocks of that method are updated. (P2 Important)

#### D6. Test-to-Code Traceability

For each significant code change in the PR, verify:

1. At least one test exercises the new/changed behavior.
2. Edge cases identified in Pass B (boundary conditions, null handling, error paths) have corresponding test cases.
3. If the PR fixes a bug, a regression test exists that would have caught the bug.
4. If the PR adds a new code path (if/else, switch case, catch block), a test exercises that path.
5. If the PR modifies existing behavior, existing tests were updated to reflect the new behavior — not deleted.

### PASS E: AC Coverage Verification [CONDITIONAL — only when AC source is available from Stage 4]

If Stage 4 yielded no AC source (Jira fetch failed AND user replied "skip"), skip this pass entirely. Do not invent ACs from the PR title or description.

When ACs are available — either from Jira or pasted by the user — this pass produces an **AC coverage map** that is mandatory output of the review. The map answers a single question for every AC: *did this PR implement it?*

#### E1. Extract Acceptance Criteria

From the AC source resolved in Stage 4 (Jira issue OR user-pasted text):

1. Parse the **Acceptance Criteria** section (or equivalent — "AC", "Definition of Done", numbered list under Description).
2. Extract each AC as a discrete, testable statement. If ACs are written as prose paragraphs, split into atomic checks.
3. Number them: `AC1`, `AC2`, `AC3`, ... preserve the order from the ticket.
4. If the ticket has linked sub-tasks or child stories with their own ACs and they are part of the same PR, include them too.
5. If ACs are missing, vague, or non-testable, flag as **P2 Important AC-GAP**: "Story has no clear acceptance criteria — coverage cannot be verified" and stop this pass.

#### E2. Map ACs to Code Changes

For each extracted AC:

1. **Identify the expected code surface**: which files, functions, or modules would need to change to satisfy this AC?
2. **Search the diff**: scan the PR's changed files for evidence of implementation. Look for:
   - New/modified functions whose names or behavior match the AC
   - New/modified validations, guards, or business rules
   - New/modified API contracts (GraphQL fields, REST endpoints, event payloads)
   - New/modified database queries or schema changes
   - New/modified UI components (if `IS_UI_TICKET = true`)
3. **Search the test diff**: verify a test exercises the AC. ACs without corresponding tests are weak coverage even if the code is present.
4. **Trace cross-system impact**: if the AC implies behavior in another service (frontend/backend boundary, event consumer), check whether this PR or a linked PR covers it.

#### E3. Classify Each AC

For each AC, assign one classification:

| Status | Meaning |
|--------|---------|
| ✅ Covered | Code change directly implements the AC AND a test exercises it. |
| ⚠️ Partial | Code change exists but: (a) test is missing, (b) only one of multiple sub-conditions is covered, or (c) edge case in the AC is not handled. |
| ❌ Missing | No code change in this PR implements the AC. |
| ↗️ Out of scope | AC is explicitly handled in a linked PR (cite PR number) or a separate ticket (cite Jira key). |
| ❓ Unverifiable | AC is too vague, or implementation is in code paths not visible in this diff (config, infra, external system). State why. |

#### E4. Flag Coverage Gaps

For each AC classified as **Partial** or **Missing**:

- Create a P1 Critical AC-GAP finding if the AC describes a security, authorization, data integrity, or compliance behavior.
- Create a P2 Important AC-GAP finding for all other missing/partial ACs.
- The finding must cite the AC verbatim from the Jira ticket and explain what is missing.

For each AC classified as **Out of scope**:

- Verify the linked PR exists and is open or merged. If the linked PR is closed/declined or doesn't exist, downgrade to **Missing**.

For **scope creep** — code changes in the PR that don't map to any AC:

- Flag as P3 Moderate AC-GAP: "Change [describe] is not covered by any AC in [JIRA-KEY]. Confirm intent or split into separate PR."
- Bug fixes, test additions, refactors, and trivial cleanups are exempt — do not flag them.

#### E5. AC Coverage Map Output

This pass produces a structured table that becomes part of Stage 8's draft. Format:

```
## AC Coverage — [JIRA-KEY]

| # | AC | Status | Evidence |
|---|----|--------|----------|
| 1 | <verbatim AC text> | ✅ Covered | `src/service/foo.ts:42` + test `foo.spec.ts:15` |
| 2 | <verbatim AC text> | ⚠️ Partial | Code in `src/service/bar.ts:88`, no test for null case |
| 3 | <verbatim AC text> | ❌ Missing | No matching change in diff |
| 4 | <verbatim AC text> | ↗️ Out of scope | Covered by frontend PR #1234 |
| 5 | <verbatim AC text> | ❓ Unverifiable | Behavior depends on AppConfig — not in diff |

**Summary**: X/Y ACs covered, Z partial, W missing.
```

If summary shows any ❌ Missing or ⚠️ Partial in security/auth/data-integrity ACs, **the PR should not be approved** until addressed.

---

## STAGE 7: Check Existing PR Comments [AUTOMATIC]

Fetch with `mcp_github_pull_request_read` (`method=get_review_comments` for existing inline review threads; `method=get_comments` for PR-level conversation comments). Build a map by file+line. For each finding from Stage 6 (all passes), check for similar existing feedback (same file/line ±3, same topic). AUTOMATICALLY EXCLUDE similar comments from the draft. Prepare exclusion report.

---

## STAGE 8: Present Draft Inline Comments [WAIT FOR USER]

Show excluded comments first (with reason), then the draft of non-duplicate comments grouped by pass:

```
## Security Scan (Pass A)
[findings...]

## Code Quality (Pass B)
[findings...]

## Architecture (Pass C)
[findings...]

## Test Coverage (Pass D)
[findings...]

## AC Coverage (Pass E) — only if Jira story linked
[AC coverage map table from E5...]
[AC-GAP findings...]
```

Each draft comment includes:

- File path (repo-relative, exactly as in the diff — no repo directory prefix)
- Line number (`line` from the head/new version of the file in the diff — NOT the `@@` diff hunk header)
- Side (`RIGHT` for added/context lines in the new version, `LEFT` for lines from the base version)
- Comment text following the **Comment Format** below

### Comment Format

Every inline comment MUST follow this structure. Keep it short — the developer should understand the issue and know what to do in under 10 seconds.

```
@pr-agent

**Issue**: One sentence describing what's wrong.

**Fix**: Concrete action or code snippet to resolve it.
```

**Rules:**

- **Max 5 lines** for the entire comment (excluding code blocks). If it takes more, the finding is too broad — split it.
- **Lead with `@pr-agent`** — developer recognizes it as automated review at a glance.
- **"Issue" line = what's wrong**, not a lecture. No preamble, no "I noticed that...", no "Please consider...".
- **"Fix" line = what to do**. Provide a code snippet, a method name to use, or a specific action. Never leave the developer guessing.
- **Code snippets over prose** — a 2-line before/after is worth more than a paragraph of explanation.
- **No filler** — cut "It would be great if...", "You might want to...", "I would suggest...". Just state the issue and the fix.
- **No repeating the code** — the comment is anchored to the line. Don't quote it back.

**Examples:**

Good:

```
@pr-agent

**Issue**: Hardcoded API key will be committed to version control.

**Fix**: Move to environment variable and add to `.gitignore`:
`const apiKey = process.env.PAYMENT_API_KEY;`
```

Good:

```
@pr-agent

**Issue**: Promise rejection unhandled — will crash the process.

**Fix**: Wrap in try/catch:
`try { await service.process(input); } catch (e) { logger.error('Process failed', e); throw new AppError('PROCESS_FAILED'); }`
```

Good:

```
@pr-agent

**Issue**: New `calculateDiscount()` logic has no unit test.

**Fix**: Add test covering the boundary: `expect(calculateDiscount(0)).toBe(0);` and the standard case.
```

Good:

```
@pr-agent

**Issue**: `d` is not intention-revealing.

**Fix**: Rename to `elapsedTimeInDays`.
```

Bad (too wordy, no fix):

```
@pr-agent I noticed that this function is quite long and does several things.
It might be worth considering breaking it up into smaller functions for better
readability and maintainability. Please consider extracting the validation
logic into its own method.
```

**Options:**

```
1. Edit
2. Approve and publish (summary + inline comments)
3. Approve (LGTM) — summary only
4. Publish inline comments only
5. Include duplicates
6. Reply to existing PR comments
7. Cancel
```

WAIT for user choice.

- Option 3 (LGTM): Post only approval summary comment, skip to Stage 10.
- Option 4: Post only inline comments, skip to Stage 10.
- Option 5: Add excluded comments back, re-present, WAIT again.
- Option 6: Present existing PR comments and let user pick which to reply to. Use `mcp_github_add_reply_to_pull_request_comment` (`commentId` = numeric review-comment ID from the `#discussion_r...` anchor, not the GraphQL `PRRT_...` thread node ID). WAIT for user to compose reply text and confirm before posting.
- Option 7: Discard, end.

---

## STAGE 9: Handle User Corrections [IF NEEDED]

Update draft per user feedback, re-present, WAIT for re-approval. Repeat until satisfied.

---

## STAGE 10: Publish Review Comments [WAIT FOR USER]

Confirm:

```
Ready to publish review to PR #<N>?
This will submit one review with: [X inline comments] [event: APPROVE / COMMENT / REQUEST_CHANGES]
Publish? (yes/no)
```

WAIT for "yes". On GitHub, inline comments are posted as a single **review** (create a pending review, attach all inline comments, then submit once) — not one API call per comment. Then:

1. **Start a pending review**: `mcp_github_pull_request_review_write` with `method=create` and NO `event` (owner, repo, pullNumber, optional `commitID` = PR head SHA from Stage 4). This opens a pending review to attach comments to.
2. **Attach each inline comment**: `mcp_github_add_comment_to_pending_review` (owner, repo, pullNumber, `path` = exact diff path, `body` = comment text, `subjectType=LINE`, `line` = head-file line, `side` = RIGHT/LEFT; for multi-line use `startLine`/`startSide`).
3. **Submit the review**: `mcp_github_pull_request_review_write` with `method=submit_pending` and `event`:
   - `event=APPROVE` when approving (option 2 or 3) — the review `body` carries the approval summary.
   - `event=COMMENT` when publishing inline comments without approving (option 4 or the not-approving path of option 2).
   - `event=REQUEST_CHANGES` when the AC coverage map shows Missing/Partial security/auth/data-integrity ACs.
4. **Post replies to existing comments** (option 6) via `mcp_github_add_reply_to_pull_request_comment` (owner, repo, `commentId`, `body`).
5. **PR-level summary comment** (not tied to a line) via `mcp_github_add_issue_comment` (owner, repo, `issue_number` = PR number, `body`) — use only when a standalone summary is wanted outside the review body.

> ⚠️ `path` MUST match the diff exactly (repo-relative, no leading prefix). A mismatch causes the comment to be rejected or posted as a file-level comment instead of anchoring to the line.

> ⚠️ `line`/`side` MUST fall inside the PR diff. Use the head-file line for `side=RIGHT` (added/context) or the base-file line for `side=LEFT` (removed). Numbers taken from the `@@` hunk header, or lines outside the diff, will fail or anchor to the wrong place.

> ⚠️ Never leave a pending review dangling. If you start a review (step 1) but the user aborts, delete it with `method=delete_pending` — an orphaned pending review blocks starting a new one.

Report progress per comment. If a comment fails (line not in diff), report and continue; fall back to including it in the review summary body.

---

## STAGE 11: Offer to Work on Fixes [WAIT FOR USER]

List identified items and ask:

```
Would you like help implementing fixes? (yes/no)
```

"no" → Stage 16. "yes" → Stage 12.

---

## STAGE 12: List Suggested Changes [WAIT FOR USER]

Present fix table (file, line, description). Ask which to implement (numbers or "all"). WAIT.

---

## STAGE 13: Branch Strategy [WAIT FOR USER — REQUIRES PERMISSION]

Ask permission before any git operations:

```
To implement fixes, I need to switch to <PR-branch> and create fix/<JIRA-KEY>-review-fixes.
This will change your local working directory. Proceed? (yes/no)
```

WAIT. If "yes": checkout PR branch, then create fix branch via `mcp_github_create_branch` (`branch` = `fix/<JIRA-KEY>-review-fixes`, `from_branch` = PR head/source branch). Confirm and WAIT again.

---

## STAGE 14: Implement Fixes [WAIT FOR USER — REQUIRES EXPLICIT PERMISSION]

List files to be modified. Ask "Do you want me to make these changes? (yes/no)". WAIT for "yes".

Implement each fix, show the change, run related unit tests using the project's toolchain (see **Test Execution by Ecosystem** below). Report results. WAIT before pushing.

---

## STAGE 15: Push Changes [WAIT FOR USER]

Ask:

```
Would you like to push these changes? (yes/no)
```

WAIT. If "no" → Stage 16. If "yes":

Push via `mcp_github_push_files` (owner, repo, `branch` = fix branch, `files` = array of `{path, content}`, `message` = commit message) — all changed files go in a single commit. Then ask about PR creation:

```
1. Yes - Create PR (fix branch → original PR branch)
2. No - Keep in fix branch only
```

WAIT. If "yes": `mcp_github_create_pull_request` (`head` = fix branch, `base` = PR head/source branch, `title` = `[JIRA-KEY] Code review fixes`).

Proceed to Stage 16.

---

## STAGE 16: Wrap-Up [WAIT FOR USER]

Ask:

```
Is there anything else you need help with? (yes/no)
```

WAIT. If "no" → task is complete, end. If "yes" → ask what they need and route accordingly.

---

## Test Execution by Ecosystem

Auto-detect the project ecosystem from config files in the repo root and use the appropriate commands. Always redirect output to a workspace file since direct stdout isn't reliably captured in this environment.

### Node.js / TypeScript (package.json)

```
npm run lint
npm run test -- --coverage
# Or for monorepo service-specific:
npm run <service>-test
```

### Python (pyproject.toml / setup.py)

```
# Preferred: uv run with --no-sync to bypass stale lock files
uv run --no-sync pytest tests/unit/ > test_output.txt 2>&1

# If make test-dev fails with "Lock file is out of sync":
# Option A: uv run --no-sync (bypass lock check)
# Option B: make lock first to resync, then make test-dev
```

Key issues in this environment:

- Direct stdout is swallowed — always redirect `> test_output.txt 2>&1`, then read the file.
- `make test-dev` runs `.check-lock` first. If `uv.lock` is stale (e.g., dependency version bumped without regenerating lock), it blocks. Use `uv run --no-sync` to bypass.

### Java / Kotlin (pom.xml / build.gradle)

```
mvn test > test_output.txt 2>&1
# or
./gradlew test > test_output.txt 2>&1
```

### Fallback

If none of the above config files exist, ask the user for the test command.

---

## CRITICAL RULES

The stages above are authoritative. These five rules are the non-negotiables; everything else is enforced by the stage flow.

1. **Never modify remote state without explicit consent.** Submitting reviews, posting comments, creating branches, pushing, creating PRs — all require the user to say "yes" or equivalent. Silence is not consent. Applies to: `pull_request_review_write` (create/submit), `add_comment_to_pending_review`, `add_pull_request_review_comment`, `add_reply_to_pull_request_comment`, `add_issue_comment`, `create_branch`, `push_files`, `create_or_update_file`, `create_pull_request`, and any `git commit/push/checkout/switch/merge/rebase`.
2. **Read-only by default.** `git status/diff/log`, file reads, GitHub/Jira fetches, and running linters/tests proceed without permission. Anything that writes to disk or remote requires permission.
3. **Never auto-fallback.** If the user declines a permission request (e.g., refuses full-codebase mode in Stage 3, refuses a branch switch in Stage 13), ask what they want to do next. Do not silently switch to a different mode.
4. **Diff-based line anchoring for inline comments.** Every inline comment uses `path` + `line` + `side` where `line` is the head/new-file line (`side=RIGHT`) or base-file line (`side=LEFT`) as it appears in the PR diff. Never use `@@` hunk-header numbers, and never comment on a line outside the diff — GitHub rejects it or drops it to a file-level comment.
5. **Five-pass review, AC pass conditional.** Always run A (Security), B (Code Quality), C (Architecture), D (Tests). Run E (AC Coverage) when ACs are available from Stage 4 (Jira fetch or user-pasted). Skip E only if Jira is unavailable AND the user declined to provide ACs. Never invent ACs from PR title/description.
6. **Comment format is fixed.** Every inline comment uses `@pr-agent` / `Issue` / `Fix`, max 5 lines, code over prose. See Stage 8.
7. **Prioritize business logic over style.** A logic bug, missing error handling, or untested code path always outranks naming or formatting. Don't bury P1/P2 findings under a pile of P4 nits.
8. **One review, correct event.** Publish inline comments as a single review, never one comment per call. Choose the event: `APPROVE` for option 2/3 (summary in the review body), `COMMENT` for option 4 (inline only, no approval), `REQUEST_CHANGES` when security/auth/data-integrity ACs are Missing/Partial. Option 3 (LGTM) submits an `APPROVE` review with a summary body and no inline comments.
9. **Minimize output.** Show only what the user needs to decide or act. No restating context they already have, no narrating what you're about to do.

Default priorities for ambiguous findings:

- Committed secrets, credentials, private keys → P1, no exceptions.
- Missing/partial security/auth/data-integrity ACs → P1.
- Style/formatting → P4 unless it materially harms readability.
- Trace upstream contracts before flagging null-safety issues; do not flag if the upstream method throws on not-found.

---

## QUICK COMMANDS

| Command | Action |
|---------|--------|
| "Check PRs" | Stage 0 — detect project, then list open PRs |
| "List PRs" | Stage 2 — show open PRs |
| "Review PR #X" | Start review for specific PR |
| "My PRs" | Filter PRs by author via `search_pull_requests` |
| "Skip to fixes" | Jump to fix implementation |
| "Analyze staged" | Stage 1 Option 2 — analyze staged changes |
| "include duplicates" | Add excluded similar comments to draft |
| "Reply to comments" | Show existing PR comments and reply to selected ones |
