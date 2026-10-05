package com.careconnect.ehr.reconciliation.jpa;

import com.careconnect.ehr.reconciliation.IdentityFieldNames;
import com.careconnect.repository.PatientRepository;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verifyNoInteractions;

/**
 * The field-name contract, checked without a database so it runs in the standard CI gate.
 * {@code JpaPatientFieldAccessorPostgresTest} TC-EHR-PACC-003 covers the same rejection against
 * PostgreSQL, but is skipped wherever {@code EHR_IT_JDBC_URI} is unset.
 * <p>
 * Test IDs TC-EHR-PACC-011..012 are permanent. Never renumber, never reuse.
 */
class JpaPatientFieldAccessorFieldNamesTest {

    @Test
    @DisplayName("TC-EHR-PACC-011: the accessor binds exactly the names IdentityFieldNames publishes")
    void accessorVocabularyMatchesPublishedConstants() {
        assertThat(JpaPatientFieldAccessor.supportedFieldNames())
                .containsExactlyInAnyOrderElementsOf(IdentityFieldNames.ALL);
    }

    @Test
    @DisplayName("TC-EHR-PACC-012: an unrecognised field name is rejected before the database is touched")
    void unknownFieldNameIsRejectedNotSkipped() {
        final PatientRepository patients = mock(PatientRepository.class);
        final JpaPatientFieldAccessor accessor = new JpaPatientFieldAccessor(patients);

        // Patient's own Java name for the field, the mistake an adapter is most likely to make.
        assertThatThrownBy(() -> accessor.getCurrentValue(1L, "firstName"))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("firstName")
                .hasMessageContaining(IdentityFieldNames.GIVEN_NAME);
        verifyNoInteractions(patients);
    }
}
