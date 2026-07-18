package com.careconnect.service.schedule;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.LocalTime;
import java.util.Collections;
import java.util.List;
import java.util.Optional;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.MockitoAnnotations;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;

import com.careconnect.dto.schedule.AuditDiffResponse;
import com.careconnect.dto.schedule.ScheduledVisitAuditResponse;
import com.careconnect.dto.schedule.ScheduledVisitRequest;
import com.careconnect.dto.schedule.ScheduledVisitResponse;
import com.careconnect.dto.schedule.ScheduledVisitSummary;
import com.careconnect.model.Patient;
import com.careconnect.model.schedule.ScheduledVisit;
import com.careconnect.model.schedule.ScheduledVisitAudit;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.schedule.ScheduledVisitAuditRepository;
import com.careconnect.repository.schedule.ScheduledVisitRepository;
import com.careconnect.service.schedule.ScheduleConflictService.ConflictSummary;
import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * Unit tests for {@link ScheduledVisitService}.
 *
 * <p>All repository and service dependencies are mocked with Mockito so the
 * service's business logic is validated in isolation.</p>
 */
class ScheduledVisitServiceTest {

    @Mock
    private ScheduledVisitRepository scheduledVisitRepository;

    @Mock
    private ScheduledVisitAuditRepository scheduledVisitAuditRepository;

    @Mock
    private PatientRepository patientRepository;

    @Mock
    private ScheduleConflictService conflictService;

    @Mock
    private ObjectMapper objectMapper;

    @InjectMocks
    private ScheduledVisitService visitService;

    private static final Long CAREGIVER_ID = 1L;
    private static final Long PATIENT_ID = 10L;
    private static final Long VISIT_ID = 100L;
    private static final LocalDate TEST_DATE = LocalDate.of(2026, 3, 17);
    private static final LocalTime TEST_TIME = LocalTime.of(10, 0);
    private static final String TEST_USER = "testuser";

    @BeforeEach
    void setUp() {
        MockitoAnnotations.openMocks(this);
        SecurityContextHolder.getContext().setAuthentication(
                new UsernamePasswordAuthenticationToken(TEST_USER, null));
    }

    @AfterEach
    void tearDown() {
        SecurityContextHolder.clearContext();
    }

    // ========================================================================
    // Helper methods
    // ========================================================================

    private ScheduledVisit createVisit() {
        ScheduledVisit visit = new ScheduledVisit();
        visit.setId(VISIT_ID);
        visit.setCaregiverId(CAREGIVER_ID);
        visit.setPatientId(PATIENT_ID);
        visit.setServiceType("General Care");
        visit.setScheduledDate(TEST_DATE);
        visit.setScheduledTime(TEST_TIME);
        visit.setDurationMinutes(60);
        visit.setPriority("Normal");
        visit.setNotes("Test notes");
        visit.setStatus("Scheduled");
        return visit;
    }

    private ScheduledVisitRequest createRequest() {
        ScheduledVisitRequest request = new ScheduledVisitRequest();
        request.setPatientId(PATIENT_ID);
        request.setServiceType("General Care");
        request.setScheduledDate(TEST_DATE);
        request.setScheduledTime(TEST_TIME);
        request.setDurationMinutes(60);
        request.setPriority("Normal");
        request.setNotes("Test notes");
        return request;
    }

    private ConflictSummary createEmptyConflictSummary() {
        return new ConflictSummary();
    }

    private Patient createPatient() {
        return Patient.builder()
                .id(PATIENT_ID)
                .firstName("John")
                .lastName("Doe")
                .build();
    }

    private void mockPatientLookup() {
        when(patientRepository.findById(PATIENT_ID)).thenReturn(Optional.of(createPatient()));
    }

    private void stubNoConflicts() {
        when(conflictService.analyzeConflicts(
                anyLong(), anyLong(), any(LocalDate.class), any(LocalTime.class), anyInt()))
                .thenReturn(createEmptyConflictSummary());
    }

    // ========================================================================
    // createScheduledVisit
    // ========================================================================

    @Nested
    @DisplayName("createScheduledVisit")
    class CreateScheduledVisit {

        @Test
        @DisplayName("should create visit successfully with no conflicts")
        void shouldCreateVisitSuccessfully() throws Exception {
            ScheduledVisitRequest request = createRequest();
            ConflictSummary noConflicts = createEmptyConflictSummary();
            ScheduledVisit savedVisit = createVisit();

            when(conflictService.analyzeConflicts(
                    CAREGIVER_ID, PATIENT_ID, TEST_DATE, TEST_TIME, 60))
                    .thenReturn(noConflicts);
            when(scheduledVisitRepository.save(any(ScheduledVisit.class))).thenReturn(savedVisit);
            when(objectMapper.writeValueAsString(any())).thenReturn("{}");
            mockPatientLookup();

            ScheduledVisitResponse response =
                    visitService.createScheduledVisit(CAREGIVER_ID, request);

            assertNotNull(response);
            assertEquals(VISIT_ID, response.getId());
            assertEquals(CAREGIVER_ID, response.getCaregiverId());
            assertEquals(PATIENT_ID, response.getPatientId());
            assertEquals("John Doe", response.getPatientName());
            assertEquals("Scheduled", response.getStatus());
            verify(scheduledVisitRepository).save(any(ScheduledVisit.class));
            verify(scheduledVisitAuditRepository).save(any(ScheduledVisitAudit.class));
        }

        @Test
        @DisplayName("should throw exception when patient has overlapping visit")
        void shouldThrowWhenPatientConflicts() {
            ScheduledVisitRequest request = createRequest();
            ConflictSummary conflictSummary = createEmptyConflictSummary();
            ScheduledVisit conflicting = createVisit();
            conflictSummary.setPatientConflicts(List.of(conflicting));

            when(conflictService.analyzeConflicts(
                    CAREGIVER_ID, PATIENT_ID, TEST_DATE, TEST_TIME, 60))
                    .thenReturn(conflictSummary);

            IllegalArgumentException ex = assertThrows(IllegalArgumentException.class,
                    () -> visitService.createScheduledVisit(CAREGIVER_ID, request));

            assertTrue(ex.getMessage().contains("Patient already has a scheduled visit"));
            verify(scheduledVisitRepository, never()).save(any());
        }

        @Test
        @DisplayName("should create visit with caregiver conflict warning but no block")
        void shouldCreateVisitWithCaregiverConflictWarning() throws Exception {
            ScheduledVisitRequest request = createRequest();
            ConflictSummary conflictSummary = createEmptyConflictSummary();
            ScheduledVisit conflicting = createVisit();
            conflictSummary.setCaregiverConflicts(List.of(conflicting));
            conflictSummary.addWarning("Caregiver has 1 overlapping visit(s) at this time");

            ScheduledVisit savedVisit = createVisit();
            savedVisit.setConflictFlag(true);
            savedVisit.setConflictWarning(
                    "Caregiver has 1 overlapping visit(s) at this time");

            when(conflictService.analyzeConflicts(
                    CAREGIVER_ID, PATIENT_ID, TEST_DATE, TEST_TIME, 60))
                    .thenReturn(conflictSummary);
            when(scheduledVisitRepository.save(any(ScheduledVisit.class))).thenReturn(savedVisit);
            when(objectMapper.writeValueAsString(any())).thenReturn("{}");
            mockPatientLookup();

            ScheduledVisitResponse response =
                    visitService.createScheduledVisit(CAREGIVER_ID, request);

            assertNotNull(response);
            verify(scheduledVisitRepository).save(any(ScheduledVisit.class));
        }

        @Test
        @DisplayName("should create visit with daily limit warning but no block")
        void shouldCreateVisitWithDailyLimitWarning() throws Exception {
            ScheduledVisitRequest request = createRequest();
            ConflictSummary conflictSummary = createEmptyConflictSummary();
            conflictSummary.setExceedsDailyLimit(true);
            conflictSummary.addWarning(
                    "Caregiver already has max visits (8) scheduled for this day");

            ScheduledVisit savedVisit = createVisit();
            savedVisit.setConflictFlag(true);

            when(conflictService.analyzeConflicts(
                    CAREGIVER_ID, PATIENT_ID, TEST_DATE, TEST_TIME, 60))
                    .thenReturn(conflictSummary);
            when(scheduledVisitRepository.save(any(ScheduledVisit.class))).thenReturn(savedVisit);
            when(objectMapper.writeValueAsString(any())).thenReturn("{}");
            mockPatientLookup();

            ScheduledVisitResponse response =
                    visitService.createScheduledVisit(CAREGIVER_ID, request);

            assertNotNull(response);
            verify(scheduledVisitRepository).save(any(ScheduledVisit.class));
        }

