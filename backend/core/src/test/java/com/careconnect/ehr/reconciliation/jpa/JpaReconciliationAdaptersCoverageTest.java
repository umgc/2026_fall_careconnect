package com.careconnect.ehr.reconciliation.jpa;

import com.careconnect.model.Patient;
import com.careconnect.model.ehr.EhrIdentityFieldProvenance;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.ehr.EhrIdentityFieldProvenanceRepository;
import jakarta.persistence.EntityManager;
import jakarta.persistence.Query;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.springframework.transaction.support.TransactionSynchronizationManager;

import java.time.Instant;
import java.time.LocalDateTime;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Mock-backed unit coverage for the JPA reconciliation adapters; the row-locking semantics are
 * verified against PostgreSQL by the *PostgresTest classes in this package.
 */
class JpaReconciliationAdaptersCoverageTest {

    @AfterEach
    void clearTransaction() {
        TransactionSynchronizationManager.setActualTransactionActive(false);
    }

    @Test
    void provenanceStoreLocksCreatesAndRecords() {
        EhrIdentityFieldProvenanceRepository repo = mock(EhrIdentityFieldProvenanceRepository.class);
        EntityManager em = mock(EntityManager.class);
        Query query = mock(Query.class);
        when(em.createNativeQuery(anyString())).thenReturn(query);
        when(query.setParameter(anyString(), any())).thenReturn(query);
        JpaIdentityFieldProvenanceStore store = new JpaIdentityFieldProvenanceStore(repo, em);

        assertThatThrownBy(() -> store.lockOrCreate(1L, "given_name")).isInstanceOf(IllegalStateException.class);
        TransactionSynchronizationManager.setActualTransactionActive(true);

        EhrIdentityFieldProvenance placeholder = EhrIdentityFieldProvenance.builder().patientId(1L).build();
        when(repo.lockByPatientIdAndFieldName(1L, "given_name"))
                .thenReturn(Optional.empty())
                .thenReturn(Optional.of(placeholder));
        assertThat(store.lockOrCreate(1L, "given_name")).isEmpty();
        verify(query).executeUpdate();

        EhrIdentityFieldProvenance known = EhrIdentityFieldProvenance.builder()
                .sourceId(4L).sourceUpdatedAt(Instant.now()).build();
        when(repo.lockByPatientIdAndFieldName(1L, "family_name")).thenReturn(Optional.of(known));
        assertThat(store.lockOrCreate(1L, "family_name")).isPresent();

        when(repo.lockByPatientIdAndFieldName(2L, "x")).thenReturn(Optional.empty());
        assertThatThrownBy(() -> store.lockOrCreate(2L, "x")).isInstanceOf(IllegalStateException.class);
        assertThatThrownBy(() -> store.lockOrCreate(2L, " ")).isInstanceOf(IllegalArgumentException.class);

        store.recordAsFreshest(1L, "family_name", 5L, Instant.now());
        assertThat(known.getSourceId()).isEqualTo(5L);
        verify(em).flush();
        assertThatThrownBy(() -> store.recordAsFreshest(2L, "x", 5L, Instant.now()))
                .isInstanceOf(IllegalStateException.class);
    }

    @Test
    void patientFieldAccessorReadsAndWritesEveryBinding() {
        PatientRepository patients = mock(PatientRepository.class);
        Patient patient = new Patient();
        patient.setId(1L);
        patient.setFirstName("Ann");
        patient.setDob("01/02/1950");
        patient.setUpdatedAt(LocalDateTime.now());
        when(patients.findById(1L)).thenReturn(Optional.of(patient));
        Patient stale = new Patient();
        stale.setId(2L);
        when(patients.findById(2L)).thenReturn(Optional.of(stale));
        JpaPatientFieldAccessor accessor = new JpaPatientFieldAccessor(patients);

        for (String field : JpaPatientFieldAccessor.supportedFieldNames()) {
            accessor.getCurrentValue(1L, field);
        }
        assertThat(accessor.getPatientUpdatedAt(1L)).isNotNull();
        assertThatThrownBy(() -> accessor.getPatientUpdatedAt(2L)).isInstanceOf(IllegalStateException.class);
        assertThatThrownBy(() -> accessor.getCurrentValue(3L, "given_name"))
                .isInstanceOf(IllegalArgumentException.class);

        assertThatThrownBy(() -> accessor.applyValue(1L, "given_name", "Bea"))
                .isInstanceOf(IllegalStateException.class);
        TransactionSynchronizationManager.setActualTransactionActive(true);
        for (String field : JpaPatientFieldAccessor.supportedFieldNames()) {
            String value = field.toLowerCase().contains("birth") || field.toLowerCase().contains("dob")
                    ? "1950-01-02" : " Value ";
            accessor.applyValue(1L, field, value);
            assertThat(accessor.getCurrentValue(1L, field)).isPresent();
        }
        assertThatThrownBy(() -> accessor.applyValue(1L, "unknown_field", "x")).isInstanceOf(RuntimeException.class);
    }
}
