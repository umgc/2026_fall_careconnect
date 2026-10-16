package com.careconnect.repository.emergency;

import com.careconnect.model.emergency.BloodType;
import com.careconnect.model.emergency.EmergencyPassportFieldVisibility;
import com.careconnect.model.emergency.EmergencyPassportProfile;
import com.careconnect.model.emergency.PassportField;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.test.context.ActiveProfiles;

import java.time.LocalDateTime;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * Entity mapping and repository behaviour for the CC-12 Increment 1 passport tables, on the H2 test
 * profile. Covers what the entities themselves declare: column mapping, the hidden-by-default rule
 * and the two unique constraints.
 * <p>
 * The foreign keys, cascade and {@code TIMESTAMPTZ} columns come from {@code SchemaPatchRunner},
 * which skips its PostgreSQL patches on H2; {@link EmergencyPassportSchemaPostgresTest} covers those.
 * Patient ids are bare longs here because H2 has no foreign key to satisfy.
 * <p>
 * Test IDs TC-EMG-029…035 (the author's) and TC-EMG-044…049 (the Testing Lead's) are permanent,
 * Test Plan §3.23. Never renumber, never reuse.
 */
@DataJpaTest
@ActiveProfiles("test")
@DisplayName("Emergency passport repositories (CC-12 Increment 1)")
class EmergencyPassportRepositoryTest {

    @Autowired
    private EmergencyPassportProfileRepository profileRepository;

    @Autowired
    private EmergencyPassportFieldVisibilityRepository visibilityRepository;

    @Test
    @DisplayName("TC-EMG-029: a profile round-trips every field, blood type stored by enum name")
    void profileRoundTrips() {
        profileRepository.saveAndFlush(EmergencyPassportProfile.builder()
                .patientId(101L)
                .bloodType(BloodType.AB_NEGATIVE)
                .chronicConditions("Type 2 diabetes; atrial fibrillation")
                .emergencyContactName("Dana Example")
                .emergencyContactPhone("+1-555-0100")
                .emergencyContactRelationship("daughter")
                .build());

        EmergencyPassportProfile reloaded = profileRepository.findByPatientId(101L).orElseThrow();
        assertThat(reloaded.getBloodType()).isEqualTo(BloodType.AB_NEGATIVE);
        assertThat(reloaded.getChronicConditions()).isEqualTo("Type 2 diabetes; atrial fibrillation");
        assertThat(reloaded.getEmergencyContactName()).isEqualTo("Dana Example");
        assertThat(reloaded.getEmergencyContactPhone()).isEqualTo("+1-555-0100");
        assertThat(reloaded.getEmergencyContactRelationship()).isEqualTo("daughter");
        assertThat(reloaded.getCreatedAt()).isNotNull();
        assertThat(reloaded.getUpdatedAt()).isNotNull();
    }

    @Test
    @DisplayName("TC-EMG-030: a profile may leave every value empty")
    void emptyProfileIsAllowed() {
        profileRepository.saveAndFlush(EmergencyPassportProfile.builder().patientId(102L).build());

        EmergencyPassportProfile reloaded = profileRepository.findByPatientId(102L).orElseThrow();
        assertThat(reloaded.getBloodType()).isNull();
        assertThat(reloaded.getChronicConditions()).isNull();
        assertThat(reloaded.getEmergencyContactName()).isNull();
    }

    @Test
    @DisplayName("TC-EMG-031: a patient cannot hold two profiles")
    void secondProfileForOnePatientIsRejected() {
        profileRepository.saveAndFlush(EmergencyPassportProfile.builder().patientId(103L).build());

        assertThatThrownBy(() -> profileRepository.saveAndFlush(
                EmergencyPassportProfile.builder().patientId(103L).build()))
                .isInstanceOf(DataIntegrityViolationException.class);
    }

    @Test
    @DisplayName("TC-EMG-032: a visibility row built without is_public is hidden")
    void visibilityDefaultsToHidden() {
        visibilityRepository.saveAndFlush(EmergencyPassportFieldVisibility.builder()
                .patientId(104L)
                .fieldKey(PassportField.BLOOD_TYPE)
                .build());

        assertThat(visibilityRepository.findByPatientIdAndFieldKey(104L, PassportField.BLOOD_TYPE))
                .get().extracting(EmergencyPassportFieldVisibility::getIsPublic).isEqualTo(false);
        assertThat(visibilityRepository.findPublicFields(104L)).isEmpty();
    }

    @Test
    @DisplayName("TC-EMG-033: a patient with no visibility rows shows nothing")
    void noRowsMeansNothingIsPublic() {
        assertThat(visibilityRepository.findPublicFields(105L)).isEmpty();
    }

