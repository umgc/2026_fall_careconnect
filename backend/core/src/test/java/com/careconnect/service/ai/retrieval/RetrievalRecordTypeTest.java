package com.careconnect.service.ai.retrieval;

import com.careconnect.security.Role;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

class RetrievalRecordTypeTest {

    @Test
    @DisplayName("patient defaults exclude USPS mail per RBAC matrix")
    void patientDefaultsExcludeUspsMail() {
        assertThat(RetrievalRecordType.defaultsForRole(Role.PATIENT))
                .doesNotContain(RetrievalRecordType.USPS_MAIL)
                .contains(RetrievalRecordType.CALL_SUMMARY);
    }

    @Test
    @DisplayName("family member defaults are read-only subset without USPS mail")
    void familyMemberDefaultsAreReadOnlySubset() {
        assertThat(RetrievalRecordType.defaultsForRole(Role.FAMILY_MEMBER))
                .doesNotContain(RetrievalRecordType.USPS_MAIL)
                .contains(RetrievalRecordType.CLINICAL_NOTE)
                .doesNotContain(RetrievalRecordType.EVV_RECORD);
    }

    @Test
    @DisplayName("admin defaults include all record types")
    void adminDefaultsIncludeAll() {
        assertThat(RetrievalRecordType.defaultsForRole(Role.ADMIN))
                .containsExactlyInAnyOrderElementsOf(RetrievalRecordType.all());
    }

    @Test
    @DisplayName("caregiver defaults include all record types")
    void caregiverDefaultsIncludeAll() {
        assertThat(RetrievalRecordType.defaultsForRole(Role.CAREGIVER))
                .contains(RetrievalRecordType.USPS_MAIL)
                .containsExactlyInAnyOrderElementsOf(RetrievalRecordType.all());
    }
}
