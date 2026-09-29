package com.careconnect.ehr.reconciliation;

import com.careconnect.ehr.reconciliation.support.InMemoryAuditWriter;
import com.careconnect.ehr.reconciliation.support.InMemoryPatientAccessor;
import com.careconnect.ehr.reconciliation.support.InMemoryProvenanceStore;
import com.careconnect.ehr.reconciliation.support.InMemoryTransactionRunner;
import org.junit.jupiter.api.BeforeEach;

import java.time.Instant;
import java.util.List;
import java.util.concurrent.atomic.AtomicLong;

/**
 * Reference implementation of the contract: wires {@link RecencyWinsIdentityReconciler} to the
 * in-memory fakes and runs every test in {@link AbstractIdentityReconciliationContractTest} against
 * it. This is what proves the contract is actually satisfiable, and it's the example each adapter
 * team's own subclass (wired to a real test database instead) should follow the shape of.
 */
class InMemoryContractTest extends AbstractIdentityReconciliationContractTest {

    private InMemoryProvenanceStore provenanceStore;
    private InMemoryPatientAccessor patientAccessor;
    private InMemoryAuditWriter auditWriter;
    private IdentityReconciler reconciler;
    private final AtomicLong patientIdSeq = new AtomicLong(1);

    @BeforeEach
    void setUp() {
        provenanceStore = new InMemoryProvenanceStore();
        patientAccessor = new InMemoryPatientAccessor();
        auditWriter = new InMemoryAuditWriter();
        reconciler = new RecencyWinsIdentityReconciler(
                provenanceStore, patientAccessor, auditWriter, new InMemoryTransactionRunner());
    }

    @Override
    protected IdentityReconciler reconciler() {
        return reconciler;
    }

    @Override
    protected PatientFieldAccessor patientAccessor() {
        return patientAccessor;
    }

    @Override
    protected IdentityConflictAuditWriter auditWriter() {
        return auditWriter;
    }

    @Override
    protected void seedPatientUpdatedAt(Object patientId, Instant instant) {
        patientAccessor.seedPatientUpdatedAt(patientId, instant);
    }

    @Override
    protected List<RecordedDecision> decisionsFor(Object patientId, String fieldName) {
        return auditWriter.decisionsFor(patientId, fieldName);
    }

    @Override
    protected Object freshPatientId() {
        return patientIdSeq.getAndIncrement();
    }

    @Override
    protected Object sourceId(String sourceCode) {
        return sourceCode; // in-memory fakes treat the source code itself as the id
    }
}