    @Test
    @DisplayName("TC-EMG-034: only fields explicitly made public are returned, and only for that patient")
    void findPublicFieldsReturnsOnlyExplicitOptIns() {
        // Arrange: patient 106 makes two fields public and one hidden; patient 107 makes one public.
        save(106L, PassportField.ALLERGIES, true);
        save(106L, PassportField.MEDICATIONS, true);
        save(106L, PassportField.EMERGENCY_CONTACT, false);
        save(107L, PassportField.BLOOD_TYPE, true);

        // Assert: CHRONIC_CONDITIONS has no row and EMERGENCY_CONTACT is false; neither appears.
        assertThat(visibilityRepository.findPublicFields(106L))
                .containsExactlyInAnyOrder(PassportField.ALLERGIES, PassportField.MEDICATIONS);
        assertThat(visibilityRepository.findByPatientId(106L)).hasSize(3);
        assertThat(visibilityRepository.findPublicFields(107L)).containsExactly(PassportField.BLOOD_TYPE);
        assertThat(visibilityRepository.findByPatientId(107L)).hasSize(1);
    }

    @Test
    @DisplayName("TC-EMG-035: a patient cannot hold two visibility rows for the same field")
    void secondVisibilityRowForOneFieldIsRejected() {
        save(108L, PassportField.ALLERGIES, false);

        assertThatThrownBy(() -> save(108L, PassportField.ALLERGIES, true))
                .isInstanceOf(DataIntegrityViolationException.class);
    }

    @Test
    @DisplayName("TC-EMG-044: every blood type round-trips by name")
    void everyBloodTypeRoundTrips() {
        long patientId = 200L;
        for (BloodType bloodType : BloodType.values()) {
            profileRepository.saveAndFlush(EmergencyPassportProfile.builder()
                    .patientId(patientId)
                    .bloodType(bloodType)
                    .build());
            assertThat(profileRepository.findByPatientId(patientId).orElseThrow().getBloodType())
                    .as("patient %d", patientId).isEqualTo(bloodType);
            patientId++;
        }
    }

    @Test
    @DisplayName("TC-EMG-045: a profile without a patient is rejected")
    void profileWithoutPatientIsRejected() {
        assertThatThrownBy(() -> profileRepository.saveAndFlush(EmergencyPassportProfile.builder()
                .bloodType(BloodType.O_NEGATIVE)
                .build()))
                .isInstanceOf(DataIntegrityViolationException.class);
    }

    @Test
    @DisplayName("TC-EMG-046: a visibility row without a field is rejected")
    void visibilityWithoutFieldIsRejected() {
        assertThatThrownBy(() -> visibilityRepository.saveAndFlush(EmergencyPassportFieldVisibility.builder()
                .patientId(109L)
                .isPublic(true)
                .build()))
                .isInstanceOf(DataIntegrityViolationException.class);
    }

    @Test
    @DisplayName("TC-EMG-047: a visibility row with is_public explicitly null is rejected, not stored as a third state")
    void visibilityWithNullIsPublicIsRejected() {
        assertThatThrownBy(() -> visibilityRepository.saveAndFlush(EmergencyPassportFieldVisibility.builder()
                .patientId(110L)
                .fieldKey(PassportField.ALLERGIES)
                .isPublic(null)
                .build()))
                .isInstanceOf(DataIntegrityViolationException.class);
    }

    @Test
    @DisplayName("TC-EMG-048: hiding a public field again removes it from the public set and advances updated_at")
    void hidingAFieldAgainIsRecorded() throws InterruptedException {
        EmergencyPassportFieldVisibility row = visibilityRepository.saveAndFlush(EmergencyPassportFieldVisibility.builder()
                .patientId(111L)
                .fieldKey(PassportField.MEDICATIONS)
                .isPublic(true)
                .build());
        assertThat(visibilityRepository.findPublicFields(111L)).containsExactly(PassportField.MEDICATIONS);
        LocalDateTime createdAt = row.getCreatedAt();
        LocalDateTime madePublicAt = row.getUpdatedAt();

        Thread.sleep(20);
        row.setIsPublic(false);
        visibilityRepository.saveAndFlush(row);

        EmergencyPassportFieldVisibility reloaded =
                visibilityRepository.findByPatientIdAndFieldKey(111L, PassportField.MEDICATIONS).orElseThrow();
        assertThat(visibilityRepository.findPublicFields(111L)).isEmpty();
        assertThat(reloaded.getIsPublic()).isFalse();
        assertThat(reloaded.getUpdatedAt()).isAfter(madePublicAt);
        assertThat(reloaded.getCreatedAt()).isEqualTo(createdAt);
    }

    @Test
    @DisplayName("TC-EMG-049: one patient's profile is never returned for another patient")
    void profileLookupIsPerPatient() {
        profileRepository.saveAndFlush(EmergencyPassportProfile.builder()
                .patientId(112L)
                .bloodType(BloodType.B_POSITIVE)
                .emergencyContactName("Pat Example")
                .build());

        assertThat(profileRepository.findByPatientId(113L)).isEmpty();
        assertThat(profileRepository.findByPatientId(112L)).get()
                .extracting(EmergencyPassportProfile::getPatientId).isEqualTo(112L);
    }

    private void save(long patientId, PassportField field, boolean isPublic) {
        visibilityRepository.saveAndFlush(EmergencyPassportFieldVisibility.builder()
                .patientId(patientId)
                .fieldKey(field)
                .isPublic(isPublic)
                .build());
    }
}