        @Test
        @DisplayName("should create visit with daily hours exceeded warning but no block")
        void shouldCreateVisitWithDailyHoursWarning() throws Exception {
            ScheduledVisitRequest request = createRequest();
            ConflictSummary conflictSummary = createEmptyConflictSummary();
            conflictSummary.setExceedsDailyHours(true);
            conflictSummary.addWarning(
                    "Adding this visit would exceed 10 working hours for the day");

            ScheduledVisit savedVisit = createVisit();
            savedVisit.setConflictFlag(true);

            when(conflictService.analyzeConflicts(
                    CAREGIVER_ID, PATIENT_ID, TEST_DATE, TEST_TIME, 60))
                    .thenReturn(conflictSummary);
            when(scheduledVisitRepository.save(any(ScheduledVisit.class))).thenReturn(savedVisit);
            when(objectMapper.writeValueAsString(any())).thenReturn("{}");
            mockPatientLookup();

            ScheduledVisitResponse response =
                    visitService.createScheduledVisit(CAREGIVER_ID, request);

            assertNotNull(response);
            verify(scheduledVisitRepository).save(any(ScheduledVisit.class));
        }

        @Test
        @DisplayName("should return Unknown patient name when patient not in repository")
        void shouldReturnUnknownPatientNameWhenNotFound() throws Exception {
            ScheduledVisitRequest request = createRequest();
            ScheduledVisit savedVisit = createVisit();

            stubNoConflicts();
            when(scheduledVisitRepository.save(any(ScheduledVisit.class))).thenReturn(savedVisit);
            when(objectMapper.writeValueAsString(any())).thenReturn("{}");
            when(patientRepository.findById(PATIENT_ID)).thenReturn(Optional.empty());

            ScheduledVisitResponse response =
                    visitService.createScheduledVisit(CAREGIVER_ID, request);

            assertEquals("Unknown", response.getPatientName());
        }

        @Test
        @DisplayName("should create visit when conflict summary has null patient/caregiver conflict lists")
        void shouldCreateVisitWhenConflictListsAreNull() throws Exception {
            // Arrange: simulate a ConflictSummary whose conflict lists were never
            // populated (null), exercising the null-check branches guarding both
            // the patient-conflict block and the caregiver-conflict warning flag.
            ScheduledVisitRequest request = createRequest();
            ConflictSummary conflictSummary = new ConflictSummary();
            conflictSummary.setPatientConflicts(null);
            conflictSummary.setCaregiverConflicts(null);
            ScheduledVisit savedVisit = createVisit();

            when(conflictService.analyzeConflicts(
                    CAREGIVER_ID, PATIENT_ID, TEST_DATE, TEST_TIME, 60))
                    .thenReturn(conflictSummary);
            when(scheduledVisitRepository.save(any(ScheduledVisit.class))).thenReturn(savedVisit);
            when(objectMapper.writeValueAsString(any())).thenReturn("{}");
            mockPatientLookup();

            ScheduledVisitResponse response =
                    visitService.createScheduledVisit(CAREGIVER_ID, request);

            assertNotNull(response);
            verify(scheduledVisitRepository).save(any(ScheduledVisit.class));
        }
    }

    // ========================================================================
    // getScheduledVisits
    // ========================================================================

    @Nested
    @DisplayName("getScheduledVisits")
    class GetScheduledVisits {

        @Test
        @DisplayName("should return all visits for caregiver")
        void shouldReturnAllVisits() {
            ScheduledVisit visit = createVisit();
            when(scheduledVisitRepository.findByCaregiverId(CAREGIVER_ID))
                    .thenReturn(List.of(visit));
            mockPatientLookup();

            List<ScheduledVisitResponse> results =
                    visitService.getScheduledVisits(CAREGIVER_ID);

            assertEquals(1, results.size());
            assertEquals(VISIT_ID, results.get(0).getId());
            assertEquals("John Doe", results.get(0).getPatientName());
        }

        @Test
        @DisplayName("should return empty list when no visits exist")
        void shouldReturnEmptyList() {
            when(scheduledVisitRepository.findByCaregiverId(CAREGIVER_ID))
                    .thenReturn(Collections.emptyList());

            List<ScheduledVisitResponse> results =
                    visitService.getScheduledVisits(CAREGIVER_ID);

            assertTrue(results.isEmpty());
        }

        @Test
        @DisplayName("should return multiple visits")
        void shouldReturnMultipleVisits() {
            ScheduledVisit visit1 = createVisit();
            ScheduledVisit visit2 = createVisit();
            visit2.setId(101L);
            when(scheduledVisitRepository.findByCaregiverId(CAREGIVER_ID))
                    .thenReturn(List.of(visit1, visit2));
            mockPatientLookup();

            List<ScheduledVisitResponse> results =
                    visitService.getScheduledVisits(CAREGIVER_ID);

            assertEquals(2, results.size());
        }
    }

    // ========================================================================
    // getScheduledVisitsByDate
    // ========================================================================

    @Nested
    @DisplayName("getScheduledVisitsByDate")
    class GetScheduledVisitsByDate {

        @Test
        @DisplayName("should return visits for specific date")
        void shouldReturnVisitsForDate() {
            ScheduledVisit visit = createVisit();
            when(scheduledVisitRepository
                    .findByCaregiverIdAndScheduledDate(CAREGIVER_ID, TEST_DATE))
                    .thenReturn(List.of(visit));
            mockPatientLookup();

            List<ScheduledVisitResponse> results =
                    visitService.getScheduledVisitsByDate(CAREGIVER_ID, TEST_DATE);

            assertEquals(1, results.size());
            assertEquals(TEST_DATE, results.get(0).getScheduledDate());
        }

        @Test
        @DisplayName("should return empty list when no visits on date")
        void shouldReturnEmptyListForDate() {
            when(scheduledVisitRepository
                    .findByCaregiverIdAndScheduledDate(CAREGIVER_ID, TEST_DATE))
                    .thenReturn(Collections.emptyList());

            List<ScheduledVisitResponse> results =
                    visitService.getScheduledVisitsByDate(CAREGIVER_ID, TEST_DATE);

            assertTrue(results.isEmpty());
        }
    }

    // ========================================================================
    // getScheduledVisitsBetweenDates
    // ========================================================================

    @Nested
    @DisplayName("getScheduledVisitsBetweenDates")
    class GetScheduledVisitsBetweenDates {

        @Test
        @DisplayName("should return visits between date range")
        void shouldReturnVisitsBetweenDates() {
            LocalDate endDate = TEST_DATE.plusDays(7);
            ScheduledVisit visit = createVisit();
            when(scheduledVisitRepository
                    .findByCaregiverIdAndScheduledDateBetween(CAREGIVER_ID, TEST_DATE, endDate))
                    .thenReturn(List.of(visit));
            mockPatientLookup();

            List<ScheduledVisitResponse> results =
                    visitService.getScheduledVisitsBetweenDates(
                            CAREGIVER_ID, TEST_DATE, endDate);

            assertEquals(1, results.size());
        }

        @Test
        @DisplayName("should return empty list when no visits in range")
        void shouldReturnEmptyListForRange() {
            LocalDate endDate = TEST_DATE.plusDays(7);
            when(scheduledVisitRepository
                    .findByCaregiverIdAndScheduledDateBetween(CAREGIVER_ID, TEST_DATE, endDate))
                    .thenReturn(Collections.emptyList());

            List<ScheduledVisitResponse> results =
                    visitService.getScheduledVisitsBetweenDates(
                            CAREGIVER_ID, TEST_DATE, endDate);

            assertTrue(results.isEmpty());
        }
    }

    // ========================================================================
    // getVisitSummary
    // ========================================================================

    @Nested
    @DisplayName("getVisitSummary")
    class GetVisitSummary {

