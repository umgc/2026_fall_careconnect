package com.careconnect.controller;

import com.careconnect.dto.schedule.ScheduledVisitRequest;
import com.careconnect.dto.schedule.ScheduledVisitResponse;
import com.careconnect.dto.schedule.ScheduledVisitSummary;
import com.careconnect.repository.PatientRepository;
import com.careconnect.security.AuthorizationService;
import com.careconnect.service.schedule.ScheduledVisitService;
import com.careconnect.util.SecurityUtil;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.http.MediaType;
import org.springframework.security.test.context.support.WithMockUser;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.LocalTime;
import java.util.List;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.csrf;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@WebMvcTest(ScheduledVisitController.class)
@DisplayName("ScheduledVisitController Tests")
class ScheduledVisitControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

    @MockitoBean
    private ScheduledVisitService scheduledVisitService;

    @MockitoBean
    private SecurityUtil securityUtil;

    @MockitoBean
    private AuthorizationService authorizationService;

    @MockitoBean
    private PatientRepository patientRepository;

    private ScheduledVisitRequest validRequest;
    private ScheduledVisitResponse sampleVisit;
    private ScheduledVisitSummary sampleSummary;

    @BeforeEach
    void setUp() throws Exception {
        validRequest = new ScheduledVisitRequest(
                10L,
                "Bathing Assistance",
                LocalDate.of(2026, 3, 1),
                LocalTime.of(9, 0),
                60,
                "High",
                "Bring supplies"
        );

        sampleVisit = new ScheduledVisitResponse(
                101L,
                5L,
                10L,
                "Pat Ient",
                "Bathing Assistance",
                LocalDate.of(2026, 3, 1),
                LocalTime.of(9, 0),
                60,
                "High",
                "Bring supplies",
                "Scheduled",
                LocalDateTime.of(2026, 2, 20, 8, 0),
                LocalDateTime.of(2026, 2, 20, 8, 30)
        );

        sampleSummary = new ScheduledVisitSummary(1L, 2L, 3L, 6L);
    }

    @Nested
    @DisplayName("POST /caregiver/{caregiverId}")
    class CreateScheduledVisit {

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("Creates scheduled visit and returns 201")
        void createsScheduledVisit() throws Exception {
            // Arrange
            when(scheduledVisitService.createScheduledVisit(eq(5L), any(ScheduledVisitRequest.class)))
                    .thenReturn(sampleVisit);

            // Act + Assert
            mockMvc.perform(post("/v1/api/scheduled-visits/caregiver/5")
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(validRequest)))
                    .andExpect(status().isCreated())
                    .andExpect(jsonPath("$.id").value(101))
                    .andExpect(jsonPath("$.caregiverId").value(5))
                    .andExpect(jsonPath("$.patientId").value(10));

            // Assert
            verify(scheduledVisitService).createScheduledVisit(eq(5L), any(ScheduledVisitRequest.class));
        }

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("Returns 400 when request fails validation")
        void returns500WhenRequestInvalid() throws Exception {
            // Arrange
            final ScheduledVisitRequest invalidRequest = new ScheduledVisitRequest(
                    10L,
                    "Bathing Assistance",
                    LocalDate.of(2026, 3, 1),
                    LocalTime.of(9, 0),
                    10,
                    "High",
                    "Too short"
            );

            // Act + Assert
            mockMvc.perform(post("/v1/api/scheduled-visits/caregiver/5")
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(invalidRequest)))
                    .andExpect(status().isBadRequest());

            // Assert
            verifyNoInteractions(scheduledVisitService);
        }
    }

    @Nested
    @DisplayName("GET /caregiver/{caregiverId}")
    class GetScheduledVisits {

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("Returns all scheduled visits for caregiver")
        void returnsScheduledVisitsForCaregiver() throws Exception {
            // Arrange
            when(scheduledVisitService.getScheduledVisits(5L)).thenReturn(List.of(sampleVisit));

            // Act + Assert
            mockMvc.perform(get("/v1/api/scheduled-visits/caregiver/5"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$[0].id").value(101))
                    .andExpect(jsonPath("$[0].patientName").value("Pat Ient"));

            // Assert
            verify(scheduledVisitService).getScheduledVisits(5L);
        }
    }

    @Nested
    @DisplayName("GET /caregiver/{caregiverId}/date/{date}")
    class GetScheduledVisitsByDate {

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("Returns scheduled visits for specific date")
        void returnsVisitsByDate() throws Exception {
            // Arrange
            when(scheduledVisitService.getScheduledVisitsByDate(5L, LocalDate.of(2026, 3, 1)))
                    .thenReturn(List.of(sampleVisit));

            // Act + Assert
            mockMvc.perform(get("/v1/api/scheduled-visits/caregiver/5/date/2026-03-01"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$[0].scheduledDate").value("2026-03-01"));

            // Assert
            verify(scheduledVisitService).getScheduledVisitsByDate(5L, LocalDate.of(2026, 3, 1));
        }

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("Returns 400 when date format is invalid")
        void returns400WhenDateFormatInvalid() throws Exception {
            // Act + Assert
            // Invalid LocalDate path variable triggers MethodArgumentTypeMismatchException,
            // which GlobalExceptionHandler now maps to 400 (was 500 before the handler was added).
            mockMvc.perform(get("/v1/api/scheduled-visits/caregiver/5/date/03-01-2026"))
                    .andExpect(status().isBadRequest());
            // Assert
            verifyNoInteractions(scheduledVisitService);
        }
    }

    @Nested
    @DisplayName("GET /caregiver/{caregiverId}/range")
    class GetScheduledVisitsBetweenDates {

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("Returns scheduled visits between start and end dates")
        void returnsVisitsBetweenDates() throws Exception {
            // Arrange
            when(scheduledVisitService.getScheduledVisitsBetweenDates(
                    5L, LocalDate.of(2026, 3, 1), LocalDate.of(2026, 3, 3)))
                    .thenReturn(List.of(sampleVisit));

            // Act + Assert
            mockMvc.perform(get("/v1/api/scheduled-visits/caregiver/5/range")
                            .param("startDate", "2026-03-01")
                            .param("endDate", "2026-03-03"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$[0].id").value(101));

            // Assert
            verify(scheduledVisitService).getScheduledVisitsBetweenDates(
                    5L, LocalDate.of(2026, 3, 1), LocalDate.of(2026, 3, 3));
        }

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("Returns 500 when required range param is missing")
        void returns500WhenRangeParamMissing() throws Exception {
            // Act + Assert
            mockMvc.perform(get("/v1/api/scheduled-visits/caregiver/5/range")
                            .param("startDate", "2026-03-01"))
                    .andExpect(status().isInternalServerError());

            // Assert
            verifyNoInteractions(scheduledVisitService);
        }
    }

    @Nested
    @DisplayName("GET /caregiver/{caregiverId}/summary")
    class GetVisitSummary {

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("Returns visit summary counters")
        void returnsVisitSummary() throws Exception {
            // Arrange
            when(scheduledVisitService.getVisitSummary(5L)).thenReturn(sampleSummary);

            // Act + Assert
            mockMvc.perform(get("/v1/api/scheduled-visits/caregiver/5/summary"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.overdue").value(1))
                    .andExpect(jsonPath("$.ready").value(2))
                    .andExpect(jsonPath("$.upcoming").value(3))
                    .andExpect(jsonPath("$.totalToday").value(6));

            // Assert
            verify(scheduledVisitService).getVisitSummary(5L);
        }
    }

    @Nested
    @DisplayName("GET /caregiver/{caregiverId}/overdue")
    class GetOverdueVisits {

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("Returns overdue visits")
        void returnsOverdueVisits() throws Exception {
            // Arrange
            when(scheduledVisitService.getOverdueVisits(5L)).thenReturn(List.of(sampleVisit));

            // Act + Assert
            mockMvc.perform(get("/v1/api/scheduled-visits/caregiver/5/overdue"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$[0].id").value(101));

            // Assert
            verify(scheduledVisitService).getOverdueVisits(5L);
        }
    }

    @Nested
    @DisplayName("GET /caregiver/{caregiverId}/ready")
    class GetReadyVisits {

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("Returns ready visits")
        void returnsReadyVisits() throws Exception {
            // Arrange
            when(scheduledVisitService.getReadyVisits(5L)).thenReturn(List.of(sampleVisit));

            // Act + Assert
            mockMvc.perform(get("/v1/api/scheduled-visits/caregiver/5/ready"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$[0].id").value(101));

            // Assert
            verify(scheduledVisitService).getReadyVisits(5L);
        }
    }

    @Nested
    @DisplayName("GET /caregiver/{caregiverId}/upcoming")
    class GetUpcomingVisits {

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("Returns upcoming visits")
        void returnsUpcomingVisits() throws Exception {
            // Arrange
            when(scheduledVisitService.getUpcomingVisits(5L)).thenReturn(List.of(sampleVisit));

            // Act + Assert
            mockMvc.perform(get("/v1/api/scheduled-visits/caregiver/5/upcoming"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$[0].id").value(101));

            // Assert
            verify(scheduledVisitService).getUpcomingVisits(5L);
        }
    }

    @Nested
    @DisplayName("GET /{visitId}")
    class GetScheduledVisit {

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("Returns scheduled visit by id")
        void returnsScheduledVisitById() throws Exception {
            // Arrange
            when(scheduledVisitService.getScheduledVisit(101L)).thenReturn(sampleVisit);

            // Act + Assert
            mockMvc.perform(get("/v1/api/scheduled-visits/101"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.id").value(101))
                    .andExpect(jsonPath("$.patientName").value("Pat Ient"));

            // Assert
            verify(scheduledVisitService).getScheduledVisit(101L);
        }

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("Returns 500 when service throws runtime exception")
        void returns500WhenServiceThrowsRuntimeException() throws Exception {
            // Arrange
            when(scheduledVisitService.getScheduledVisit(999L)).thenThrow(new RuntimeException("Database down"));

            // Act + Assert
            mockMvc.perform(get("/v1/api/scheduled-visits/999"))
                    .andExpect(status().isInternalServerError())
                    .andExpect(jsonPath("$.error").value("An unexpected error occurred"));

            // Assert
            verify(scheduledVisitService).getScheduledVisit(999L);
        }
    }

    @Nested
    @DisplayName("PUT /{visitId}")
    class UpdateScheduledVisit {

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("Updates scheduled visit")
        void updatesScheduledVisit() throws Exception {
            // Arrange
            final ScheduledVisitResponse updatedVisit = new ScheduledVisitResponse(
                    101L,
                    5L,
                    10L,
                    "Pat Ient",
                    "Meal Preparation",
                    LocalDate.of(2026, 3, 2),
                    LocalTime.of(10, 30),
                    45,
                    "Medium",
                    "Updated notes",
                    "Scheduled",
                    LocalDateTime.of(2026, 2, 20, 8, 0),
                    LocalDateTime.of(2026, 2, 21, 9, 0)
            );
            when(scheduledVisitService.updateScheduledVisit(eq(101L), any(ScheduledVisitRequest.class)))
                    .thenReturn(updatedVisit);

            final ScheduledVisitRequest updateRequest = new ScheduledVisitRequest(
                    10L,
                    "Meal Preparation",
                    LocalDate.of(2026, 3, 2),
                    LocalTime.of(10, 30),
                    45,
                    "Medium",
                    "Updated notes"
            );

            // Act + Assert
            mockMvc.perform(put("/v1/api/scheduled-visits/101")
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(updateRequest)))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.serviceType").value("Meal Preparation"))
                    .andExpect(jsonPath("$.priority").value("Medium"));

            // Assert
            verify(scheduledVisitService).updateScheduledVisit(eq(101L), any(ScheduledVisitRequest.class));
        }

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("Returns 400 when update request fails validation")
        void returns500WhenUpdateRequestInvalid() throws Exception {
            // Arrange
            final ScheduledVisitRequest invalidUpdateRequest = new ScheduledVisitRequest(
                    10L,
                    "Meal Preparation",
                    LocalDate.of(2026, 3, 2),
                    LocalTime.of(10, 30),
                    10,
                    "Medium",
                    "Invalid duration"
            );

            // Act + Assert
            mockMvc.perform(put("/v1/api/scheduled-visits/101")
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(invalidUpdateRequest)))
                    .andExpect(status().isBadRequest());

            // Assert
            verifyNoInteractions(scheduledVisitService);
        }
    }

    @Nested
    @DisplayName("PUT /{visitId}/cancel")
    class CancelScheduledVisit {

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("Cancels scheduled visit and returns 204")
        void cancelsScheduledVisit() throws Exception {
            // Act + Assert
            mockMvc.perform(put("/v1/api/scheduled-visits/101/cancel").with(csrf()))
                    .andExpect(status().isNoContent());

            // Assert
            verify(scheduledVisitService).cancelScheduledVisit(101L);
        }

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("Returns 500 when cancel fails in service")
        void returns500WhenCancelFails() throws Exception {
            // Arrange
            doThrow(new RuntimeException("Cancel failed")).when(scheduledVisitService).cancelScheduledVisit(101L);

            // Act + Assert
            mockMvc.perform(put("/v1/api/scheduled-visits/101/cancel").with(csrf()))
                    .andExpect(status().isInternalServerError())
                    .andExpect(jsonPath("$.error").value("An unexpected error occurred"));

            // Assert
            verify(scheduledVisitService).cancelScheduledVisit(101L);
        }
    }

    @Nested
    @DisplayName("PUT /{visitId}/status")
    class UpdateVisitStatus {

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("Updates visit status")
        void updatesVisitStatus() throws Exception {
            // Arrange
            final ScheduledVisitResponse completedVisit = new ScheduledVisitResponse(
                    sampleVisit.getId(),
                    sampleVisit.getCaregiverId(),
                    sampleVisit.getPatientId(),
                    sampleVisit.getPatientName(),
                    sampleVisit.getServiceType(),
                    sampleVisit.getScheduledDate(),
                    sampleVisit.getScheduledTime(),
                    sampleVisit.getDurationMinutes(),
                    sampleVisit.getPriority(),
                    sampleVisit.getNotes(),
                    "Completed",
                    sampleVisit.getCreatedAt(),
                    sampleVisit.getUpdatedAt()
            );
            when(scheduledVisitService.updateVisitStatus(101L, "Completed")).thenReturn(completedVisit);

            // Act + Assert
            mockMvc.perform(put("/v1/api/scheduled-visits/101/status")
                            .with(csrf())
                            .param("status", "Completed"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.id").value(101))
                    .andExpect(jsonPath("$.status").value("Completed"));

            // Assert
            verify(scheduledVisitService).updateVisitStatus(101L, "Completed");
        }

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("Returns 500 when required status param is missing")
        void returns500WhenStatusMissing() throws Exception {
            // Act + Assert
            mockMvc.perform(put("/v1/api/scheduled-visits/101/status")
                            .with(csrf()))
                    .andExpect(status().isInternalServerError());

            // Assert
            verifyNoInteractions(scheduledVisitService);
        }
    }

    @Nested
    @DisplayName("DELETE /{visitId}")
    class DeleteScheduledVisit {

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("Deletes scheduled visit and returns 204")
        void deletesScheduledVisit() throws Exception {
            // Act + Assert
            mockMvc.perform(delete("/v1/api/scheduled-visits/101").with(csrf()))
                    .andExpect(status().isNoContent());

            // Assert
            verify(scheduledVisitService).deleteScheduledVisit(101L);
        }

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("Returns 500 when delete fails in service")
        void returns500WhenDeleteFails() throws Exception {
            // Arrange
            doThrow(new RuntimeException("Delete failed")).when(scheduledVisitService).deleteScheduledVisit(101L);

            // Act + Assert
            mockMvc.perform(delete("/v1/api/scheduled-visits/101").with(csrf()))
                    .andExpect(status().isInternalServerError())
                    .andExpect(jsonPath("$.error").value("An unexpected error occurred"));

            // Assert
            verify(scheduledVisitService).deleteScheduledVisit(101L);
        }
    }
}
