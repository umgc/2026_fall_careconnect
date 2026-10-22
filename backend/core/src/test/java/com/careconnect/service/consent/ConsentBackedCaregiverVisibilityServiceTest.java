package com.careconnect.service.consent;

import com.careconnect.model.Patient;
import com.careconnect.model.User;
import com.careconnect.repository.PatientRepository;
import com.careconnect.service.CaregiverPatientLinkService;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

/**
 * Both-gates contract (WBS 3.15.5 + TC-E-SUM-009): GRANTED requires effective Ask AI
 * retrieval consent AND a patient-approved caregiver-visibility record. Either absent
 * holds the summary back.
 */
@ExtendWith(MockitoExtension.class)
class ConsentBackedCaregiverVisibilityServiceTest {

    private static final Long CG = 5L, PATIENT_ENTITY = 100L, PATIENT_USER = 9L;

    private final ConsentService consentService = mock(ConsentService.class);
    private final CaregiverPatientLinkService linkService = mock(CaregiverPatientLinkService.class);
    private final PatientRepository patientRepository = mock(PatientRepository.class);
    private final com.careconnect.service.visibility.CaregiverVisibilityService store =
            mock(com.careconnect.service.visibility.CaregiverVisibilityService.class);

    private final ConsentBackedCaregiverVisibilityService service =
            new ConsentBackedCaregiverVisibilityService(consentService, linkService, patientRepository, store);

    /**
     * Resolves PATIENT_ENTITY -> PATIENT_USER and puts the caregiver in the care circle.
     */
    private void stubLinkedPatient() {
        User user = new User();
        user.setId(PATIENT_USER);
        Patient patient = mock(Patient.class);
        lenient().when(patient.getUser()).thenReturn(user);
        when(patientRepository.findById(PATIENT_ENTITY)).thenReturn(Optional.of(patient));
        when(linkService.hasAccessToPatient(CG, PATIENT_USER)).thenReturn(true);
    }

    @Test
    @DisplayName("TC-CONSENT-030 caregiver summary visibility is GRANTED only when AI-retrieval consent and the visibility record both pass")
    void granted_onlyWhenConsentAndVisibilityBothPass() {
        stubLinkedPatient();
        when(consentService.isEffectiveAiRetrievalConsent(CG, PATIENT_USER)).thenReturn(true);
        when(store.canViewSummaries(CG, PATIENT_USER)).thenReturn(true);

        CaregiverVisibilityCheck check = service.getStatus(CG, PATIENT_ENTITY);

        assertThat(check.status()).isEqualTo(CaregiverVisibilityStatus.GRANTED);
        assertThat(check.canViewSummaries()).isTrue();
    }

    @Test
    @DisplayName("TC-CONSENT-031 caregiver summary visibility is blocked with consent but no visibility record")
    void blocked_whenConsentEffectiveButNoVisibilityRecord() {
        stubLinkedPatient();
        when(consentService.isEffectiveAiRetrievalConsent(CG, PATIENT_USER)).thenReturn(true);
        when(store.canViewSummaries(CG, PATIENT_USER)).thenReturn(false);

        CaregiverVisibilityCheck check = service.getStatus(CG, PATIENT_ENTITY);

        assertThat(check.status()).isNotEqualTo(CaregiverVisibilityStatus.GRANTED);
        assertThat(check.canViewSummaries()).isFalse();
    }

    @Test
    @DisplayName("TC-CONSENT-032 caregiver summary visibility is blocked with a visibility record but no consent")
    void blocked_whenVisibilityGrantedButNoConsent() {
        stubLinkedPatient();
        when(consentService.isEffectiveAiRetrievalConsent(CG, PATIENT_USER)).thenReturn(false);
        lenient().when(store.canViewSummaries(CG, PATIENT_USER)).thenReturn(true);

        CaregiverVisibilityCheck check = service.getStatus(CG, PATIENT_ENTITY);

        assertThat(check.status()).isNotEqualTo(CaregiverVisibilityStatus.GRANTED);
        assertThat(check.canViewSummaries()).isFalse();
    }

    // ===== Early exits and the REVOKED state (coverage gate, PR #325). Characterize the inherited behaviour:
    // none() means "this gate does not apply" (status NONE, canViewSummaries true); the surrounding
    // access checks decide. Test IDs TC-CONSENT-033 to 037, Software Test Plan §3.20.

    @Test
    @DisplayName("TC-CONSENT-033 canViewSummaries returns the getStatus decision: true when both gates pass")
    void canViewSummaries_delegatesToStatus() {
        stubLinkedPatient();
        when(consentService.isEffectiveAiRetrievalConsent(CG, PATIENT_USER)).thenReturn(true);
        when(store.canViewSummaries(CG, PATIENT_USER)).thenReturn(true);

        assertThat(service.canViewSummaries(CG, PATIENT_ENTITY)).isTrue();
    }

    @Test
    @DisplayName("TC-CONSENT-034 a missing caregiver or patient id is NONE and looks nothing up")
    void none_whenIdsMissing() {
        assertThat(service.getStatus(null, PATIENT_ENTITY)).isEqualTo(CaregiverVisibilityCheck.none());
        assertThat(service.getStatus(CG, null)).isEqualTo(CaregiverVisibilityCheck.none());

        verifyNoInteractions(patientRepository, linkService, consentService, store);
    }

    @Test
    @DisplayName("TC-CONSENT-035 a patient record that does not exist is NONE and no consent is asked")
    void none_whenPatientRecordUnknown() {
        when(patientRepository.findById(PATIENT_ENTITY)).thenReturn(Optional.empty());

        assertThat(service.getStatus(CG, PATIENT_ENTITY)).isEqualTo(CaregiverVisibilityCheck.none());

        verifyNoInteractions(linkService, consentService, store);
    }

    @Test
    @DisplayName("TC-CONSENT-036 a caregiver outside the patient's care circle is NONE and no consent is asked")
    void none_whenNoCareCircleLink() {
        User user = new User();
        user.setId(PATIENT_USER);
        Patient patient = mock(Patient.class);
        when(patient.getUser()).thenReturn(user);
        when(patientRepository.findById(PATIENT_ENTITY)).thenReturn(Optional.of(patient));
        when(linkService.hasAccessToPatient(CG, PATIENT_USER)).thenReturn(false);

        assertThat(service.getStatus(CG, PATIENT_ENTITY)).isEqualTo(CaregiverVisibilityCheck.none());

        verifyNoInteractions(consentService, store);
    }

    @Test
    @DisplayName("TC-CONSENT-037 a linked caregiver whose AI-retrieval consent has grant history but is not in effect is REVOKED")
    void revoked_whenConsentHistoryWithoutEffectiveConsent() {
        stubLinkedPatient();
        when(consentService.isEffectiveAiRetrievalConsent(CG, PATIENT_USER)).thenReturn(false);
        lenient().when(store.canViewSummaries(CG, PATIENT_USER)).thenReturn(true);
        when(consentService.hasAnyAiRetrievalGrantHistory(CG, PATIENT_USER)).thenReturn(true);

        CaregiverVisibilityCheck check = service.getStatus(CG, PATIENT_ENTITY);

        assertThat(check.status()).isEqualTo(CaregiverVisibilityStatus.REVOKED);
        assertThat(check.canViewSummaries()).isFalse();
    }
}
