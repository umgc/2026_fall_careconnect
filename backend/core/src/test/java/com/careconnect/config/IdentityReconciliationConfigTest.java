package com.careconnect.config;

import com.careconnect.ehr.reconciliation.IdentityConflictAuditWriter;
import com.careconnect.ehr.reconciliation.IdentityFieldProvenanceStore;
import com.careconnect.ehr.reconciliation.IdentityReconciler;
import com.careconnect.ehr.reconciliation.PatientFieldAccessor;
import com.careconnect.ehr.reconciliation.RecencyWinsIdentityReconciler;
import com.careconnect.ehr.reconciliation.TransactionRunner;
import com.careconnect.ehr.reconciliation.jpa.JpaIdentityConflictAuditWriter;
import com.careconnect.ehr.reconciliation.jpa.JpaIdentityFieldProvenanceStore;
import com.careconnect.ehr.reconciliation.jpa.JpaPatientFieldAccessor;
import com.careconnect.ehr.reconciliation.jpa.SpringTransactionRunner;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.ehr.EhrIdentityConflictRepository;
import com.careconnect.repository.ehr.EhrIdentityFieldProvenanceRepository;
import jakarta.persistence.EntityManager;
import org.junit.jupiter.api.Test;
import org.springframework.transaction.PlatformTransactionManager;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;

/**
 * Verifies {@link IdentityReconciliationConfig} assembles the reconciliation library into the right
 * concrete beans. Pure unit test: each {@code @Bean} method is called with mocked leaf dependencies
 * (no Spring context), and the wired implementation type is asserted.
 */
class IdentityReconciliationConfigTest {

    private final IdentityReconciliationConfig config = new IdentityReconciliationConfig();

    @Test
    void identityFieldProvenanceStore_isJpaBacked() {
        final IdentityFieldProvenanceStore store = config.identityFieldProvenanceStore(
                mock(EhrIdentityFieldProvenanceRepository.class), mock(EntityManager.class));
        assertThat(store).isInstanceOf(JpaIdentityFieldProvenanceStore.class);
    }

    @Test
    void patientFieldAccessor_isJpaBacked() {
        final PatientFieldAccessor accessor = config.patientFieldAccessor(mock(PatientRepository.class));
        assertThat(accessor).isInstanceOf(JpaPatientFieldAccessor.class);
    }

    @Test
    void identityConflictAuditWriter_isJpaBacked() {
        final IdentityConflictAuditWriter writer =
                config.identityConflictAuditWriter(mock(EhrIdentityConflictRepository.class));
        assertThat(writer).isInstanceOf(JpaIdentityConflictAuditWriter.class);
    }

    @Test
    void identityTransactionRunner_isSpringBacked() {
        final TransactionRunner runner =
                config.identityTransactionRunner(mock(PlatformTransactionManager.class));
        assertThat(runner).isInstanceOf(SpringTransactionRunner.class);
    }

    @Test
    void identityReconciler_isRecencyWins() {
        final IdentityReconciler reconciler = config.identityReconciler(
                mock(IdentityFieldProvenanceStore.class),
                mock(PatientFieldAccessor.class),
                mock(IdentityConflictAuditWriter.class),
                mock(TransactionRunner.class));
        assertThat(reconciler).isInstanceOf(RecencyWinsIdentityReconciler.class);
    }
}
