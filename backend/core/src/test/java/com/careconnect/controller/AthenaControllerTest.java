package com.careconnect.controller;

import com.careconnect.config.AthenaProperties;
import com.careconnect.dto.ehr.AthenaConnectionResponse;
import com.careconnect.model.User;
import com.careconnect.model.ehr.EhrResource;
import com.careconnect.repository.ehr.EhrResourceQueryRepository;
import com.careconnect.repository.ehr.EhrResourceRepository;
import com.careconnect.security.Role;
import com.careconnect.service.ehr.EhrSourceDataPurger;
import com.careconnect.service.ehr.athena.AthenaConnectionService;
import com.careconnect.service.ehr.athena.AthenaSyncInProgressException;
import com.careconnect.service.ehr.athena.AthenaSyncResult;
import com.careconnect.service.ehr.athena.AthenaSyncService;
import com.careconnect.util.SecurityUtil;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.SliceImpl;
import org.springframework.http.MediaType;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import java.time.Instant;
import java.util.List;
import java.util.Optional;

import static org.hamcrest.Matchers.hasSize;
import static org.hamcrest.Matchers.is;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * HTTP-layer tests for {@link AthenaController}: request validation, the error code each failure maps
 * to, and that reads are scoped to the caller's own user id. Services are mocked. The PATIENT role
 * check is {@code @PreAuthorize}, which this slice does not enforce; it is exercised against the
 * running application instead.
 */
@WebMvcTest(AthenaController.class)
@AutoConfigureMockMvc(addFilters = false)
@TestPropertySource(properties = "careconnect.athena.enabled=true")
class AthenaControllerTest {

    private static final long USER_ID = 7L;
    private static final String SOURCE = AthenaProperties.SOURCE_ATHENA;

    @Autowired
    private MockMvc mockMvc;

    @MockitoBean
    private SecurityUtil securityUtil;

    @MockitoBean
    private AthenaConnectionService connections;

    @MockitoBean
    private AthenaSyncService syncService;

    @MockitoBean
    private EhrResourceQueryRepository resourceQueries;

    @MockitoBean
    private EhrResourceRepository resources;

    @BeforeEach
    void setUp() {
        final User me = new User();
        me.setId(USER_ID);
        me.setRole(Role.PATIENT);
        when(securityUtil.resolveCurrentUser()).thenReturn(me);
        when(connections.isConnected(USER_ID)).thenReturn(true);
    }

    private static EhrResource row(final String type, final String id, final String occurredAt) {
        return EhrResource.builder().userId(USER_ID).source(SOURCE).resourceType(type).resourceFhirId(id)
                .title(type + ": x").statusValue("active").occurredAt(occurredAt)
                .payloadJson("{\"resourceType\":\"" + type + "\",\"id\":\"" + id + "\"}")
                .lastSyncedAt(Instant.parse("2026-10-03T12:00:00Z")).build();
    }

