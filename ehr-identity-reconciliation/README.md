# CareConnect EHR Identity Reconciliation — Shared Pattern

**For:** Teams Athenahealth (B), Epic (D), Oracle Health/Cerner (C), and whoever eventually builds
Medicare's sibling implementation. **From:** the EHR Canonical Schema team.

**What this is:** the one piece of the identity-reconciliation design that has to be implemented
correctly, shipped as a small dependency-free Java library plus an executable contract test suite —
not just a written spec you each implement from your own reading of it. See the implementation plan's
Phase 0 decision log (2026-09-26) for why: reconciliation ownership decentralized to each adapter team
instead of one shared service, which means this one correctness-critical piece now gets implemented up
to four times instead of once. This package exists so it's implemented *correctly* four times, not
*independently* four times.

## What you're integrating

Each of your adapters, after upserting its own row into `ehr_source_identity`, builds a
`SourceIdentitySnapshot` (patient id, source id, the FHIR resource's `meta.lastUpdated`, and a
map of field name → mapped value) and calls `IdentityReconciler.reconcile(snapshot)`. For every field
except `date_of_birth`, that's the entire integration surface — everything about *which value wins* is
decided inside the library, identically, regardless of which of you calls it. For `date_of_birth`
specifically, there is a second entry point too — see "The `date_of_birth` carve-out" below.

**Ids are `Long`, as of the PR #209 review (2026-09-30).** They were typed `Object` so adapters
would not be forced onto this codebase's key types. That never bought anything: every table these
ids land in declares `patient_id` and `source_id` as `bigint` with foreign keys to `patient.id`
and `ehr_source.id`, so no implementation could have used another type. `Object` only moved the
failure from compile time to runtime.

You do not decide winners yourselves, and you do not write to `patient` directly for any field this
library manages — that's the write-contract the original reconciliation design established, and it's
still the rule.

## The decision this library encodes (2026-09-26, partially reversed the same day)

Every field conflict resolves to whichever source has the most recent `source_updated_at` — **for
every field except `date_of_birth`.** There is no field-risk tiering beyond that one named exception
(the original design's low-risk/ambiguous/high-risk tiers are gone) and no `PENDING` state for those
fields — every decision is made and recorded in the same transaction it was detected in, as `ACCEPTED`
or `REJECTED` on `ehr_identity_conflict`, with `resolved_by = 'system'`. There is no user-facing
confirmation modal to build for these fields; a non-blocking "your info was updated" notice, if you
want one, is the only UI surface left.

**This does not apply outside identity/demographic fields.** Medication conflicts (FR-EHR-07) must
still be flagged for caregiver review, never auto-resolved — do not call this library for medications.
Visit/claims cross-source reconciliation (FR-XSRC-03/04) is a separate, still-undesigned problem — do
not call this library for visit or claims records either. This package is scoped to
`ehr_source_identity` vs. `patient` demographic fields only.

### The `date_of_birth` carve-out (2026-09-26 partial reversal)

DOB is "very sensitive and usually how patient is identified," and recency alone is not enough to
auto-resolve it without a human ever being asked. This is a single named exception for one field, **not
a return to the original three-tier design** — every other field keeps the recency-wins/no-`PENDING`
behavior above, unchanged.

- A `date_of_birth` disagreement that is not even newer than what's already confirmed on `patient` is
  discarded exactly like any other field's stale disagreement — `REJECTED`, `resolved_by = SYSTEM`, the
  patient is never interrupted for a candidate that couldn't have won anyway.
- A disagreement that *is* newer than the confirmed baseline does not auto-apply. It's written as
  `PENDING` (via `IdentityConflictAuditWriter.openPendingConflict`) and `patient.date_of_birth` is left
  untouched. `resolved_at`/`resolved_by` stay `NULL` while `PENDING` — the same invariant
  `ck_ehr_identity_conflict_resolution` enforces at the schema layer for this one field.
- The patient resolves it via `IdentityReconciler.finalizePendingDateOfBirth(patientId,
  acceptIncoming)` — the second integration surface for this field. `resolved_by` is always
  `PATIENT` once they choose. **There is no staff/admin resolution path** — confirmed in the Decisions
  log: patient self-service only.
- If a second, genuinely newer disagreement arrives while one is already `PENDING`, the newer one
  supersedes it: the stale candidate is closed out as `REJECTED`/`SYSTEM` (the system superseded it, the
  patient was never asked about it) and a fresh `PENDING` conflict opens for the new one. A candidate
  that isn't newer than the one already pending is discarded quietly instead. This is **Assumption A3**
  (below) — not settled by either Decisions-log entry, so `RecencyWinsIdentityReconciler` picks this as
  a defensible default rather than leaving the case unhandled. Confirm it before relying on it for
  anything patient-visible beyond "which value ends up in the confirmation prompt."
- What the patient's confirmation UI actually shows while a conflict is `PENDING` (old value, new
  value, both?) and whether there's a timeout if they never respond are still **not decided** — out of
  scope for this library, flagged in the implementation plan for whoever builds that UI.

