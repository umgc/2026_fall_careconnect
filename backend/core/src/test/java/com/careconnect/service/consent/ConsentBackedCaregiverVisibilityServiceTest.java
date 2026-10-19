package com.careconnect.service.consent;

import com.careconnect.model.Patient;
import com.careconnect.model.User;
import com.careconnect.repository.PatientRepository;
import com.careconnect.service.CaregiverPatientLinkService;
import com.careconnect.service.ConsentService;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.mock;
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
    void granted_onlyWhenConsentAndVisibilityBothPass() {
        stubLinkedPatient();
        when(consentService.isEffectiveAiRetrievalConsent(CG, PATIENT_USER)).thenReturn(true);
        when(store.canViewSummaries(CG, PATIENT_USER)).thenReturn(true);

        CaregiverVisibilityCheck check = service.getStatus(CG, PATIENT_ENTITY);

        assertThat(check.status()).isEqualTo(CaregiverVisibilityStatus.GRANTED);
        assertThat(check.canViewSummaries()).isTrue();
    }

    @Test
    void blocked_whenConsentEffectiveButNoVisibilityRecord() {
        stubLinkedPatient();
        when(consentService.isEffectiveAiRetrievalConsent(CG, PATIENT_USER)).thenReturn(true);
        when(store.canViewSummaries(CG, PATIENT_USER)).thenReturn(false);

        CaregiverVisibilityCheck check = service.getStatus(CG, PATIENT_ENTITY);

        assertThat(check.status()).isNotEqualTo(CaregiverVisibilityStatus.GRANTED);
        assertThat(check.canViewSummaries()).isFalse();
    }

    @Test
    void blocked_whenVisibilityGrantedButNoConsent() {
        stubLinkedPatient();
        when(consentService.isEffectiveAiRetrievalConsent(CG, PATIENT_USER)).thenReturn(false);
        lenient().when(store.canViewSummaries(CG, PATIENT_USER)).thenReturn(true);

        CaregiverVisibilityCheck check = service.getStatus(CG, PATIENT_ENTITY);

        assertThat(check.status()).isNotEqualTo(CaregiverVisibilityStatus.GRANTED);
        assertThat(check.canViewSummaries()).isFalse();
    }
}
