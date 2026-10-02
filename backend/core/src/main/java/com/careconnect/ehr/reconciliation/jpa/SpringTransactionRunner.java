package com.careconnect.ehr.reconciliation.jpa;

import com.careconnect.ehr.reconciliation.TransactionRunner;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

import java.util.Objects;

/**
 * Runs one field's reconciliation inside a Spring-managed transaction, which is what makes the
 * provenance row lock mean anything: the lock, the {@code patient} write and the audit row either
 * commit together or roll back together.
 *
 * <p>Propagation is {@code REQUIRED} rather than {@code REQUIRES_NEW}. The reconciler calls this once
 * per field, so {@code REQUIRES_NEW} would mean a caller who wrapped a whole snapshot in a
 * transaction of their own got its fields committed independently of it — a partially reconciled
 * patient surviving a rollback the caller thought was atomic. Joining instead means the caller
 * decides the unit of work, and the default (no surrounding transaction) still gives each field its
 * own, exactly as the algorithm describes.
 *
 * <p>The practical consequence to know: under a caller-supplied outer transaction, every field's
 * provenance lock is held until that outer transaction ends rather than being released field by
 * field. It makes a long-running wrapper hold locks for longer than the per-field design assumes.
 *
 * <p><b>Accumulated locks change what deadlock is possible</b>, which an earlier version of this
 * note glossed as simply "safe — it can only serialise more, never less." That is true of
 * correctness and false of liveness. Holding one lock at a time cannot deadlock; holding several
 * can, as soon as two transactions acquire them in different orders. Raised in the PR #209 review.
 *
 * <p>{@code RecencyWinsIdentityReconciler} now processes fields in sorted order precisely so that
 * cannot happen — one global lock order across all callers. Two things follow for anyone wrapping
 * {@code reconcile()} in an outer transaction: it is safe with respect to <em>this</em> library's
 * locks, and it stops being safe if that outer transaction also takes locks of its own in some
 * other order. Keep the wrapper short, and do not interleave other locking work inside it.
 */
public class SpringTransactionRunner implements TransactionRunner {

    private final TransactionTemplate transactionTemplate;

    public SpringTransactionRunner(PlatformTransactionManager transactionManager) {
        this.transactionTemplate = new TransactionTemplate(
                Objects.requireNonNull(transactionManager, "transactionManager"));
    }

    @Override
    public void runInTransaction(Runnable work) {
        Objects.requireNonNull(work, "work");
        transactionTemplate.executeWithoutResult(status -> work.run());
    }
}
