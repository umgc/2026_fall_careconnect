package com.careconnect.service.ehr;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class EhrStatusGateTest {

    private final EhrStatusGate gate = new EhrStatusGate();
    private final ObjectMapper mapper = new ObjectMapper();

    private JsonNode json(String s) {
        try {
            return mapper.readTree(s);
        } catch (Exception e) {
            throw new RuntimeException(e);
        }
    }

    @Test
    void allowsActiveCondition() {
        JsonNode node = json("{\"resourceType\":\"Condition\","
                + "\"clinicalStatus\":{\"coding\":[{\"code\":\"active\"}]},"
                + "\"verificationStatus\":{\"coding\":[{\"code\":\"confirmed\"}]}}");
        assertTrue(gate.isAllowed(node));
    }

    @Test
    void excludesEnteredInErrorViaVerificationStatus() {
        JsonNode node = json("{\"resourceType\":\"Condition\","
                + "\"clinicalStatus\":{\"coding\":[{\"code\":\"active\"}]},"
                + "\"verificationStatus\":{\"coding\":[{\"code\":\"entered-in-error\"}]}}");
        assertFalse(gate.isAllowed(node));
    }

    @Test
    void excludesCancelledMedicationRequest() {
        JsonNode node = json("{\"resourceType\":\"MedicationRequest\",\"status\":\"cancelled\"}");
        assertFalse(gate.isAllowed(node));
    }

    @Test
    void excludesDraft() {
        JsonNode node = json("{\"resourceType\":\"MedicationRequest\",\"status\":\"draft\"}");
        assertFalse(gate.isAllowed(node));
    }

    @Test
    void allowsFinalObservation() {
        JsonNode node = json("{\"resourceType\":\"Observation\",\"status\":\"final\"}");
        assertTrue(gate.isAllowed(node));
    }
}
