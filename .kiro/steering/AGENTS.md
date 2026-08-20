# CareConnect — AI Assistant Project Rules (AGENTS.md)

> Steering / rules file for AI coding assistants working on the
> **CareConnect** capstone (SWEN 670, UMGC).
>
> ⚠️ **Source & validation:** The rules below are derived from the **prior cohort's
> handoff documents** (Project Plan, TDD, SRS, Programmer's Guide, Deployment Guide,
> Handoff). Versions, ports, passwords, and coverage numbers MAY have changed.
> **Always validate against the actual received repo** (`README`, `analysis_options.yaml`,
> Checkstyle config, `quality/Local_Scans/`, CI workflow files, Flyway migrations)
> before treating any specific value as authoritative.

---

## 1. Project Context

- **CareConnect** is a cross-platform digital healthcare app for users with cognitive
  and sensory impairments (memory loss, hearing/vision). It connects a "care circle":
  **patient, caregiver, family member, provider**.
- This is an **inherited codebase** developed over multiple semesters. We ADD features
  to a working app — we do NOT build from scratch.
- **Our team (new Team B, Fall 2026) owns: athenahealth EHR integration (via FHIR).**
  This is a NEW capability not present in the prior codebase.
- **Accessibility and HIPAA are first-class concerns**, not afterthoughts (see §8).

---

## 2. Tech Stack (do not introduce alternatives without team/architect approval)

| Layer | Technology |
|---|---|
| Frontend | **Flutter / Dart** — single codebase for Web, Android, iOS |
| Backend | **Spring Boot 3.4.x (3.4.5) on Java 17** |
| Database | **PostgreSQL 15** (with `pgvector` extension) |
| Auth | **Spring Security + JWT** (stateless) |
| Migrations | **Flyway** |
| Local infra | **Docker / Docker Desktop** |
| Cloud | **AWS** — ECS Fargate, RDS (PostgreSQL), ECR, CloudFormation |
| AI/LLM | **AWS Bedrock** (Claude models) |
| Backend tests | **JUnit 5**, `@SpringBootTest` |
| Frontend tests | **Flutter widget tests**, `integration_test` (E2E on Android emulator) |
| Coverage | **JaCoCo + SonarCloud** |

---

## 3. Architecture Patterns (new code MUST follow these)

### Backend — Layered architecture
- **Controller → Service → Repository.** Keep responsibilities separated.
- New athenahealth work should mirror this: `AthenaController` → `AthenaService` → `AthenaRepository`.
- **Follow existing external-integration patterns.** The codebase already integrates
  external healthcare systems — study and imitate these before inventing new patterns:
  - EVV: `EvvController.java`, `EvvService.java`
  - HHAeXchange batch submission: `HhaExchangeBatchSubmissionService.java`
  - Invoicing / OCR: `InvoiceController.java`, `TextractService`
  - External client classes and mock/sandbox clients (e.g., `DcSandataAltEvvClient`)

### Frontend — Feature-First + Provider
- Organize by **feature**, not by layer.
- Use the **Provider** state-management pattern (feature-scoped).

---

## 4. Coding Conventions

### Backend (Java / Spring Boot) — enforced, not optional
- **Google Java Style**, enforced by **Checkstyle at build time — violations BLOCK compilation.**
- **PMD** and **SpotBugs** run additional static analysis at the verification phase.
- Naming:
  - Classes: `PascalCase`
  - Methods & variables: `camelCase`
  - Constants: `UPPER_SNAKE_CASE`
- Spring class suffixes: `Controller`, `Service`, `Repository`, `Dto`.
- Method names use descriptive **verb prefixes**: `get`, `find`, `create`, `update`, `delete`.
- **Lombok**: use on entities (boilerplate reduction) and on services (constructor-based DI).

### Frontend (Dart / Flutter)
- **`flutter_lints`** rules in `analysis_options.yaml`; **Flutter Analyze** runs in local + CI gates.
- Naming:
  - Source files: `snake_case`
  - Classes: `PascalCase`
  - Methods & variables: `camelCase`
- Widget classes suffixed with `Screen`, `Page`, or `Widget` to signal UI-hierarchy role.
- Model classes implement `fromJson` / `toJson` factory constructors.
- Import order: `dart:` core first → third-party packages → internal project imports.

