package com.careconnect.service.ai.retrieval;

import com.careconnect.security.Role;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

class CaregiverVisibilityFilterTest {

    @Test
    @DisplayName("patient and admin bypass caregiver visibility gates")
    void patientAndAdminBypassGates() {
        CaregiverVisibilityFilter patientFilter = new CaregiverVisibilityFilter(Role.PATIENT, false);
        CaregiverVisibilityFilter adminFilter = new CaregiverVisibilityFilter(Role.ADMIN, false);

        assertThat(patientFilter.permits("hidden")).isTrue();
        assertThat(adminFilter.permits("patient_only")).isTrue();
    }

    @Test
    @DisplayName("caregiver requires consent for on_consent rows")
    void caregiverRequiresConsentForOnConsent() {
        CaregiverVisibilityFilter withoutConsent = new CaregiverVisibilityFilter(Role.CAREGIVER, false);
        CaregiverVisibilityFilter withConsent = new CaregiverVisibilityFilter(Role.CAREGIVER, true);

        assertThat(withoutConsent.permits("on_consent")).isFalse();
        assertThat(withConsent.permits("on_consent")).isTrue();
        assertThat(withoutConsent.permits("auto")).isTrue();
        assertThat(withoutConsent.permits("hidden")).isFalse();
    }

    @Test
    @DisplayName("family member cannot see hidden or patient_only rows")
    void familyMemberRestricted() {
        CaregiverVisibilityFilter filter = new CaregiverVisibilityFilter(Role.FAMILY_MEMBER, false);

        assertThat(filter.permits("hidden")).isFalse();
        assertThat(filter.permits("patient_only")).isFalse();
        assertThat(filter.permits("shared")).isTrue();
        assertThat(filter.permits("on_consent")).isFalse();
    }
}
