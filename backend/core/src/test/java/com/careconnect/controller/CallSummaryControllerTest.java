package com.careconnect.controller;

import com.careconnect.config.CareconnectTestConfig;
import com.careconnect.service.CallSummaryService;
import java.time.LocalDateTime;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Optional;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.autoconfigure.security.oauth2.client.servlet.OAuth2ClientAutoConfiguration;
import org.springframework.boot.autoconfigure.security.oauth2.resource.servlet.OAuth2ResourceServerAutoConfiguration;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.context.annotation.Import;
import org.springframework.security.test.context.support.WithMockUser;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * Slice tests for {@link CallSummaryController} (WBS 3.11.6).
 *
 * <p>Covers the {@code GET /api/v3/summaries/{id}} contract:
 * 200 with body on found, 404 on not-found, 400 on a non-numeric id.
 */
@WebMvcTest(
        controllers = CallSummaryController.class,
        excludeAutoConfiguration = {
                OAuth2ClientAutoConfiguration.class,
                OAuth2ResourceServerAutoConfiguration.class
        }
)
@Import(CareconnectTestConfig.class)
@ActiveProfiles("test")
@DisplayName("CallSummaryController Tests")
class CallSummaryControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @MockitoBean
    private CallSummaryService callSummaryService;

    private static final long SUMMARY_ID = 101L;

    private Map<String, Object> exampleResponse() {
        Map<String, Object> response = new LinkedHashMap<>();
        response.put("callId", "call-1");
        response.put("status", "SUCCESS");
        response.put("generatedAt", LocalDateTime.of(2026, 7, 11, 12, 0));
        response.put("transcriptSegmentCount", 3);
        response.put("transcriptArchived", true);
        Map<String, Object> summary = new LinkedHashMap<>();
        summary.put("headline", "Stable call");
        summary.put("overallAssessment", "Patient remained stable.");
        response.put("summary", summary);
        return response;
    }

    @Test
    @WithMockUser
    @DisplayName("returns 200 with the response body when the summary is found")
    void getSummaryById_found_returns200WithBody() throws Exception {
        when(callSummaryService.getSummaryById(SUMMARY_ID))
                .thenReturn(Optional.of(exampleResponse()));

        mockMvc.perform(get("/api/v3/summaries/{id}", SUMMARY_ID))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.callId").value("call-1"))
                .andExpect(jsonPath("$.status").value("SUCCESS"))
                .andExpect(jsonPath("$.transcriptArchived").value(true))
                .andExpect(jsonPath("$.summary.headline").value("Stable call"));
    }

    @Test
    @WithMockUser
    @DisplayName("returns 404 when the summary does not exist")
    void getSummaryById_notFound_returns404() throws Exception {
        when(callSummaryService.getSummaryById(999L))
                .thenReturn(Optional.empty());

        mockMvc.perform(get("/api/v3/summaries/{id}", 999L))
                .andExpect(status().isNotFound());
    }

    @Test
    @WithMockUser
    @DisplayName("returns 400 when the id path variable is not a valid Long")
    void getSummaryById_nonNumericId_returns400() throws Exception {
        mockMvc.perform(get("/api/v3/summaries/{id}", "not-a-number"))
                .andExpect(status().isBadRequest());
    }
}