        @Test
        @DisplayName("should return correct summary counts")
        void shouldReturnCorrectSummaryCounts() {
            when(scheduledVisitRepository
                    .countOverdueVisits(eq(CAREGIVER_ID), any(), any()))
                    .thenReturn(2L);
            when(scheduledVisitRepository
                    .countReadyVisits(eq(CAREGIVER_ID), any(), any()))
                    .thenReturn(1L);
            when(scheduledVisitRepository
                    .countUpcomingVisits(eq(CAREGIVER_ID), any(), any()))
                    .thenReturn(3L);
            when(scheduledVisitRepository
                    .countTodayVisits(eq(CAREGIVER_ID), any()))
                    .thenReturn(6L);

            ScheduledVisitSummary summary = visitService.getVisitSummary(CAREGIVER_ID);

            assertNotNull(summary);
            assertEquals(2L, summary.getOverdue());
            assertEquals(1L, summary.getReady());
            assertEquals(3L, summary.getUpcoming());
            assertEquals(6L, summary.getTotalToday());
        }

        @Test
        @DisplayName("should return zero counts when no visits")
        void shouldReturnZeroCounts() {
            when(scheduledVisitRepository
                    .countOverdueVisits(eq(CAREGIVER_ID), any(), any()))
                    .thenReturn(0L);
            when(scheduledVisitRepository
                    .countReadyVisits(eq(CAREGIVER_ID), any(), any()))
                    .thenReturn(0L);
            when(scheduledVisitRepository
                    .countUpcomingVisits(eq(CAREGIVER_ID), any(), any()))
                    .thenReturn(0L);
            when(scheduledVisitRepository
                    .countTodayVisits(eq(CAREGIVER_ID), any()))
                    .thenReturn(0L);

            ScheduledVisitSummary summary = visitService.getVisitSummary(CAREGIVER_ID);

            assertEquals(0L, summary.getOverdue());
            assertEquals(0L, summary.getReady());
            assertEquals(0L, summary.getUpcoming());
            assertEquals(0L, summary.getTotalToday());
        }
    }

    // ========================================================================
    // getOverdueVisits
    // ========================================================================

    @Nested
    @DisplayName("getOverdueVisits")
    class GetOverdueVisits {

        @Test
        @DisplayName("should return overdue visits")
        void shouldReturnOverdueVisits() {
            ScheduledVisit visit = createVisit();
            when(scheduledVisitRepository
                    .findOverdueVisits(eq(CAREGIVER_ID), any(), any()))
                    .thenReturn(List.of(visit));
            mockPatientLookup();

            List<ScheduledVisitResponse> results =
                    visitService.getOverdueVisits(CAREGIVER_ID);

            assertEquals(1, results.size());
        }

        @Test
        @DisplayName("should return empty list when no overdue visits")
        void shouldReturnEmptyWhenNoOverdue() {
            when(scheduledVisitRepository
                    .findOverdueVisits(eq(CAREGIVER_ID), any(), any()))
                    .thenReturn(Collections.emptyList());

            List<ScheduledVisitResponse> results =
                    visitService.getOverdueVisits(CAREGIVER_ID);

            assertTrue(results.isEmpty());
        }
    }

    // ========================================================================
    // getReadyVisits
    // ========================================================================

    @Nested
    @DisplayName("getReadyVisits")
    class GetReadyVisits {

        @Test
        @DisplayName("should return ready visits")
        void shouldReturnReadyVisits() {
            ScheduledVisit visit = createVisit();
            when(scheduledVisitRepository
                    .findReadyVisits(eq(CAREGIVER_ID), any(), any()))
                    .thenReturn(List.of(visit));
            mockPatientLookup();

            List<ScheduledVisitResponse> results =
                    visitService.getReadyVisits(CAREGIVER_ID);

            assertEquals(1, results.size());
        }

        @Test
        @DisplayName("should return empty list when no ready visits")
        void shouldReturnEmptyWhenNoReady() {
            when(scheduledVisitRepository
                    .findReadyVisits(eq(CAREGIVER_ID), any(), any()))
                    .thenReturn(Collections.emptyList());

            List<ScheduledVisitResponse> results =
                    visitService.getReadyVisits(CAREGIVER_ID);

            assertTrue(results.isEmpty());
        }
    }

    // ========================================================================
    // getUpcomingVisits
    // ========================================================================

    @Nested
    @DisplayName("getUpcomingVisits")
    class GetUpcomingVisits {

        @Test
        @DisplayName("should return upcoming visits")
        void shouldReturnUpcomingVisits() {
            ScheduledVisit visit = createVisit();
            when(scheduledVisitRepository
                    .findUpcomingVisits(eq(CAREGIVER_ID), any(), any()))
                    .thenReturn(List.of(visit));
            mockPatientLookup();

            List<ScheduledVisitResponse> results =
                    visitService.getUpcomingVisits(CAREGIVER_ID);

            assertEquals(1, results.size());
        }

        @Test
        @DisplayName("should return empty list when no upcoming visits")
        void shouldReturnEmptyWhenNoUpcoming() {
            when(scheduledVisitRepository
                    .findUpcomingVisits(eq(CAREGIVER_ID), any(), any()))
                    .thenReturn(Collections.emptyList());

            List<ScheduledVisitResponse> results =
                    visitService.getUpcomingVisits(CAREGIVER_ID);

            assertTrue(results.isEmpty());
        }
    }

    // ========================================================================
    // getScheduledVisit
    // ========================================================================

    @Nested
    @DisplayName("getScheduledVisit")
    class GetScheduledVisit {

        @Test
        @DisplayName("should return visit when found")
        void shouldReturnVisitWhenFound() {
            ScheduledVisit visit = createVisit();
            when(scheduledVisitRepository.findById(VISIT_ID))
                    .thenReturn(Optional.of(visit));
            mockPatientLookup();

            ScheduledVisitResponse response = visitService.getScheduledVisit(VISIT_ID);

            assertNotNull(response);
            assertEquals(VISIT_ID, response.getId());
            assertEquals("John Doe", response.getPatientName());
        }

        @Test
        @DisplayName("should throw exception when visit not found")
        void shouldThrowWhenNotFound() {
            when(scheduledVisitRepository.findById(VISIT_ID))
                    .thenReturn(Optional.empty());

            RuntimeException ex = assertThrows(RuntimeException.class,
                    () -> visitService.getScheduledVisit(VISIT_ID));

            assertTrue(ex.getMessage().contains("Scheduled visit not found"));
        }
    }

    // ========================================================================
    // updateScheduledVisit
    // ========================================================================

    @Nested
    @DisplayName("updateScheduledVisit")
    class UpdateScheduledVisit {

        @Test
        @DisplayName("should update visit successfully with no conflicts")
        void shouldUpdateVisitSuccessfully() {
            ScheduledVisit existing = createVisit();
            ScheduledVisitRequest request = createRequest();
            request.setServiceType("Updated Care");
            ConflictSummary noConflicts = createEmptyConflictSummary();

            ScheduledVisit updatedVisit = createVisit();
            updatedVisit.setServiceType("Updated Care");

            when(scheduledVisitRepository.findById(VISIT_ID))
                    .thenReturn(Optional.of(existing));
            when(conflictService.analyzeConflicts(
                    CAREGIVER_ID, PATIENT_ID, TEST_DATE, TEST_TIME, 60))
                    .thenReturn(noConflicts);
            when(scheduledVisitRepository.save(any(ScheduledVisit.class)))
                    .thenReturn(updatedVisit);
            mockPatientLookup();

            ScheduledVisitResponse response =
                    visitService.updateScheduledVisit(VISIT_ID, request);

            assertNotNull(response);
            assertEquals("Updated Care", response.getServiceType());
            // Audit entry for serviceType change
            verify(scheduledVisitAuditRepository, times(1))
                    .save(any(ScheduledVisitAudit.class));
        }

        @Test
        @DisplayName("should throw exception when visit not found for update")
        void shouldThrowWhenVisitNotFoundForUpdate() {
            ScheduledVisitRequest request = createRequest();
            when(scheduledVisitRepository.findById(VISIT_ID))
                    .thenReturn(Optional.empty());

            RuntimeException ex = assertThrows(RuntimeException.class,
                    () -> visitService.updateScheduledVisit(VISIT_ID, request));

            assertTrue(ex.getMessage().contains("Scheduled visit not found"));
        }

