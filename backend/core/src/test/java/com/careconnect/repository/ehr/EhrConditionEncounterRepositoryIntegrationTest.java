package com.careconnect.repository.ehr;

import static org.assertj.core.api.Assertions.assertThat;

import com.careconnect.model.ehr.EhrCodeValue;
import com.careconnect.model.ehr.EhrConditionRecord;
import com.careconnect.model.ehr.EhrEncounterParticipantValue;
import com.careconnect.model.ehr.EhrEncounterRecord;
import jakarta.persistence.EntityManager;
import java.util.List;
import org.junit.jupiter.api.Tag;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.test.context.ActiveProfiles;

/** Proves the new canonical Condition and Encounter entity mappings on the H2 test database. */
@DataJpaTest
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@ActiveProfiles("test")
@Tag("M3-REQ-17")
@Tag("M3-REQ-18")
class EhrConditionEncounterRepositoryIntegrationTest {

    @Autowired
    private EhrConditionRecordRepository conditions;

    @Autowired
    private EhrEncounterRecordRepository encounters;

    @Autowired
    private EntityManager entityManager;

    @Test
    void conditionStructuredCollectionsRoundTrip() {
        final EhrConditionRecord saved = conditions.saveAndFlush(EhrConditionRecord.builder()
                .patientId(7L)
                .sourceId(4L)
                .externalConditionId("condition-1")
                .categories(List.of(new EhrCodeValue("category-system", "problem", "Problem", null)))
                .conditionCodes(List.of(new EhrCodeValue(
                        "http://snomed.info/sct", "38341003", "Hypertension", "Synthetic hypertension")))
                .bodySites(List.of())
                .hiddenFromActiveList(false)
                .build());
        entityManager.clear();

        final EhrConditionRecord found = conditions.findById(saved.getId()).orElseThrow();

        assertThat(found.getCategories()).singleElement().satisfies(category ->
                assertThat(category.code()).isEqualTo("problem"));
        assertThat(found.getConditionCodes()).singleElement().satisfies(code -> {
            assertThat(code.code()).isEqualTo("38341003");
            assertThat(code.text()).isEqualTo("Synthetic hypertension");
        });
        assertThat(found.getBodySites()).isEmpty();
    }

    @Test
    void encounterStructuredParticipantsRoundTrip() {
        final EhrEncounterRecord saved = encounters.saveAndFlush(EhrEncounterRecord.builder()
                .patientId(7L)
                .sourceId(4L)
                .externalEncounterId("encounter-1")
                .status("finished")
                .encounterTypes(List.of())
                .participants(List.of(new EhrEncounterParticipantValue(
                        List.of(new EhrCodeValue("role-system", "PPRF", "Primary performer", null)),
                        "Practitioner/1",
                        "Synthetic Clinician",
                        "2026-09-18T14:00:00Z",
                        "2026-09-18T15:00:00Z")))
                .locations(List.of())
                .reasonCodes(List.of())
                .diagnosisReferences(List.of())
                .appointmentReferences(List.of())
                .build());
        entityManager.clear();

        final EhrEncounterRecord found = encounters.findById(saved.getId()).orElseThrow();

        assertThat(found.getParticipants()).singleElement().satisfies(participant -> {
            assertThat(participant.reference()).isEqualTo("Practitioner/1");
            assertThat(participant.types()).singleElement().satisfies(type ->
                    assertThat(type.code()).isEqualTo("PPRF"));
        });
    }
}