## What you implement

Four interfaces, against your own persistence stack (JPA, plain JDBC, whatever you already use):

| Interface | What it's for |
|---|---|
| `IdentityFieldProvenanceStore` | Read/write `ehr_identity_field_provenance` (new table — DDL in `ehr_identity_field_provenance.sql`; **not** in either original draft, see below). `lockOrCreate` MUST take a row lock (`SELECT ... FOR UPDATE`) held for the rest of the transaction — this is the entire concurrency guarantee, and it covers `date_of_birth`'s pending-conflict reads/writes too (`RecencyWinsIdentityReconciler` takes this lock before branching on field name — see `finalizePendingDateOfBirth` as well, which takes it explicitly for the same reason). |
| `PatientFieldAccessor` | Read/write `patient`. This is the only path this library uses to touch `patient`. |
| `IdentityConflictAuditWriter` | Write `ehr_identity_conflict` rows. For every field except `date_of_birth`: always `ACCEPTED` or `REJECTED`, never `PENDING`, via `recordDecision`. For `date_of_birth` only: `openPendingConflict`/`currentPendingConflict`/`resolvePendingConflict` manage the one field that *does* go through `PENDING` — see its javadoc for the full contract, including the open-conflict uniqueness invariant implementations must enforce. |
| `TransactionRunner` | One method: run a block of work in a single DB transaction, using whatever transaction manager you already have. |