---

## 5. Quality Gates (code must pass ALL of these to merge)

- Every push / PR runs a **13-tool quality gate** in CI. "It runs on my machine" is not enough.
- A **local pre-commit quality gate** exists at `quality/Local_Scans/` — **run it BEFORE committing**
  to avoid wasting CI cycles.
- Gate includes (at minimum): Checkstyle, PMD, SpotBugs, Flutter Analyze, test execution,
  coverage check, and **`Flyway validate`**.
- **All tests must pass with no coverage regression before merge.**

---

## 6. Testing Requirements

- **Every team is responsible for three test layers:**
  1. **Unit tests** (JUnit 5 backend, Flutter widget tests frontend)
  2. **E2E tests** (`integration_test`, runs on Android emulator)
  3. **CAT** (Client Acceptance Testing) — validate against acceptance criteria
- **Coverage target: 95% on NEW code we add.** (Existing inherited code is already
  largely covered; confirm current CI threshold in the repo.)
- **Definition of Done for a feature** = feature code **+** unit tests to 95% **+** E2E scenario
  **+** acceptance criteria met.
- Write tests for all new/modified components **before merge**.
- Map tests to acceptance criteria where possible (traceability).
- **External-API code (athenahealth) must be unit-testable with mocks** — do not require a live
  sandbox connection to run unit tests. Mock the athenahealth/FHIR client.

---

## 7. Database Access & Migrations

### Local development
- DB runs as a **Docker container**, not a native install.
- Start it: from `backend/core/pg_docker`, run **`docker compose up -d`**
  (provisions PostgreSQL 15 + `pgvector`, plus a pgAdmin container).
- Connect for inspection: `localhost:5432` (prior guide also references container
  `cc_pg_5433` on port **5433**), default database **`careconnect`**,
  password commonly **`careconnect123`** — **verify in the repo's Docker Compose env.**
- Backend connects via **JDBC** using environment variables (e.g., `JDBC_URI`).

### Schema changes
- **All schema changes go through Flyway migrations.** Never hand-edit shared schema.
- PRs must pass **`Flyway validate`** in CI.
- Because multiple teams share one schema, **coordinate migrations** to avoid collisions.
- For athenahealth: prefer mapping onto existing `patient` / `caregiver` entities;
  add new tables via Flyway migration only when needed.

### Production
- Deployed DB is **AWS RDS (PostgreSQL)** — managed by the deployment/AWS role, not app devs.

---

## 8. HIPAA / PHI & Accessibility (non-negotiable for healthcare)

- Treat all patient/medical data as **PHI (Protected Health Information)**.
- Apply **data minimization** — collect/transmit/store only what's needed.
- Validate and sanitize on the **server side**, not just the client
  (prior gap: client-only guardrails were bypassable).
- Define retention/TTL for any new data store (prior gap: telemetry accumulated indefinitely).
- Accessibility standards: **WCAG 2.1 AA** and **Section 508**; automated **axe-core** scans;
  results documented in a **VPAT**. Keyboard navigation and screen-reader support matter
  because of the target user base.

---

## 9. Git Workflow

