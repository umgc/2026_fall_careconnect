package com.careconnect.service.ehr;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;

import java.util.ArrayList;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;

/**
 * Unit tests for {@link EpicFhirClient}'s pure Bundle-parsing helpers (no HTTP).
 */
class EpicFhirClientStaticTest {

    private final ObjectMapper mapper = new ObjectMapper();

    private JsonNode json(String s) {
        try {
            return mapper.readTree(s);
        } catch (Exception e) {
            throw new RuntimeException(e);
        }
    }

    @Test
    void extractEntries_pullsBundleResources() {
        JsonNode bundle = json("{\"resourceType\":\"Bundle\",\"entry\":["
                + "{\"resource\":{\"resourceType\":\"Condition\",\"id\":\"c1\"}},"
                + "{\"resource\":{\"resourceType\":\"Condition\",\"id\":\"c2\"}}]}");
        List<JsonNode> out = new ArrayList<>();
        EpicFhirClient.extractEntries(bundle, out);
        assertEquals(2, out.size());
        assertEquals("c1", out.get(0).get("id").asText());
    }

    @Test
    void extractEntries_singleResourceRead() {
        JsonNode patient = json("{\"resourceType\":\"Patient\",\"id\":\"p1\"}");
        List<JsonNode> out = new ArrayList<>();
        EpicFhirClient.extractEntries(patient, out);
        assertEquals(1, out.size());
        assertEquals("p1", out.get(0).get("id").asText());
    }

    @Test
    void nextLink_followsNextRelation() {
        JsonNode bundle = json("{\"resourceType\":\"Bundle\",\"link\":["
                + "{\"relation\":\"self\",\"url\":\"https://x/self\"},"
                + "{\"relation\":\"next\",\"url\":\"https://x/next\"}]}");
        assertEquals("https://x/next", EpicFhirClient.nextLink(bundle));
    }

    @Test
    void nextLink_absentReturnsNull() {
        JsonNode bundle = json("{\"resourceType\":\"Bundle\",\"link\":["
                + "{\"relation\":\"self\",\"url\":\"https://x/self\"}]}");
        assertNull(EpicFhirClient.nextLink(bundle));
    }
}