        @Test
        @DisplayName("should set conflict flag when conflicts detected during update")
        void shouldSetConflictFlagOnUpdate() {
            ScheduledVisit existing = createVisit();
            ScheduledVisitRequest request = createRequest();
            ConflictSummary conflicts = createEmptyConflictSummary();
            conflicts.setCaregiverConflicts(List.of(createVisit()));
            conflicts.addWarning("Caregiver conflict");

            ScheduledVisit updatedVisit = createVisit();
            updatedVisit.setConflictFlag(true);

            when(scheduledVisitRepository.findById(VISIT_ID))
                    .thenReturn(Optional.of(existing));
            when(conflictService.analyzeConflicts(
                    CAREGIVER_ID, PATIENT_ID, TEST_DATE, TEST_TIME, 60))
                    .thenReturn(conflicts);
            when(scheduledVisitRepository.save(any(ScheduledVisit.class)))
                    .thenReturn(updatedVisit);
            mockPatientLookup();

            ScheduledVisitResponse response =
                    visitService.updateScheduledVisit(VISIT_ID, request);

            assertNotNull(response);
            verify(scheduledVisitRepository).save(any(ScheduledVisit.class));
        }

        @Test
        @DisplayName("should create audit entries for each changed field")
        void shouldCreateAuditEntriesForChangedFields() {
            ScheduledVisit existing = createVisit();
            ScheduledVisitRequest request = createRequest();
            request.setServiceType("Updated Care");
            request.setPriority("High");
            request.setNotes("Updated notes");
            ConflictSummary noConflicts = createEmptyConflictSummary();

            ScheduledVisit updatedVisit = createVisit();
            updatedVisit.setServiceType("Updated Care");
            updatedVisit.setPriority("High");
            updatedVisit.setNotes("Updated notes");

            when(scheduledVisitRepository.findById(VISIT_ID))
                    .thenReturn(Optional.of(existing));
            when(conflictService.analyzeConflicts(
                    CAREGIVER_ID, PATIENT_ID, TEST_DATE, TEST_TIME, 60))
                    .thenReturn(noConflicts);
            when(scheduledVisitRepository.save(any(ScheduledVisit.class)))
                    .thenReturn(updatedVisit);
            mockPatientLookup();

            visitService.updateScheduledVisit(VISIT_ID, request);

            // serviceType, priority, notes changed = 3 audit entries
            verify(scheduledVisitAuditRepository, times(3))
                    .save(any(ScheduledVisitAudit.class));
        }

        @Test
        @DisplayName("should not create audit entries when no fields changed")
        void shouldNotCreateAuditWhenNoChanges() {
            ScheduledVisit existing = createVisit();
            ScheduledVisitRequest request = createRequest();
            // Request matches existing visit exactly
            ConflictSummary noConflicts = createEmptyConflictSummary();

            when(scheduledVisitRepository.findById(VISIT_ID))
                    .thenReturn(Optional.of(existing));
            when(conflictService.analyzeConflicts(
                    CAREGIVER_ID, PATIENT_ID, TEST_DATE, TEST_TIME, 60))
                    .thenReturn(noConflicts);
            when(scheduledVisitRepository.save(any(ScheduledVisit.class)))
                    .thenReturn(existing);
            mockPatientLookup();

            visitService.updateScheduledVisit(VISIT_ID, request);

            verify(scheduledVisitAuditRepository, never())
                    .save(any(ScheduledVisitAudit.class));
        }

        @Test
        @DisplayName("should create audit entry when notes changed from null")
        void shouldCreateAuditWhenNotesChangedFromNull() {
            ScheduledVisit existing = createVisit();
            existing.setNotes(null);
            ScheduledVisitRequest request = createRequest();
            request.setNotes("New notes");
            ConflictSummary noConflicts = createEmptyConflictSummary();

            when(scheduledVisitRepository.findById(VISIT_ID))
                    .thenReturn(Optional.of(existing));
            when(conflictService.analyzeConflicts(
                    CAREGIVER_ID, PATIENT_ID, TEST_DATE, TEST_TIME, 60))
                    .thenReturn(noConflicts);
            when(scheduledVisitRepository.save(any(ScheduledVisit.class)))
                    .thenReturn(existing);
            mockPatientLookup();

            visitService.updateScheduledVisit(VISIT_ID, request);

            // notes changed from null to "New notes" = 1 audit entry
            verify(scheduledVisitAuditRepository, times(1))
                    .save(any(ScheduledVisitAudit.class));
        }

        @Test
        @DisplayName("should clear conflict flag when no conflicts on update")
        void shouldClearConflictFlagWhenNoConflicts() {
            ScheduledVisit existing = createVisit();
            existing.setConflictFlag(true);
            existing.setConflictWarning("Old warning");
            ScheduledVisitRequest request = createRequest();
            ConflictSummary noConflicts = createEmptyConflictSummary();

            when(scheduledVisitRepository.findById(VISIT_ID))
                    .thenReturn(Optional.of(existing));
            when(conflictService.analyzeConflicts(
                    CAREGIVER_ID, PATIENT_ID, TEST_DATE, TEST_TIME, 60))
                    .thenReturn(noConflicts);
            when(scheduledVisitRepository.save(any(ScheduledVisit.class)))
                    .thenReturn(existing);
            mockPatientLookup();

            visitService.updateScheduledVisit(VISIT_ID, request);

            verify(scheduledVisitRepository).save(any(ScheduledVisit.class));
        }
    }

    // ========================================================================
    // cancelScheduledVisit
    // ========================================================================

    @Nested
    @DisplayName("cancelScheduledVisit")
    class CancelScheduledVisit {

        @Test
        @DisplayName("should cancel visit successfully")
        void shouldCancelVisit() {
            ScheduledVisit visit = createVisit();
            when(scheduledVisitRepository.findById(VISIT_ID))
                    .thenReturn(Optional.of(visit));
            when(scheduledVisitRepository.save(any(ScheduledVisit.class)))
                    .thenReturn(visit);

            visitService.cancelScheduledVisit(VISIT_ID);

            assertEquals("Cancelled", visit.getStatus());
            verify(scheduledVisitRepository).save(any(ScheduledVisit.class));
        }

        @Test
        @DisplayName("should throw exception when visit not found for cancel")
        void shouldThrowWhenVisitNotFoundForCancel() {
            when(scheduledVisitRepository.findById(VISIT_ID))
                    .thenReturn(Optional.empty());

            RuntimeException ex = assertThrows(RuntimeException.class,
                    () -> visitService.cancelScheduledVisit(VISIT_ID));

            assertTrue(ex.getMessage().contains("Scheduled visit not found"));
        }
    }

    // ========================================================================
    // updateVisitStatus
    // ========================================================================

    @Nested
    @DisplayName("updateVisitStatus")
    class UpdateVisitStatus {

        @Test
        @DisplayName("should update status successfully")
        void shouldUpdateStatus() {
            ScheduledVisit visit = createVisit();
            ScheduledVisit updatedVisit = createVisit();
            updatedVisit.setStatus("In Progress");

            when(scheduledVisitRepository.findById(VISIT_ID))
                    .thenReturn(Optional.of(visit));
            when(scheduledVisitRepository.save(any(ScheduledVisit.class)))
                    .thenReturn(updatedVisit);
            mockPatientLookup();

            ScheduledVisitResponse response =
                    visitService.updateVisitStatus(VISIT_ID, "In Progress");

            assertNotNull(response);
            assertEquals("In Progress", response.getStatus());
        }

        @Test
        @DisplayName("should throw exception when visit not found for status update")
        void shouldThrowWhenVisitNotFoundForStatusUpdate() {
            when(scheduledVisitRepository.findById(VISIT_ID))
                    .thenReturn(Optional.empty());

            RuntimeException ex = assertThrows(RuntimeException.class,
                    () -> visitService.updateVisitStatus(VISIT_ID, "In Progress"));

            assertTrue(ex.getMessage().contains("Scheduled visit not found"));
        }

        @Test
        @DisplayName("should update to Completed status")
        void shouldUpdateToCompleted() {
            ScheduledVisit visit = createVisit();
            ScheduledVisit updatedVisit = createVisit();
            updatedVisit.setStatus("Completed");

            when(scheduledVisitRepository.findById(VISIT_ID))
                    .thenReturn(Optional.of(visit));
            when(scheduledVisitRepository.save(any(ScheduledVisit.class)))
                    .thenReturn(updatedVisit);
            mockPatientLookup();

            ScheduledVisitResponse response =
                    visitService.updateVisitStatus(VISIT_ID, "Completed");

            assertEquals("Completed", response.getStatus());
        }
    }

