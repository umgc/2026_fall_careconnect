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
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.transaction.PlatformTransactionManager;

/**
 * Wires the {@code ehr.reconciliation} identity-reconciliation library as Spring beans
 * (Cononical_5_1 Step 7). The library and its JPA-backed stores carry no Spring annotations — they
 * are a plain library — so this configuration assembles the chain and exposes the single
 * {@link IdentityReconciler} bean that {@code EpicIdentitySync} and {@code EpicOAuthController}
 * autowire to feed Epic demographics into reconciliation and to resolve a pending date-of-birth
 * conflict. The leaf dependencies (repositories, {@link EntityManager}, the transaction manager)
 * are standard beans Spring provides.
 */
@Configuration
public class IdentityReconciliationConfig {

    @Bean
    public IdentityFieldProvenanceStore identityFieldProvenanceStore(
            final EhrIdentityFieldProvenanceRepository provenanceRepository,
            final EntityManager entityManager) {
        return new JpaIdentityFieldProvenanceStore(provenanceRepository, entityManager);
    }

    @Bean
    public PatientFieldAccessor patientFieldAccessor(final PatientRepository patientRepository) {
        return new JpaPatientFieldAccessor(patientRepository);
    }

    @Bean
    public IdentityConflictAuditWriter identityConflictAuditWriter(
            final EhrIdentityConflictRepository conflictRepository) {
        return new JpaIdentityConflictAuditWriter(conflictRepository);
    }

    @Bean
    public TransactionRunner identityTransactionRunner(final PlatformTransactionManager transactionManager) {
        return new SpringTransactionRunner(transactionManager);
    }

    @Bean
    public IdentityReconciler identityReconciler(
            final IdentityFieldProvenanceStore provenanceStore,
            final PatientFieldAccessor patientFieldAccessor,
            final IdentityConflictAuditWriter auditWriter,
            final TransactionRunner transactionRunner) {
        return new RecencyWinsIdentityReconciler(
                provenanceStore, patientFieldAccessor, auditWriter, transactionRunner);
    }
}
