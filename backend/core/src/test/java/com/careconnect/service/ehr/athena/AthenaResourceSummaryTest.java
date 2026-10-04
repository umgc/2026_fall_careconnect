package com.careconnect.service.ehr.athena;

import com.fasterxml.jackson.databind.node.ObjectNode;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static com.careconnect.testsupport.fixtures.AthenaFhirFixtures.JSON;
import static com.careconnect.testsupport.fixtures.AthenaFhirFixtures.romilda;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;

/**
 * Covers where {@link AthenaResourceSummary} finds a title and a date across the resource shapes the
 * sync stores, including the Immunization and Procedure date fields the Epic mapping does not read.
 */
class AthenaResourceSummaryTest {

    private static ObjectNode resource(final String type) {
        return JSON.createObjectNode().put("resourceType", type).put("id", "x");
    }

    @Test
    @DisplayName("an Immunization is titled by vaccineCode and dated by occurrenceDateTime")
    void immunization() {
        final ObjectNode immunization = resource("Immunization").put("occurrenceDateTime", "2023-10-01");
        immunization.putObject("vaccineCode").putArray("coding").addObject().put("display", "Influenza");

        assertEquals("Immunization: Influenza", AthenaResourceSummary.title("Immunization", immunization));
        assertEquals("2023-10-01", AthenaResourceSummary.occurredAt(immunization));
    }

    @Test
    @DisplayName("a Procedure with only performedPeriod is dated by its start")
    void procedurePeriod() {
        final ObjectNode procedure = resource("Procedure");
        procedure.putObject("performedPeriod").put("start", "2022-05-01T09:00:00Z");
        procedure.putObject("code").put("text", "Colonoscopy");

        assertEquals("Procedure: Colonoscopy", AthenaResourceSummary.title("Procedure", procedure));
        assertEquals("2022-05-01T09:00:00Z", AthenaResourceSummary.occurredAt(procedure));
    }

    @Test
    @DisplayName("an Encounter falls back to the first of its type array, then period.start")
    void encounter() {
        final ObjectNode encounter = resource("Encounter");
        encounter.putArray("type").addObject().put("text", "Office visit");
        encounter.putObject("period").put("start", "2024-02-02");

        assertEquals("Encounter: Office visit", AthenaResourceSummary.title("Encounter", encounter));
        assertEquals("2024-02-02", AthenaResourceSummary.occurredAt(encounter));
    }

    @Test
    @DisplayName("a Patient is titled by type alone, so no name reaches the title column")
    void patientTitleCarriesNoName() {
        assertEquals("Patient", AthenaResourceSummary.title("Patient", romilda()));
        assertNull(AthenaResourceSummary.occurredAt(romilda()));
    }
}