    // ========================================================================
    // deleteScheduledVisit
    // ========================================================================

    @Nested
    @DisplayName("deleteScheduledVisit")
    class DeleteScheduledVisit {

        @Test
        @DisplayName("should delete visit and create audit entry")
        void shouldDeleteVisitAndAudit() throws Exception {
            ScheduledVisit visit = createVisit();
            when(scheduledVisitRepository.findById(VISIT_ID))
                    .thenReturn(Optional.of(visit));
            when(objectMapper.writeValueAsString(any())).thenReturn("{\"id\":100}");

            visitService.deleteScheduledVisit(VISIT_ID);

            verify(scheduledVisitRepository).deleteById(VISIT_ID);
            verify(scheduledVisitAuditRepository).save(any(ScheduledVisitAudit.class));
        }

        @Test
        @DisplayName("should throw exception when visit not found for delete")
        void shouldThrowWhenVisitNotFoundForDelete() {
            when(scheduledVisitRepository.findById(VISIT_ID))
                    .thenReturn(Optional.empty());

            RuntimeException ex = assertThrows(RuntimeException.class,
                    () -> visitService.deleteScheduledVisit(VISIT_ID));

            assertTrue(ex.getMessage().contains("Scheduled visit not found"));
        }

        @Test
        @DisplayName("should handle serialization failure gracefully during delete")
        void shouldHandleSerializationFailureDuringDelete() throws Exception {
            ScheduledVisit visit = createVisit();
            when(scheduledVisitRepository.findById(VISIT_ID))
                    .thenReturn(Optional.of(visit));
            when(objectMapper.writeValueAsString(any()))
                    .thenThrow(new RuntimeException("Serialization error"));

            visitService.deleteScheduledVisit(VISIT_ID);

            // Should still delete and create audit with fallback value
            verify(scheduledVisitRepository).deleteById(VISIT_ID);
            verify(scheduledVisitAuditRepository).save(any(ScheduledVisitAudit.class));
        }
    }

    // ========================================================================
    // getVisitAuditHistory
    // ========================================================================

    @Nested
    @DisplayName("getVisitAuditHistory")
    class GetVisitAuditHistory {

        @Test
        @DisplayName("should return audit history for visit")
        void shouldReturnAuditHistory() {
            ScheduledVisit visit = createVisit();
            when(scheduledVisitRepository.findById(VISIT_ID))
                    .thenReturn(Optional.of(visit));

            ScheduledVisitAudit audit = new ScheduledVisitAudit();
            audit.setId(1L);
            audit.setVisitId(VISIT_ID);
            audit.setAction("CREATED");
            audit.setChangedField(null);
            audit.setOldValue(null);
            audit.setNewValue("{}");
            audit.setChangedBy(TEST_USER);
            audit.setChangedAt(LocalDateTime.now());

            when(scheduledVisitAuditRepository
                    .findByVisitIdOrderByChangedAtDesc(VISIT_ID))
                    .thenReturn(List.of(audit));

            List<ScheduledVisitAuditResponse> results =
                    visitService.getVisitAuditHistory(VISIT_ID);

            assertEquals(1, results.size());
            assertEquals("CREATED", results.get(0).getAction());
            assertEquals(VISIT_ID, results.get(0).getVisitId());
            assertEquals(TEST_USER, results.get(0).getChangedBy());
        }

        @Test
        @DisplayName("should return empty list when no audit history")
        void shouldReturnEmptyAuditHistory() {
            ScheduledVisit visit = createVisit();
            when(scheduledVisitRepository.findById(VISIT_ID))
                    .thenReturn(Optional.of(visit));
            when(scheduledVisitAuditRepository
                    .findByVisitIdOrderByChangedAtDesc(VISIT_ID))
                    .thenReturn(Collections.emptyList());

            List<ScheduledVisitAuditResponse> results =
                    visitService.getVisitAuditHistory(VISIT_ID);

            assertTrue(results.isEmpty());
        }

        @Test
        @DisplayName("should throw exception when visit not found for audit history")
        void shouldThrowWhenVisitNotFoundForAudit() {
            when(scheduledVisitRepository.findById(VISIT_ID))
                    .thenReturn(Optional.empty());

            RuntimeException ex = assertThrows(RuntimeException.class,
                    () -> visitService.getVisitAuditHistory(VISIT_ID));

            assertTrue(ex.getMessage().contains("Scheduled visit not found"));
        }

        @Test
        @DisplayName("should return multiple audit entries in order")
        void shouldReturnMultipleAuditEntries() {
            ScheduledVisit visit = createVisit();
            when(scheduledVisitRepository.findById(VISIT_ID))
                    .thenReturn(Optional.of(visit));

            ScheduledVisitAudit audit1 = new ScheduledVisitAudit();
            audit1.setId(1L);
            audit1.setVisitId(VISIT_ID);
            audit1.setAction("CREATED");
            audit1.setChangedAt(LocalDateTime.now().minusHours(2));
            audit1.setChangedBy(TEST_USER);

            ScheduledVisitAudit audit2 = new ScheduledVisitAudit();
            audit2.setId(2L);
            audit2.setVisitId(VISIT_ID);
            audit2.setAction("UPDATED");
            audit2.setChangedField("serviceType");
            audit2.setOldValue("General Care");
            audit2.setNewValue("Physical Therapy");
            audit2.setChangedAt(LocalDateTime.now().minusHours(1));
            audit2.setChangedBy(TEST_USER);

            when(scheduledVisitAuditRepository
                    .findByVisitIdOrderByChangedAtDesc(VISIT_ID))
                    .thenReturn(List.of(audit2, audit1));

            List<ScheduledVisitAuditResponse> results =
                    visitService.getVisitAuditHistory(VISIT_ID);

            assertEquals(2, results.size());
            assertEquals("UPDATED", results.get(0).getAction());
            assertEquals("CREATED", results.get(1).getAction());
        }
    }

    // ========================================================================
    // getVisitAuditDetails
    // ========================================================================

    @Nested
    @DisplayName("getVisitAuditDetails")
    class GetVisitAuditDetails {

        @Test
        @DisplayName("should return audit diff response")
        void shouldReturnAuditDiffResponse() {
            Long auditId = 50L;
            ScheduledVisit visit = createVisit();
            LocalDateTime auditTime = LocalDateTime.of(2026, 3, 17, 12, 0);

            ScheduledVisitAudit audit = new ScheduledVisitAudit();
            audit.setId(auditId);
            audit.setVisitId(VISIT_ID);
            audit.setAction("UPDATED");
            audit.setChangedField("serviceType");
            audit.setOldValue("General Care");
            audit.setNewValue("Physical Therapy");
            audit.setChangedBy(TEST_USER);
            audit.setChangedAt(auditTime);

            when(scheduledVisitRepository.findById(VISIT_ID))
                    .thenReturn(Optional.of(visit));
            when(scheduledVisitAuditRepository.findById(auditId))
                    .thenReturn(Optional.of(audit));
            when(scheduledVisitAuditRepository
                    .findByVisitIdAndChangedAtBeforeOrderByChangedAtDesc(
                            VISIT_ID, auditTime))
                    .thenReturn(Collections.emptyList());
            mockPatientLookup();

            AuditDiffResponse response =
                    visitService.getVisitAuditDetails(VISIT_ID, auditId);

            assertNotNull(response);
            assertNull(response.getBefore()); // No prior audits
            assertNotNull(response.getAfter());
            assertEquals("serviceType", response.getChangedField());
            assertEquals("UPDATED", response.getAction());
            assertEquals(TEST_USER, response.getChangedBy());
            assertEquals(auditTime, response.getChangedAt());
        }

        @Test
        @DisplayName("should throw exception when visit not found for audit details")
        void shouldThrowWhenVisitNotFound() {
            when(scheduledVisitRepository.findById(VISIT_ID))
                    .thenReturn(Optional.empty());

            RuntimeException ex = assertThrows(RuntimeException.class,
                    () -> visitService.getVisitAuditDetails(VISIT_ID, 50L));

            assertTrue(ex.getMessage().contains("Scheduled visit not found"));
        }

        @Test
        @DisplayName("should throw exception when audit entry not found")
        void shouldThrowWhenAuditNotFound() {
            ScheduledVisit visit = createVisit();
            when(scheduledVisitRepository.findById(VISIT_ID))
                    .thenReturn(Optional.of(visit));
            when(scheduledVisitAuditRepository.findById(50L))
                    .thenReturn(Optional.empty());

            RuntimeException ex = assertThrows(RuntimeException.class,
                    () -> visitService.getVisitAuditDetails(VISIT_ID, 50L));

            assertTrue(ex.getMessage().contains("Audit entry not found"));
        }