Then wire them into `RecencyWinsIdentityReconciler` (the one implementation of `IdentityReconciler` —
don't write your own) and extend `AbstractIdentityReconciliationContractTest`, pointing its abstract
hooks — including `auditWriter()`, needed for the `date_of_birth`-specific assertions — at your real
(test) database instead of the in-memory fakes. Every test in that class then runs against your
implementation, including the concurrency tests, which are the ones that actually matter.

## Why `ehr_identity_field_provenance` exists (it's new — not in either original draft)

The original reconciliation design deferred a "field provenance" concept entirely: *"Deferred, not
built now: a `field_provenance` JSONB summary column on `patient`... derivable by querying the latest
RESOLVED row per `field_name` in [`ehr_identity_conflict`]... don't pre-build it."* That deferral was
safe under the original assumption — one shared service, naturally able to serialize its own writes.
It stopped being safe the moment reconciliation ownership decentralized to four independent adapters
(2026-09-26): with no single process coordinating, and with `ehr_identity_conflict` only ever written
when values actually *disagree* (never on agreement, per the original design's own sequence diagram),
there's no reliable place to durably ask "what's the current freshest value for this field?" — which is
exactly what a lock-and-compare needs. `ehr_identity_field_provenance` is that place: one row per
`(patient_id, field_name)`, always present once first touched, always lockable. It is the smallest
schema addition that makes decentralized reconciliation actually safe.

## Assumptions baked into this library — confirm before relying on them

- **A1 — no-provenance baseline:** the first time a field is ever contested (no provenance row yet,
  but `patient` already has a non-empty value — e.g. from signup), the incoming snapshot is compared
  against `patient.updated_at`, not against some other notion of "how fresh is user-entered data."
  Applies to `date_of_birth` the same as any other field — A1 governs whether a DOB disagreement is
  even a candidate, not what happens to it once it is (that's A3).

  **Changed 2026-09-29 — re-read this if you read it before.** Two things moved, and the second
  reverses what this section used to promise.

  1. *The baseline is read once per snapshot,* before any field is processed, not per field.
     `patient.updated_at` is a property of the row, not the field, and applying any field advances
     it — so read per field, the first disagreeing field in a snapshot raised the bar above the
     snapshot's own `source_updated_at` and every later field without provenance lost to a bar the
     snapshot had just raised. Silently, and compounding on each sync.
  2. *`patient.updated_at` did not exist until 2026-09-29.* `Patient` carried no timestamps at all,
     so A1 had nothing to read. It now extends `Auditable`, and pre-existing rows were backfilled to
     the migration timestamp — a tech-lead decision, not a default.

  This README previously said "a first EHR sync will usually beat original signup data." **For any
  patient who existed before that migration, that is no longer true.** Their baseline is the
  migration time, so an EHR value wins only if its `source_updated_at` is *after* it. The policy is
  deliberate: an EHR record's history does not retroactively overwrite what is already on file, but
  any EHR update made since the migration does. Note this only concerns fields that are *non-empty*
  and *disagree* — an empty field is still filled directly, with no comparison at all, so a first
  sync populates everything blank regardless.
- **A2 — exact ties:** if two timestamps are bit-for-bit equal, the existing value wins (nothing
  flips). This is deterministic and prevents flip-flopping on repeated syncs at identical timestamps,
  but it is a made-up tie-break, not something either original draft specified.
- **A3 — a second `date_of_birth` disagreement while one is already `PENDING`:** see "The
  `date_of_birth` carve-out" above. Newer-than-the-pending-candidate supersedes it; not-newer is
  discarded quietly. Not settled by either Decisions-log entry — this library's own choice, not a
  product decision.

## Verified, not just written

This package's logic is run and checked by the normal build, not just reviewed on paper:

- All 16 contract scenarios (8 original + 8 added for the `date_of_birth` carve-out) pass consistently
  against the real, correctly-locking store.
- The original recency-wins concurrency scenario was run 200 times against a **deliberately broken**
  (non-locking) store as a control: it produced the wrong result in 17/200 trials on the most recent
  run (expect a nonzero count that varies run to run — see the implementation plan's note on this; the
  library's own initial verification saw 27/200 and 34/200 on two separate runs).
- The `date_of_birth` pending-conflict path was put through the same control: racing two disagreements
  that both beat the confirmed baseline against the broken store produced an unexpected exception in
  81/200 trials on the most recent run — proving this new correctness-critical path is exercising the
  same lock, not accidentally race-free by construction.
- Both scenarios produced **zero** wrong outcomes, every run, against the real, correctly-locking store.

That's what proves the passing result against the real store is meaningful, and it's what the row lock
in `IdentityFieldProvenanceStore.lockOrCreate` exists to close — implement that lock faithfully against
your own database, or these exact races reappear in your adapter.

When you build this against your own real database (not the in-memory fakes), re-run the adversarial
comparison once against your own store with the lock deliberately stubbed out — for *both* the general
recency-wins race and the `date_of_birth` pending-conflict race. If neither can be made to fail against
a broken store, your test isn't exercising the lock either.

Two worked examples are in the build. `AdversarialLockProofTest` runs the race 60 times against the
in-memory store and, with `EHR_ADVERSARIAL=1`, against a deliberately non-locking one. The
single-transaction equivalent against real PostgreSQL is `JpaIdentityFieldProvenanceStorePostgresTest`
TC-EHR-PROV-003, which was verified by swapping its locking read for a plain one — it failed, and it
was the only one of that class's five cases that did.

**There is now a committed example of exactly that.**
`JpaIdentityFieldProvenanceStorePostgresTest` TC-EHR-PROV-003 drives two real transactions on two
threads against PostgreSQL. It was verified by swapping the locking read for a plain one: it failed,
and it was the *only* one of the five that failed — so it is specifically sensitive to the lock rather
than passing for some unrelated reason. That second check is the part worth copying. A concurrency
test you have never seen fail is not evidence of anything.

## Where the code lives

**Updated 2026-09-28.** This started as a standalone Maven module with its own `pom.xml`. Nothing built
it: there was no root aggregator pom, `backend/core` had no dependency on it, and no CI workflow
referenced it — so the contract suite below never ran in the pipeline, and no application code could
import the interfaces. The sources now live inside `backend/core` instead, where the existing build
compiles and tests them automatically. The standalone `pom.xml` is gone; this is a single-module
repository, so a separately-versioned artifact was buying nothing.

- `backend/core/src/main/java/com/careconnect/ehr/reconciliation/` — the library. Import it directly;
  there is no dependency to add.
- `backend/core/src/test/java/com/careconnect/ehr/reconciliation/` —
  `AbstractIdentityReconciliationContractTest` (extend this), plus the in-memory reference
  implementation (`InMemoryContractTest` and `support/`) proving the contract is satisfiable. All 16
  scenarios run as part of `backend/core`'s normal test run.
- `backend/core/src/main/java/com/careconnect/ehr/reconciliation/jpa/` — **added 2026-09-29.** A
  complete working implementation of all four interfaces against PostgreSQL:
  `JpaIdentityFieldProvenanceStore`, `JpaPatientFieldAccessor`, `JpaIdentityConflictAuditWriter` and
  `SpringTransactionRunner`. If your adapter uses the same `patient` table and the same canonical
  schema, you may not need your own — read these before writing a fourth copy.
- `backend/core/src/test/java/com/careconnect/ehr/reconciliation/jpa/JpaContractPostgresTest` — the
  same 16 scenarios wired to that implementation and run against a real database. This is the shape
  to copy for your own subclass.

### Breaking change, 2026-09-29 — `IdentityConflictAuditWriter.recordDecision`

It gained an `Instant sourceUpdatedAt` parameter, inserted after `incomingValue`. Only affects you if
you wrote your own audit writer; callers of `reconcile(...)` are unaffected.

`ehr_identity_conflict.source_updated_at` is `NOT NULL` on every row and the interface had no way to
supply it, so no implementation could satisfy both — the interface was unimplementable, and nothing
said so because its only implementation was an in-memory fake storing `null`. Free in a `HashMap`,
rejected outright by the database. It also left a `REJECTED` row recording that a value lost without
recording the timestamp it lost *with*, which is the one fact separating a correct rejection from a
bug.

The general lesson, which has now cost this workstream three separate bugs: **a test double more
permissive than the schema turns a design error into a passing test.** The H2 profile aliases `jsonb`
to `TEXT`; the fake accepted nulls the database forbids. If a behaviour is enforced by a constraint,
the test that proves it has to run on PostgreSQL.

## Files still in this directory

- `ehr_identity_field_provenance.sql` — DDL for the one new table this library needs. It carries
  no organization-scoping column: `org_id`/`organization_id`/`tenant_id` appear nowhere in this
  codebase, so an earlier TODO to "match patient's real tenant column" had nothing to match and
  nothing that could have populated a NOT NULL column. See the plan's 2026-09-26 org-scoping
  reversal; `orgId` left this library's interfaces for the same reason.
`manual-verify/` used to sit here: three files outside every Maven module, written when the authoring
environment had no JUnit or Maven Central. Nothing compiled them, so nothing noticed when the
`Object`-to-`Long` id change broke all three. They were removed on 2026-09-30 and replaced by
`AdversarialLockProofTest` plus `support/UnsafeProvenanceStore` in `backend/core/src/test`, which the
build compiles and the linters see. Raised in the PR #209 review.