- Work on **feature branches** → open a **Pull Request** into the team branch
  (prior cohort used `team-b-develop`; confirm this semester's branch name).
- PR must pass the full CI quality gate + `Flyway validate` + coverage (no regression)
  before merge.
- Keep the call-facing / stateful services considerations in mind when touching shared infra.

---

## 10. Known Environment Traps (check these BEFORE debugging app code)

Misaligned ports/passwords/credentials cause **false failures that look like app bugs**.
Align these in the SAME terminal that starts the backend:

- **Backend port confusion (8080 vs 8081):** pass
  `--dart-define=BACKEND_URL=http://localhost:8081` (or the port you actually run).
  Never rely on the empty default (which points at 8080).
- **Postgres port/password drift:** prefer container `cc_pg_5433` on port **5433**,
  password aligned with backend config (commonly `careconnect123`).
- **AWS/Chime 403 "invalid security token":** re-run
  `aws sts get-caller-identity` in the same terminal that starts the backend, then restart.

---

## 11. When Generating Code — Checklist for the AI Assistant

Before proposing or writing code for this project, ensure it:

- [ ] Follows the **layered** (backend) or **feature-first + Provider** (frontend) pattern
- [ ] Matches an **existing external-integration pattern** if it talks to athenahealth/FHIR
- [ ] Uses correct **naming conventions** and Spring/Flutter **suffixes**
- [ ] Uses **Lombok** appropriately on backend entities/services
- [ ] Will pass **Checkstyle / PMD / SpotBugs / Flutter Analyze** (no style violations)
- [ ] Ships with **unit tests** targeting **95% coverage on new code**, using **mocks** for external APIs
- [ ] Adds **Flyway migrations** for any schema change (never hand-edits schema)
- [ ] Treats medical data as **PHI** and validates **server-side**
- [ ] Does NOT hardcode credentials, ports, or connection strings — uses **env vars**
- [ ] Does NOT introduce new frameworks/services without noting it needs **team/architect approval**

---

*Maintained by: Team B (Lead Developer). Update as the received codebase is confirmed and
as the client meeting clarifies requirements. Remove or correct any prior-cohort assumption
that the actual repo contradicts.*

## 12. Branch & PR rules

Team B follows a tiered branch model. All code reaches shared branches through pull
requests — never direct commits.

### Branch naming

```
feature/b-<description>  →  team-b-develop  →  develop  →  main
```

| Branch | Purpose |
|---|---|
| `feature/b-<description>` | Individual feature or fix work (e.g., `feature/b-fix-1-4`) |
| `hotfix/b-<description>` | Urgent fix that can't wait for the normal flow |
| `team-b-develop` | Team B integration branch — all our PRs target this |
| `develop` | Cross-team integration (weekly, handled by the Team Lead) |
| `main` | Release |

**Branch names are enforced by CI.** A branch that does not match `feature/b-*`
(or `hotfix/b-*`) fails the pipeline immediately at the source-retrieval stage.
Always use the `b-` prefix (Team B) exactly — e.g., `feature/b-athena-patient-fetch`.

When generating or committing code, put the work on a correctly named `feature/b-*`
branch; never commit directly to `team-b-develop`, `develop`, or `main`.

### Pull requests

- All code goes through a **pull request** — no direct commits to `team-b-develop` or above.
- Every PR needs **at least one reviewer's approval** before merge.
- PR description must state: what changed, why, how it was tested, and a link to the related issue.
- Keep PRs **small and single-purpose** (one feature or fix per PR).
- Run the local quality scan (`quality/Local_Scans/`) **before committing**, so the CI gate
  doesn't bounce the PR.
- **Note any significant AI-assisted code** in the PR description (per the AI policy). This covers code, not routine changes like config or docs edits. This applies to significant AI-assisted code, not to writing the PR itself nor commiting.
- Track defects in **GitHub Issues** with severity and priority.

### Commit messages

Follow the **Conventional Commits** style documented in
`docs/guides/PROGRAMMERS_GUIDE.md` ("Git Commit Standards"):

```
<type>: <description>
```

Types: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`.
For breaking changes, add a `BREAKING CHANGE:` footer.

Examples:

```
feat: add athenahealth patient fetch service
fix: resolve analytics back-arrow navigation to dashboard
docs: update API documentation for health endpoints
test: add unit tests for messaging service
chore: ignore .kiro/ directory
BREAKING CHANGE: change API response format for vital signs endpoint
```

This convention is **guidance, not a hard gate** — there is no commitlint config,
commit-msg hook, or CI check enforcing it. Follow it anyway to keep history clean and
consistent. (Note: unlike commit messages, **branch names *are* enforced by CI** — see above.)

### What runs when

- Push to `feature/b-*` → build and unit-test stages only.
- PR into `team-b-develop` → full CI quality gate (build, unit + E2E tests, coverage with no
  regression, and `Flyway validate` for any schema change).
- `team-b-develop` → `develop` is the weekly cross-team integration, handled by the Team Lead.

> Branch names, coverage thresholds, and the CI gate are inherited from the prior cohort's
> setup. Verify them against the actual repo (`.github/workflows/`, CI config) and update this
> section if the real values differ.