        @Test
        @DisplayName("should throw exception when audit does not belong to visit")
        void shouldThrowWhenAuditDoesNotBelongToVisit() {
            ScheduledVisit visit = createVisit();
            ScheduledVisitAudit audit = new ScheduledVisitAudit();
            audit.setId(50L);
            audit.setVisitId(999L); // Different visit ID
            audit.setChangedAt(LocalDateTime.now());

            when(scheduledVisitRepository.findById(VISIT_ID))
                    .thenReturn(Optional.of(visit));
            when(scheduledVisitAuditRepository.findById(50L))
                    .thenReturn(Optional.of(audit));

            RuntimeException ex = assertThrows(RuntimeException.class,
                    () -> visitService.getVisitAuditDetails(VISIT_ID, 50L));

            assertTrue(ex.getMessage().contains(
                    "Audit entry does not belong to this visit"));
        }

        @Test
        @DisplayName("should reconstruct before state from prior audits")
        void shouldReconstructBeforeStateFromPriorAudits() {
            Long auditId = 50L;
            ScheduledVisit visit = createVisit();
            LocalDateTime auditTime = LocalDateTime.of(2026, 3, 17, 12, 0);

            ScheduledVisitAudit currentAudit = new ScheduledVisitAudit();
            currentAudit.setId(auditId);
            currentAudit.setVisitId(VISIT_ID);
            currentAudit.setAction("UPDATED");
            currentAudit.setChangedField("serviceType");
            currentAudit.setOldValue("General Care");
            currentAudit.setNewValue("Physical Therapy");
            currentAudit.setChangedBy(TEST_USER);
            currentAudit.setChangedAt(auditTime);

            ScheduledVisitAudit priorAudit = new ScheduledVisitAudit();
            priorAudit.setId(49L);
            priorAudit.setVisitId(VISIT_ID);
            priorAudit.setAction("UPDATED");
            priorAudit.setChangedField("serviceType");
            priorAudit.setOldValue("Home Care");
            priorAudit.setNewValue("General Care");
            priorAudit.setChangedBy(TEST_USER);
            priorAudit.setChangedAt(auditTime.minusHours(1));

            when(scheduledVisitRepository.findById(VISIT_ID))
                    .thenReturn(Optional.of(visit));
            when(scheduledVisitAuditRepository.findById(auditId))
                    .thenReturn(Optional.of(currentAudit));
            when(scheduledVisitAuditRepository
                    .findByVisitIdAndChangedAtBeforeOrderByChangedAtDesc(
                            VISIT_ID, auditTime))
                    .thenReturn(List.of(priorAudit));
            mockPatientLookup();

            AuditDiffResponse response =
                    visitService.getVisitAuditDetails(VISIT_ID, auditId);

            assertNotNull(response);
            assertNotNull(response.getBefore());
            assertNotNull(response.getAfter());
        }
    }

    // ========================================================================
    // analyzeConflicts (delegation)
    // ========================================================================

    @Nested
    @DisplayName("analyzeConflicts")
    class AnalyzeConflicts {

        @Test
        @DisplayName("should delegate to ScheduleConflictService")
        void shouldDelegateToConflictService() {
            ConflictSummary expected = createEmptyConflictSummary();
            when(conflictService.analyzeConflicts(
                    CAREGIVER_ID, PATIENT_ID, TEST_DATE, TEST_TIME, 60))
                    .thenReturn(expected);

            ConflictSummary result = visitService.analyzeConflicts(
                    CAREGIVER_ID, PATIENT_ID, TEST_DATE, TEST_TIME, 60);

            assertEquals(expected, result);
            verify(conflictService).analyzeConflicts(
                    CAREGIVER_ID, PATIENT_ID, TEST_DATE, TEST_TIME, 60);
        }
    }

    // ========================================================================
    // getCurrentUsername (implicit via SecurityContext)
    // ========================================================================

    @Nested
    @DisplayName("getCurrentUsername via SecurityContext")
    class GetCurrentUsername {

        @Test
        @DisplayName("should use SYSTEM when no authentication present")
        void shouldUseSystemWhenNoAuth() throws Exception {
            SecurityContextHolder.clearContext();

            ScheduledVisitRequest request = createRequest();
            ScheduledVisit savedVisit = createVisit();

            stubNoConflicts();
            when(scheduledVisitRepository.save(any(ScheduledVisit.class)))
                    .thenReturn(savedVisit);
            when(objectMapper.writeValueAsString(any())).thenReturn("{}");
            mockPatientLookup();

            visitService.createScheduledVisit(CAREGIVER_ID, request);

            // Verify audit was created (indirectly tests SYSTEM username path)
            verify(scheduledVisitAuditRepository).save(any(ScheduledVisitAudit.class));
        }
    }

    // ========================================================================
    // getPatientName edge cases
    // ========================================================================

    @Nested
    @DisplayName("getPatientName edge cases")
    class GetPatientName {

        @Test
        @DisplayName("should return Unknown when patient not found")
        void shouldReturnUnknownWhenPatientNotFound() {
            ScheduledVisit visit = createVisit();
            when(scheduledVisitRepository.findById(VISIT_ID))
                    .thenReturn(Optional.of(visit));
            when(patientRepository.findById(PATIENT_ID))
                    .thenReturn(Optional.empty());

            ScheduledVisitResponse response = visitService.getScheduledVisit(VISIT_ID);

            assertEquals("Unknown", response.getPatientName());
        }

        @Test
        @DisplayName("should handle patient with null first name")
        void shouldHandleNullFirstName() {
            ScheduledVisit visit = createVisit();
            Patient patient = Patient.builder()
                    .id(PATIENT_ID).firstName(null).lastName("Doe").build();
            when(scheduledVisitRepository.findById(VISIT_ID))
                    .thenReturn(Optional.of(visit));
            when(patientRepository.findById(PATIENT_ID))
                    .thenReturn(Optional.of(patient));

            ScheduledVisitResponse response = visitService.getScheduledVisit(VISIT_ID);

            assertEquals("Doe", response.getPatientName());
        }

        @Test
        @DisplayName("should handle patient with null last name")
        void shouldHandleNullLastName() {
            ScheduledVisit visit = createVisit();
            Patient patient = Patient.builder()
                    .id(PATIENT_ID).firstName("John").lastName(null).build();
            when(scheduledVisitRepository.findById(VISIT_ID))
                    .thenReturn(Optional.of(visit));
            when(patientRepository.findById(PATIENT_ID))
                    .thenReturn(Optional.of(patient));

            ScheduledVisitResponse response = visitService.getScheduledVisit(VISIT_ID);

            assertEquals("John", response.getPatientName());
        }

        @Test
        @DisplayName("should return Unknown when patient ID is null")
        void shouldReturnUnknownWhenPatientIdNull() {
            ScheduledVisit visit = createVisit();
            visit.setPatientId(null);
            when(scheduledVisitRepository.findByCaregiverId(CAREGIVER_ID))
                    .thenReturn(List.of(visit));

            List<ScheduledVisitResponse> results =
                    visitService.getScheduledVisits(CAREGIVER_ID);

            assertEquals(1, results.size());
            assertEquals("Unknown", results.get(0).getPatientName());
        }

        @Test
        @DisplayName("should handle patient with both names null")
        void shouldHandleBothNamesNull() {
            ScheduledVisit visit = createVisit();
            Patient patient = Patient.builder()
                    .id(PATIENT_ID).firstName(null).lastName(null).build();
            when(scheduledVisitRepository.findById(VISIT_ID))
                    .thenReturn(Optional.of(visit));
            when(patientRepository.findById(PATIENT_ID))
                    .thenReturn(Optional.of(patient));

            ScheduledVisitResponse response = visitService.getScheduledVisit(VISIT_ID);

            assertEquals("", response.getPatientName());
        }
    }

    // ========================================================================
    // getScheduledVisitsBetweenDatesForPatient
    // ========================================================================

    @Nested
    @DisplayName("getScheduledVisitsBetweenDatesForPatient")
    class GetScheduledVisitsBetweenDatesForPatient {

