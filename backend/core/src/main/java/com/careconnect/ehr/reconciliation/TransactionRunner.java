package com.careconnect.ehr.reconciliation;

/**
 * The one piece of framework glue each adapter team supplies: a way to run a block of work inside a
 * single database transaction, using whatever transaction manager their service already uses (Spring
 * {@code @Transactional} via a wrapper, plain JDBC {@code Connection}, etc.). Everything
 * {@link IdentityFieldProvenanceStore#lockOrCreate}, {@link PatientFieldAccessor}, and
 * {@link IdentityConflictAuditWriter} do inside one call to {@link #runInTransaction} MUST execute on
 * the same connection, so the row lock taken by {@code lockOrCreate} is actually held for the
 * duration of the compare-decide-apply-audit sequence below. If your framework hands out a new
 * connection per repository call by default (e.g. an unmanaged Spring bean without
 * {@code @Transactional}), this is the thing that will silently break the one guarantee this library
 * provides — verify it against {@code AbstractIdentityReconciliationContractTest} before trusting it.
 */
public interface TransactionRunner {
    void runInTransaction(Runnable work);
}
