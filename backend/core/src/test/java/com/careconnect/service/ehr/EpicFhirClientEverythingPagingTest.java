package com.careconnect.service.ehr;

import com.careconnect.config.EpicProperties;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpMethod;
import org.springframework.http.ResponseEntity;
import org.springframework.web.client.RestTemplate;

import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Verifies {@link EpicFhirClient#everything(Long)} follows Bundle {@code next} paging and merges
 * every page's resources (it previously read only the first page).
 */
class EpicFhirClientEverythingPagingTest {

    private final ObjectMapper mapper = new ObjectMapper();

    private JsonNode json(String s) {
        try {
            return mapper.readTree(s);
        } catch (Exception e) {
            throw new RuntimeException(e);
        }
    }

    @Test
    void everything_followsNextLinkAndMergesAllPages() {
        RestTemplate http = mock(RestTemplate.class);
        EpicProperties cfg = mock(EpicProperties.class);
        EpicOAuthService oauth = mock(EpicOAuthService.class);
        EhrAuditService audit = mock(EhrAuditService.class);

        when(cfg.getFhirBaseUrl()).thenReturn("https://fhir/api/R4");
        when(oauth.validAccessToken(1L)).thenReturn("tok");
        when(oauth.patientFhirId(1L)).thenReturn("pat-1");

        String page1Url = "https://fhir/api/R4/Patient/pat-1/$everything";
        String page2Url = "https://fhir/page2";

        JsonNode page1 = json("{\"resourceType\":\"Bundle\","
                + "\"link\":[{\"relation\":\"next\",\"url\":\"" + page2Url + "\"}],"
                + "\"entry\":[{\"resource\":{\"resourceType\":\"Condition\",\"id\":\"c1\"}}]}");
        JsonNode page2 = json("{\"resourceType\":\"Bundle\",\"entry\":["
                + "{\"resource\":{\"resourceType\":\"Immunization\",\"id\":\"i1\"}}]}");

        when(http.exchange(eq(page1Url), eq(HttpMethod.GET), any(HttpEntity.class), eq(JsonNode.class)))
                .thenReturn(ResponseEntity.ok(page1));
        when(http.exchange(eq(page2Url), eq(HttpMethod.GET), any(HttpEntity.class), eq(JsonNode.class)))
                .thenReturn(ResponseEntity.ok(page2));

        EpicFhirClient client = new EpicFhirClient(http, cfg, oauth, audit);

        List<JsonNode> out = client.everything(1L);

        assertEquals(2, out.size(), "both pages' resources should be merged");
        assertEquals("c1", out.get(0).get("id").asText());
        assertEquals("i1", out.get(1).get("id").asText());
        verify(http, times(2)).exchange(any(String.class), eq(HttpMethod.GET),
                any(HttpEntity.class), eq(JsonNode.class));
    }
}