        @Test
        @DisplayName("should return visits for patient between dates")
        void shouldReturnVisitsForPatientBetweenDates() {
            ScheduledVisit visit = createVisit();
            LocalDate start = TEST_DATE.minusDays(1);
            LocalDate end = TEST_DATE.plusDays(1);

            when(scheduledVisitRepository
                    .findByPatientIdAndScheduledDateBetween(PATIENT_ID, start, end))
                    .thenReturn(List.of(visit));
            mockPatientLookup();

            List<ScheduledVisitResponse> results =
                    visitService.getScheduledVisitsBetweenDatesForPatient(PATIENT_ID, start, end);

            assertEquals(1, results.size());
            assertEquals(VISIT_ID, results.get(0).getId());
        }

        @Test
        @DisplayName("should return empty list when patient has no visits in range")
        void shouldReturnEmptyListForPatientRange() {
            LocalDate start = TEST_DATE.minusDays(1);
            LocalDate end = TEST_DATE.plusDays(1);

            when(scheduledVisitRepository
                    .findByPatientIdAndScheduledDateBetween(PATIENT_ID, start, end))
                    .thenReturn(Collections.emptyList());

            List<ScheduledVisitResponse> results =
                    visitService.getScheduledVisitsBetweenDatesForPatient(PATIENT_ID, start, end);

            assertTrue(results.isEmpty());
        }
    }

    // ========================================================================
    // updateScheduledVisit — additional audit-field branches
    // (patientId / scheduledDate / scheduledTime / durationMinutes changes)
    // ========================================================================

    @Nested
    @DisplayName("updateScheduledVisit — remaining audit field branches")
    class UpdateScheduledVisitRemainingAuditFields {

        @Test
        @DisplayName("should create audit entry when patientId changes")
        void shouldCreateAuditEntryWhenPatientIdChanges() {
            ScheduledVisit existing = createVisit();
            ScheduledVisitRequest request = createRequest();
            Long newPatientId = 99L;
            request.setPatientId(newPatientId);

            when(scheduledVisitRepository.findById(VISIT_ID))
                    .thenReturn(Optional.of(existing));
            when(conflictService.analyzeConflicts(
                    eq(CAREGIVER_ID), eq(newPatientId), eq(TEST_DATE), eq(TEST_TIME), eq(60)))
                    .thenReturn(createEmptyConflictSummary());
            when(scheduledVisitRepository.save(any(ScheduledVisit.class)))
                    .thenReturn(existing);
            when(patientRepository.findById(any())).thenReturn(Optional.of(createPatient()));

            visitService.updateScheduledVisit(VISIT_ID, request);

            verify(scheduledVisitAuditRepository, times(1))
                    .save(any(ScheduledVisitAudit.class));
        }

        @Test
        @DisplayName("should create audit entry when scheduledDate changes")
        void shouldCreateAuditEntryWhenScheduledDateChanges() {
            ScheduledVisit existing = createVisit();
            ScheduledVisitRequest request = createRequest();
            LocalDate newDate = TEST_DATE.plusDays(1);
            request.setScheduledDate(newDate);

            when(scheduledVisitRepository.findById(VISIT_ID))
                    .thenReturn(Optional.of(existing));
            when(conflictService.analyzeConflicts(
                    eq(CAREGIVER_ID), eq(PATIENT_ID), eq(newDate), eq(TEST_TIME), eq(60)))
                    .thenReturn(createEmptyConflictSummary());
            when(scheduledVisitRepository.save(any(ScheduledVisit.class)))
                    .thenReturn(existing);
            mockPatientLookup();

            visitService.updateScheduledVisit(VISIT_ID, request);

            verify(scheduledVisitAuditRepository, times(1))
                    .save(any(ScheduledVisitAudit.class));
        }

        @Test
        @DisplayName("should create audit entry when scheduledTime changes")
        void shouldCreateAuditEntryWhenScheduledTimeChanges() {
            ScheduledVisit existing = createVisit();
            ScheduledVisitRequest request = createRequest();
            LocalTime newTime = TEST_TIME.plusHours(2);
            request.setScheduledTime(newTime);

            when(scheduledVisitRepository.findById(VISIT_ID))
                    .thenReturn(Optional.of(existing));
            when(conflictService.analyzeConflicts(
                    eq(CAREGIVER_ID), eq(PATIENT_ID), eq(TEST_DATE), eq(newTime), eq(60)))
                    .thenReturn(createEmptyConflictSummary());
            when(scheduledVisitRepository.save(any(ScheduledVisit.class)))
                    .thenReturn(existing);
            mockPatientLookup();

            visitService.updateScheduledVisit(VISIT_ID, request);

            verify(scheduledVisitAuditRepository, times(1))
                    .save(any(ScheduledVisitAudit.class));
        }

        @Test
        @DisplayName("should create audit entry when durationMinutes changes")
        void shouldCreateAuditEntryWhenDurationMinutesChanges() {
            ScheduledVisit existing = createVisit();
            ScheduledVisitRequest request = createRequest();
            request.setDurationMinutes(90);

            when(scheduledVisitRepository.findById(VISIT_ID))
                    .thenReturn(Optional.of(existing));
            when(conflictService.analyzeConflicts(
                    eq(CAREGIVER_ID), eq(PATIENT_ID), eq(TEST_DATE), eq(TEST_TIME), eq(90)))
                    .thenReturn(createEmptyConflictSummary());
            when(scheduledVisitRepository.save(any(ScheduledVisit.class)))
                    .thenReturn(existing);
            mockPatientLookup();

            visitService.updateScheduledVisit(VISIT_ID, request);

            verify(scheduledVisitAuditRepository, times(1))
                    .save(any(ScheduledVisitAudit.class));
        }

        @Test
        @DisplayName("should not create audit entry when both old and new notes are null")
        void shouldNotCreateAuditEntryWhenNotesBothNull() {
            // Arrange: oldNotes == null and request.getNotes() == null exercises the
            // false branch of "request.getNotes() != null" (first clause) and the
            // false branch of "oldNotes != null" (second clause) in the notes-changed
            // condition — neither is hit by the other notes-change tests.
            ScheduledVisit existing = createVisit();
            existing.setNotes(null);
            ScheduledVisitRequest request = createRequest();
            request.setNotes(null);

            when(scheduledVisitRepository.findById(VISIT_ID))
                    .thenReturn(Optional.of(existing));
            when(conflictService.analyzeConflicts(
                    eq(CAREGIVER_ID), eq(PATIENT_ID), eq(TEST_DATE), eq(TEST_TIME), eq(60)))
                    .thenReturn(createEmptyConflictSummary());
            when(scheduledVisitRepository.save(any(ScheduledVisit.class)))
                    .thenReturn(existing);
            mockPatientLookup();

            visitService.updateScheduledVisit(VISIT_ID, request);

            verify(scheduledVisitAuditRepository, never())
                    .save(any(ScheduledVisitAudit.class));
        }

        @Test
        @DisplayName("should create audit entry with empty-string new value when notes cleared to null")
        void shouldCreateAuditEntryWhenNotesClearedToNull() {
            // Arrange: oldNotes is non-null and request.getNotes() is null — this
            // hits the "request.getNotes() != null ? ... : \"\"" false branch at the
            // createAuditEntry call site, which no other test exercises.
            ScheduledVisit existing = createVisit();
            existing.setNotes("Existing notes");
            ScheduledVisitRequest request = createRequest();
            request.setNotes(null);

            when(scheduledVisitRepository.findById(VISIT_ID))
                    .thenReturn(Optional.of(existing));
            when(conflictService.analyzeConflicts(
                    eq(CAREGIVER_ID), eq(PATIENT_ID), eq(TEST_DATE), eq(TEST_TIME), eq(60)))
                    .thenReturn(createEmptyConflictSummary());
            when(scheduledVisitRepository.save(any(ScheduledVisit.class)))
                    .thenReturn(existing);
            mockPatientLookup();

            visitService.updateScheduledVisit(VISIT_ID, request);

            verify(scheduledVisitAuditRepository, times(1))
                    .save(any(ScheduledVisitAudit.class));
        }
    }

    // ========================================================================
    // getVisitAuditDetails — applyAuditToVisit switch coverage
    // Drives reconstructVisitFromAuditHistory through every changedField case
    // (patientId / scheduledDate / scheduledTime / durationMinutes / priority / notes)
    // ========================================================================

