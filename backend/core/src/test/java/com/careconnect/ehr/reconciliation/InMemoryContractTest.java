package com.careconnect.ehr.reconciliation;

import com.careconnect.ehr.reconciliation.support.InMemoryAuditWriter;
import com.careconnect.ehr.reconciliation.support.InMemoryPatientAccessor;
import com.careconnect.ehr.reconciliation.support.InMemoryProvenanceStore;
import com.careconnect.ehr.reconciliation.support.InMemoryTransactionRunner;
import org.junit.jupiter.api.BeforeEach;

import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
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
    private final AtomicLong sourceIdSeq = new AtomicLong(1);
    private final Map<String, Long> sourceIds = new ConcurrentHashMap<>();

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
    protected void seedPatientUpdatedAt(Long patientId, Instant instant) {
        patientAccessor.seedPatientUpdatedAt(patientId, instant);
    }

    @Override
    protected List<RecordedDecision> decisionsFor(Long patientId, String fieldName) {
        return auditWriter.decisionsFor(patientId, fieldName);
    }

    @Override
    protected Long freshPatientId() {
        return patientIdSeq.getAndIncrement();
    }

    /**
     * Synthesises a numeric id per source code, stable within a test.
     * <p>
     * This used to return the code string itself, which the interfaces allowed when ids were typed
     * {@code Object}. They are {@code Long} as of PR #209 review: every table these ids land in
     * declares them {@code bigint} with a foreign key to {@code patient.id} or {@code ehr_source.id},
     * so no real implementation could ever have used anything else. The fake now matches that
     * instead of exercising a shape the schema forbids.
     */
    @Override
    protected Long sourceId(String sourceCode) {
        return sourceIds.computeIfAbsent(sourceCode, code -> sourceIdSeq.getAndIncrement());
    }
}
