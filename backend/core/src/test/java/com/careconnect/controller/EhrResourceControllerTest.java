package com.careconnect.controller;

import com.careconnect.model.User;
import com.careconnect.model.ehr.EhrResource;
import com.careconnect.repository.ehr.EhrResourceRepository;
import com.careconnect.security.Role;
import com.careconnect.util.SecurityUtil;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import java.time.Instant;
import java.util.List;

import static org.hamcrest.Matchers.hasSize;
import static org.hamcrest.Matchers.is;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * HTTP-layer tests for {@link EhrResourceController} — the Unified Health Data read surface.
 * Verifies user scoping, Patient exclusion, category mapping/filter, free-text search, sort,
 * source-casing normalization, the demographics endpoint, and auth handling.
 */
@WebMvcTest(EhrResourceController.class)
@AutoConfigureMockMvc(addFilters = false)
class EhrResourceControllerTest {

    private static final String EPIC = "EPIC";

    @Autowired
    private MockMvc mockMvc;

    @MockitoBean
    private SecurityUtil securityUtil;

    @MockitoBean
    private EhrResourceRepository resourceRepo;

    private User user;

    @BeforeEach
    void setup() {
        user = new User();
        user.setId(1L);
        user.setEmail("patient@test.com");
        user.setRole(Role.PATIENT);
        when(securityUtil.resolveCurrentUser()).thenReturn(user);
        when(resourceRepo.findMaxLastSyncedAt(any(), any())).thenReturn(null);
    }

    private static EhrResource row(String type, String fhirId, String title, String status,
                                   String occurredAt, Instant syncedAt) {
        return EhrResource.builder()
                .userId(1L).source(EPIC)
                .resourceType(type).resourceFhirId(fhirId)
                .title(title).statusValue(status).occurredAt(occurredAt)
                .lastSyncedAt(syncedAt)
                .build();
    }

    @Test
    @DisplayName("GET /resources returns scoped items, excludes Patient, maps categories")
    void listExcludesPatientAndMapsCategory() throws Exception {
        when(resourceRepo.findByUserIdAndSource(1L, EPIC)).thenReturn(List.of(
                row("Patient", "p1", "Mary Johnson", null, null, null),
                row("Condition", "c1", "Hypertension", "active", "2024-01-01", null),
                row("MedicationRequest", "m1", "Lisinopril", "active", "2024-02-01", null)));

        mockMvc.perform(get("/api/ehr/resources").param("source", "EPIC"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(2)))
                .andExpect(jsonPath("$[?(@.resourceType=='Patient')]", hasSize(0)))
                .andExpect(jsonPath("$[?(@.resourceType=='Condition')].category", is(List.of("Conditions"))))
                .andExpect(jsonPath("$[?(@.resourceType=='MedicationRequest')].category",
                        is(List.of("Medications"))));
    }

    @Test
    @DisplayName("GET /resources filters by UI category")
    void listFiltersByCategory() throws Exception {
        when(resourceRepo.findByUserIdAndSource(1L, EPIC)).thenReturn(List.of(
                row("Condition", "c1", "Hypertension", "active", "2024-01-01", null),
                row("Observation", "o1", "BP 120/80", "final", "2024-03-01", null)));

        mockMvc.perform(get("/api/ehr/resources").param("category", "Results"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(1)))
                .andExpect(jsonPath("$[0].resourceType", is("Observation")))
                .andExpect(jsonPath("$[0].category", is("Results")));
    }

    @Test
    @DisplayName("GET /resources free-text q matches title or resourceType")
    void listSearchesByQ() throws Exception {
        when(resourceRepo.findByUserIdAndSource(1L, EPIC)).thenReturn(List.of(
                row("Condition", "c1", "Hypertension", "active", "2024-01-01", null),
                row("MedicationRequest", "m1", "Lisinopril", "active", "2024-02-01", null)));

        mockMvc.perform(get("/api/ehr/resources").param("q", "lisin"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(1)))
                .andExpect(jsonPath("$[0].title", is("Lisinopril")));
    }

    @Test
    @DisplayName("GET /resources sort=az orders by title ascending")
    void listSortsAz() throws Exception {
        when(resourceRepo.findByUserIdAndSource(1L, EPIC)).thenReturn(List.of(
                row("Condition", "c1", "Zoster", "active", "2024-01-01", null),
                row("Condition", "c2", "Asthma", "active", "2024-02-01", null)));

        mockMvc.perform(get("/api/ehr/resources").param("sort", "az"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].title", is("Asthma")))
                .andExpect(jsonPath("$[1].title", is("Zoster")));
    }

    @Test
    @DisplayName("GET /resources normalizes ?source casing to the stored value, and sets X-Last-Synced-At")
    void listNormalizesSourceAndSetsHeader() throws Exception {
        when(resourceRepo.findByUserIdAndSource(1L, EPIC)).thenReturn(List.of(
                row("Condition", "c1", "Hypertension", "active", "2024-01-01", null)));
        when(resourceRepo.findMaxLastSyncedAt(1L, EPIC)).thenReturn(Instant.parse("2024-05-01T00:00:00Z"));

        mockMvc.perform(get("/api/ehr/resources").param("source", "epic"))
                .andExpect(status().isOk())
                .andExpect(header().string("X-Last-Synced-At", "2024-05-01T00:00:00Z"))
                .andExpect(jsonPath("$", hasSize(1)));

        verify(resourceRepo).findByUserIdAndSource(eq(1L), eq(EPIC));
    }

    @Test
    @DisplayName("GET /resources returns 401 when unauthenticated")
    void listUnauthenticated() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(null);
        mockMvc.perform(get("/api/ehr/resources")).andExpect(status().isUnauthorized());
    }

    @Test
    @DisplayName("GET /patient parses name/birthDate/gender from the mirrored Patient payload")
    void patientReturnsDemographics() throws Exception {
        String fhir = "{\"resourceType\":\"Patient\",\"name\":[{\"given\":[\"Mary\"],\"family\":\"Johnson\"}],"
                + "\"birthDate\":\"1948-03-11\",\"gender\":\"female\"}";
        EhrResource patientRow = EhrResource.builder()
                .userId(1L).source(EPIC).resourceType("Patient").resourceFhirId("p1")
                .payloadJson(fhir).build();
        when(resourceRepo.findByUserIdAndSource(1L, EPIC)).thenReturn(List.of(patientRow));

        mockMvc.perform(get("/api/ehr/patient"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.name", is("Mary Johnson")))
                .andExpect(jsonPath("$.birthDate", is("1948-03-11")))
                .andExpect(jsonPath("$.gender", is("female")));
    }

    @Test
    @DisplayName("GET /patient returns 404 when no Patient row exists")
    void patientNotFound() throws Exception {
        when(resourceRepo.findByUserIdAndSource(1L, EPIC)).thenReturn(List.of(
                row("Condition", "c1", "Hypertension", "active", "2024-01-01", null)));
        mockMvc.perform(get("/api/ehr/patient")).andExpect(status().isNotFound());
    }
}