    @Nested
    @DisplayName("getVisitAuditDetails — applyAuditToVisit field coverage")
    class ApplyAuditToVisitFieldCoverage {

        private ScheduledVisitAudit priorAuditFor(Long visitId, String field, String oldValue,
                String newValue, LocalDateTime changedAt) {
            ScheduledVisitAudit audit = new ScheduledVisitAudit();
            audit.setId((long) changedAt.getNano()); // unique-enough id per call within a test
            audit.setVisitId(visitId);
            audit.setAction("UPDATED");
            audit.setChangedField(field);
            audit.setOldValue(oldValue);
            audit.setNewValue(newValue);
            audit.setChangedBy(TEST_USER);
            audit.setChangedAt(changedAt);
            return audit;
        }

        @Test
        @DisplayName("should reconstruct before-state across every changed field type")
        void shouldReconstructBeforeStateAcrossEveryField() {
            Long auditId = 50L;
            ScheduledVisit visit = createVisit();
            LocalDateTime currentTime = LocalDateTime.of(2026, 3, 17, 12, 0);

            ScheduledVisitAudit currentAudit = new ScheduledVisitAudit();
            currentAudit.setId(auditId);
            currentAudit.setVisitId(VISIT_ID);
            currentAudit.setAction("UPDATED");
            currentAudit.setChangedField("notes");
            currentAudit.setOldValue("old notes");
            currentAudit.setNewValue("new notes");
            currentAudit.setChangedBy(TEST_USER);
            currentAudit.setChangedAt(currentTime);

            // One prior audit per switch-case branch in applyAuditToVisit.
            List<ScheduledVisitAudit> priorAudits = List.of(
                    priorAuditFor(VISIT_ID, "patientId", "10", "20", currentTime.minusHours(6)),
                    priorAuditFor(VISIT_ID, "scheduledDate", "2026-03-16", "2026-03-17", currentTime.minusHours(5)),
                    priorAuditFor(VISIT_ID, "scheduledTime", "09:00", "10:00", currentTime.minusHours(4)),
                    priorAuditFor(VISIT_ID, "durationMinutes", "30", "60", currentTime.minusHours(3)),
                    priorAuditFor(VISIT_ID, "priority", "Low", "Normal", currentTime.minusHours(2)),
                    priorAuditFor(VISIT_ID, "notes", "older notes", "old notes", currentTime.minusHours(1)));

            when(scheduledVisitRepository.findById(VISIT_ID))
                    .thenReturn(Optional.of(visit));
            when(scheduledVisitAuditRepository.findById(auditId))
                    .thenReturn(Optional.of(currentAudit));
            when(scheduledVisitAuditRepository
                    .findByVisitIdAndChangedAtBeforeOrderByChangedAtDesc(VISIT_ID, currentTime))
                    .thenReturn(priorAudits);
            mockPatientLookup();

            AuditDiffResponse response = visitService.getVisitAuditDetails(VISIT_ID, auditId);

            assertNotNull(response);
            assertNotNull(response.getBefore());
            assertEquals(20L, response.getBefore().getPatientId());
            assertEquals(LocalDate.parse("2026-03-17"), response.getBefore().getScheduledDate());
            assertEquals(LocalTime.parse("10:00"), response.getBefore().getScheduledTime());
            assertEquals(60, response.getBefore().getDurationMinutes());
            assertEquals("Normal", response.getBefore().getPriority());
            assertEquals("old notes", response.getBefore().getNotes());
        }

        @Test
        @DisplayName("should throw when visit is removed between existence check and reconstruction")
        void shouldThrowWhenVisitRemovedDuringReconstruction() {
            Long auditId = 50L;
            ScheduledVisit visit = createVisit();
            LocalDateTime currentTime = LocalDateTime.of(2026, 3, 17, 12, 0);

            ScheduledVisitAudit currentAudit = new ScheduledVisitAudit();
            currentAudit.setId(auditId);
            currentAudit.setVisitId(VISIT_ID);
            currentAudit.setAction("UPDATED");
            currentAudit.setChangedField("serviceType");
            currentAudit.setOldValue("General Care");
            currentAudit.setNewValue("Physical Therapy");
            currentAudit.setChangedBy(TEST_USER);
            currentAudit.setChangedAt(currentTime);

            // First call (existence check) finds the visit; second call
            // (reconstructVisitFromCurrentState) simulates a concurrent delete.
            when(scheduledVisitRepository.findById(VISIT_ID))
                    .thenReturn(Optional.of(visit))
                    .thenReturn(Optional.empty());
            when(scheduledVisitAuditRepository.findById(auditId))
                    .thenReturn(Optional.of(currentAudit));
            when(scheduledVisitAuditRepository
                    .findByVisitIdAndChangedAtBeforeOrderByChangedAtDesc(VISIT_ID, currentTime))
                    .thenReturn(Collections.emptyList());

            RuntimeException ex = assertThrows(RuntimeException.class,
                    () -> visitService.getVisitAuditDetails(VISIT_ID, auditId));

            assertTrue(ex.getMessage().contains("Visit not found"));
        }

        @Test
        @DisplayName("should leave visit unchanged when prior audit has an unrecognized changed field")
        void shouldLeaveVisitUnchangedForUnrecognizedChangedField() {
            // Arrange: applyAuditToVisit's switch has no default case — a prior
            // audit whose changedField matches none of the 7 known cases (e.g. a
            // forward-compatible field added later) falls through and applies no
            // mutation. Reachable via the public API whenever audit history
            // contains an entry the current switch doesn't recognize.
            Long auditId = 50L;
            ScheduledVisit visit = createVisit();
            LocalDateTime currentTime = LocalDateTime.of(2026, 3, 17, 12, 0);

            ScheduledVisitAudit currentAudit = new ScheduledVisitAudit();
            currentAudit.setId(auditId);
            currentAudit.setVisitId(VISIT_ID);
            currentAudit.setAction("UPDATED");
            currentAudit.setChangedField("notes");
            currentAudit.setOldValue("old notes");
            currentAudit.setNewValue("new notes");
            currentAudit.setChangedBy(TEST_USER);
            currentAudit.setChangedAt(currentTime);

            List<ScheduledVisitAudit> priorAudits = List.of(
                    priorAuditFor(VISIT_ID, "unknownField", "before", "after", currentTime.minusHours(1)));

            when(scheduledVisitRepository.findById(VISIT_ID))
                    .thenReturn(Optional.of(visit));
            when(scheduledVisitAuditRepository.findById(auditId))
                    .thenReturn(Optional.of(currentAudit));
            when(scheduledVisitAuditRepository
                    .findByVisitIdAndChangedAtBeforeOrderByChangedAtDesc(VISIT_ID, currentTime))
                    .thenReturn(priorAudits);
            mockPatientLookup();

            AuditDiffResponse response = visitService.getVisitAuditDetails(VISIT_ID, auditId);

            // Assert: reconstruction starts from a blank visit (only id set) and the
            // unrecognized field never mutates it — patientId remains unset.
            assertNotNull(response);
            assertNotNull(response.getBefore());
            assertEquals(VISIT_ID, response.getBefore().getId());
            assertNull(response.getBefore().getPatientId());
        }
    }

    // ========================================================================
    // formatConflictingVisits — private helper, exercised via reflection.
    // Unreachable through the public API: createScheduledVisit only invokes
    // this helper after confirming the patient-conflict list is non-empty, so
    // the empty/null branch is invoked directly here, matching the reflection
    // pattern already used for ScheduledVisit-style private-method coverage.
    // ========================================================================

    @Nested
    @DisplayName("formatConflictingVisits (private helper)")
    class FormatConflictingVisits {

        @Test
        @DisplayName("should return 'none' for an empty conflict list")
        void shouldReturnNoneForEmptyList() throws Exception {
            var method = ScheduledVisitService.class
                    .getDeclaredMethod("formatConflictingVisits", List.class);
            method.setAccessible(true);

            String result = (String) method.invoke(visitService, Collections.emptyList());

            assertEquals("none", result);
        }

        @Test
        @DisplayName("should return 'none' for a null conflict list")
        void shouldReturnNoneForNullList() throws Exception {
            var method = ScheduledVisitService.class
                    .getDeclaredMethod("formatConflictingVisits", List.class);
            method.setAccessible(true);

            String result = (String) method.invoke(visitService, new Object[] { null });

            assertEquals("none", result);
        }
    }
}