    @Test
    @DisplayName("GET /status returns the connection state")
    void statusIsReturned() throws Exception {
        when(connections.status(USER_ID)).thenReturn(AthenaConnectionResponse.notConnected("NOT_CONSENTED"));

        mockMvc.perform(get("/api/athena/status"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.connected", is(false)))
                .andExpect(jsonPath("$.status", is("NOT_CONNECTED")))
                .andExpect(jsonPath("$.reason", is("NOT_CONSENTED")))
                .andExpect(jsonPath("$.sync").doesNotExist());
    }

    @Test
    @DisplayName("an unauthenticated caller gets 401")
    void unauthenticatedIs401() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(null);
        mockMvc.perform(get("/api/athena/status")).andExpect(status().isUnauthorized());
    }

    @Test
    @DisplayName("POST /connect without explicit consent is refused and records nothing")
    void connectRequiresExplicitConsent() throws Exception {
        mockMvc.perform(post("/api/athena/connect"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code", is("CONSENT_REQUIRED")));
        mockMvc.perform(post("/api/athena/connect").contentType(MediaType.APPLICATION_JSON).content("{\"consent\":false}"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code", is("CONSENT_REQUIRED")));
        verify(connections, never()).connect(any());
    }

    @Test
    @DisplayName("a malformed body or a badly typed parameter is 400 INVALID_REQUEST, not a 500")
    void malformedInputIsACodedBadRequest() throws Exception {
        mockMvc.perform(post("/api/athena/connect").contentType(MediaType.APPLICATION_JSON).content("{\"consent\":"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code", is("INVALID_REQUEST")));
        mockMvc.perform(get("/api/athena/resources").param("from", "not-a-date"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code", is("INVALID_REQUEST")));
        mockMvc.perform(get("/api/athena/resources").param("page", "abc"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code", is("INVALID_REQUEST")));
        verify(connections, never()).connect(any());
    }

    @Test
    @DisplayName("POST /connect with consent returns the link outcome")
    void connectWithConsent() throws Exception {
        when(connections.connect(USER_ID)).thenReturn(AthenaConnectionResponse.notConnected("NOT_MATCHED"));

        mockMvc.perform(post("/api/athena/connect").contentType(MediaType.APPLICATION_JSON).content("{\"consent\":true}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.reason", is("NOT_MATCHED")));
    }

    @Test
    @DisplayName("POST /connect while a sync is running is 409 SYNC_IN_PROGRESS")
    void connectDuringSync() throws Exception {
        when(connections.connect(USER_ID)).thenThrow(new AthenaSyncInProgressException());

        mockMvc.perform(post("/api/athena/connect").contentType(MediaType.APPLICATION_JSON).content("{\"consent\":true}"))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.code", is("SYNC_IN_PROGRESS")));
    }

    @Test
    @DisplayName("POST /sync returns per-type outcomes")
    void syncReturnsOutcomes() throws Exception {
        when(syncService.sync(USER_ID)).thenReturn(new AthenaSyncResult(AthenaSyncResult.Status.COMPLETED,
                Instant.now(), List.of(
                        new AthenaSyncResult.TypeResult("Patient", AthenaSyncResult.Outcome.STORED, 1),
                        new AthenaSyncResult.TypeResult("Condition", AthenaSyncResult.Outcome.NOT_GRANTED, 0))));

        mockMvc.perform(post("/api/athena/sync"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status", is("COMPLETED")))
                .andExpect(jsonPath("$.types", hasSize(2)))
                .andExpect(jsonPath("$.types[1].outcome", is("NOT_GRANTED")));
    }

    @Test
    @DisplayName("POST /sync when not connected is 409 NOT_CONNECTED and athena is not called")
    void syncWhenNotConnected() throws Exception {
        when(connections.isConnected(USER_ID)).thenReturn(false);

        mockMvc.perform(post("/api/athena/sync"))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.code", is("NOT_CONNECTED")));
        verify(syncService, never()).sync(any());
    }

    @Test
    @DisplayName("POST /sync with no athena token is 503 SOURCE_UNAVAILABLE")
    void syncWhenSourceUnavailable() throws Exception {
        when(syncService.sync(USER_ID)).thenReturn(new AthenaSyncResult(
                AthenaSyncResult.Status.SOURCE_UNAVAILABLE, Instant.now(), List.of()));

        mockMvc.perform(post("/api/athena/sync"))
                .andExpect(status().isServiceUnavailable())
                .andExpect(jsonPath("$.code", is("SOURCE_UNAVAILABLE")));
    }

    @Test
    @DisplayName("POST /sync while another sync runs is 409 SYNC_IN_PROGRESS")
    void syncDuringSync() throws Exception {
        when(syncService.sync(USER_ID)).thenThrow(new AthenaSyncInProgressException());

        mockMvc.perform(post("/api/athena/sync"))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.code", is("SYNC_IN_PROGRESS")));
    }

    @Test
    @DisplayName("POST /disconnect confirms with the rows removed per table")
    void disconnectReturnsCounts() throws Exception {
        when(connections.disconnect(USER_ID)).thenReturn(new EhrSourceDataPurger.Purged(4, 4, 0, 0, 1));

        mockMvc.perform(post("/api/athena/disconnect"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.disconnected", is(true)))
                .andExpect(jsonPath("$.removed.mirroredResources", is(4)))
                .andExpect(jsonPath("$.removed.crosswalkLinks", is(1)));
    }

    @Test
    @DisplayName("GET /resources pages the caller's own rows, newest first, with an inclusive date range")
    void resourcesArePagedAndScoped() throws Exception {
        // Arrange
        when(resourceQueries.findPage(eq(USER_ID), eq(SOURCE), eq("2024-01-01"), eq("2025-01-01"), eq(PageRequest.of(1, 2))))
                .thenReturn(new SliceImpl<>(List.of(row("Condition", "c-1", "2024-06-01")), PageRequest.of(1, 2), true));

        // Act / Assert: the "to" day is included by bounding at the following day.
        mockMvc.perform(get("/api/athena/resources").param("page", "1").param("size", "2")
                        .param("from", "2024-01-01").param("to", "2024-12-31"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.items", hasSize(1)))
                .andExpect(jsonPath("$.items[0].resourceType", is("Condition")))
                .andExpect(jsonPath("$.items[0].category", is("Conditions")))
                .andExpect(jsonPath("$.items[0].source", is(SOURCE)))
                .andExpect(jsonPath("$.page", is(1)))
                .andExpect(jsonPath("$.size", is(2)))
                .andExpect(jsonPath("$.hasNext", is(true)));
    }

    @Test
    @DisplayName("GET /resources defaults to page 0, size 20 and no date bounds")
    void resourcesDefaults() throws Exception {
        when(resourceQueries.findPage(eq(USER_ID), eq(SOURCE), isNull(), isNull(), eq(PageRequest.of(0, 20))))
                .thenReturn(new SliceImpl<>(List.of(), PageRequest.of(0, 20), false));

        mockMvc.perform(get("/api/athena/resources"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.items", hasSize(0)))
                .andExpect(jsonPath("$.hasNext", is(false)));
    }

    @Test
    @DisplayName("out-of-range paging and reversed or extreme dates are 400 with a code")
    void resourcesValidation() throws Exception {
        mockMvc.perform(get("/api/athena/resources").param("size", "0"))
                .andExpect(status().isBadRequest()).andExpect(jsonPath("$.code", is("INVALID_PAGE")));
        mockMvc.perform(get("/api/athena/resources").param("size", "101"))
                .andExpect(status().isBadRequest()).andExpect(jsonPath("$.code", is("INVALID_PAGE")));
        mockMvc.perform(get("/api/athena/resources").param("page", "-1"))
                .andExpect(status().isBadRequest()).andExpect(jsonPath("$.code", is("INVALID_PAGE")));
        mockMvc.perform(get("/api/athena/resources").param("from", "2024-02-01").param("to", "2024-01-01"))
                .andExpect(status().isBadRequest()).andExpect(jsonPath("$.code", is("INVALID_DATE_RANGE")));
        mockMvc.perform(get("/api/athena/resources").param("to", "+999999999-12-31"))
                .andExpect(status().isBadRequest()).andExpect(jsonPath("$.code", is("INVALID_DATE_RANGE")));
        verify(resourceQueries, never()).findPage(any(), any(), any(), any(), any());
    }

    @Test
    @DisplayName("GET /resources when not connected is 409 and reads nothing")
    void resourcesWhenNotConnected() throws Exception {
        when(connections.isConnected(USER_ID)).thenReturn(false);

        mockMvc.perform(get("/api/athena/resources"))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.code", is("NOT_CONNECTED")));
        verify(resourceQueries, never()).findPage(any(), any(), any(), any(), any());
    }

    @Test
    @DisplayName("GET /resources/{type}/{id} returns the caller's own record with its FHIR resource")
    void detailIsScopedToTheCaller() throws Exception {
        when(resources.findByUserIdAndSourceAndResourceTypeAndResourceFhirId(USER_ID, SOURCE, "Condition", "c-1"))
                .thenReturn(Optional.of(row("Condition", "c-1", "2024-06-01")));

        mockMvc.perform(get("/api/athena/resources/Condition/c-1"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.resourceId", is("c-1")))
                .andExpect(jsonPath("$.resource.id", is("c-1")));
        verify(resources).findByUserIdAndSourceAndResourceTypeAndResourceFhirId(USER_ID, SOURCE, "Condition", "c-1");
    }

    @Test
    @DisplayName("a record the caller does not own is 404, indistinguishable from one that does not exist")
    void detailOfAnotherUsersRecordIs404() throws Exception {
        when(resources.findByUserIdAndSourceAndResourceTypeAndResourceFhirId(USER_ID, SOURCE, "Condition", "c-9"))
                .thenReturn(Optional.empty());

        mockMvc.perform(get("/api/athena/resources/Condition/c-9"))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.code", is("NOT_FOUND")));
    }
}
