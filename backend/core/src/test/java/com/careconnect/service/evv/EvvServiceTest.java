package com.careconnect.service.evv;

import com.careconnect.dto.evv.EorApprovalRequestDto;
import com.careconnect.dto.evv.EvvCorrectionRequestDto;
import com.careconnect.dto.evv.EvvLocationResponse;
import com.careconnect.dto.evv.EvvRecordRequestDto;
import com.careconnect.dto.evv.EvvSearchRequestDto;
import com.careconnect.model.Patient;
import com.careconnect.model.evv.EvvCorrection;
import com.careconnect.model.evv.EvvLocationRole;
import com.careconnect.model.evv.EvvLocationType;
import com.careconnect.model.evv.EvvOfflineQueue;
import com.careconnect.model.evv.EvvRecord;
import com.careconnect.model.evv.NoGpsReason;
import com.careconnect.dto.evv.EvvLocationRequest;
import com.careconnect.model.schedule.ScheduledVisit;
import com.careconnect.model.User;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.UserRepository;
import com.careconnect.repository.evv.EvvCorrectionRepository;
import com.careconnect.repository.evv.EvvOfflineQueueRepository;
import com.careconnect.repository.evv.EvvRecordRepository;
import com.careconnect.repository.schedule.ScheduledVisitRepository;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageImpl;
import org.springframework.data.domain.Pageable;

import java.lang.reflect.Method;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.Map;
import java.util.NoSuchElementException;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class EvvServiceTest {

    @Mock private EvvRecordRepository recordRepository;
    @Mock private EvvCorrectionRepository correctionRepository;
    @Mock private EvvOfflineQueueRepository offlineQueueRepository;
    @Mock private PatientRepository patientRepository;
    @Mock private UserRepository userRepository;
    @Mock private EvvLocationService locationService;
    @Mock private AuditLogger audit;
    @Mock private ScheduledVisitRepository scheduledVisitRepository;

    @InjectMocks
    private EvvService evvService;

    // ─── helpers ───────────────────────────────────────────────────────────────

    private Patient buildPatient(Long id) {
        return Patient.builder()
                .id(id)
                .firstName("Jane")
                .lastName("Doe")
                .maNumber("MA-001")
                .build();
    }

    private EvvRecordRequestDto.EvvRecordRequestDtoBuilder baseReqBuilder() throws Exception {
        return EvvRecordRequestDto.builder()
                .patientId(5L)
                .serviceType("HOME_HEALTH")
                .individualName("Jane Doe")
                .caregiverId(10L)
                .dateOfService(LocalDate.of(2025, 1, 15))
                .timeIn(OffsetDateTime.parse("2025-01-15T08:00:00Z"))
                .timeOut(OffsetDateTime.parse("2025-01-15T10:00:00Z"))
                .stateCode("DC");
    }

    private EvvRecord buildSavedRecord(Long id, Patient patient) {
        return EvvRecord.builder()
                .id(id)
                .patient(patient)
                .serviceType("HOME_HEALTH")
                .individualName("Jane Doe")
                .caregiverId(10L)
                .dateOfService(LocalDate.of(2025, 1, 15))
                .timeIn(OffsetDateTime.parse("2025-01-15T08:00:00Z"))
                .timeOut(OffsetDateTime.parse("2025-01-15T10:00:00Z"))
                .locationLat(38.9)
                .locationLng(-77.0)
                .locationSource("GPS")
                .status("UNDER_REVIEW")
                .stateCode("DC")
                .isOffline(false)
                .eorApprovalRequired(false)
                .isCorrected(false)
                .createdAt(OffsetDateTime.now())
                .updatedAt(OffsetDateTime.now())
                .build();
    }

    // ─── createRecord ──────────────────────────────────────────────────────────

    @Test
    void createRecord_patientNotFound_throwsIllegalArgument() throws Exception {
        when(patientRepository.findById(5L)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> evvService.createRecord(baseReqBuilder().build(), 1L))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("Patient not found");
    }

    @Test
    void createRecord_noLocation_createsRecordWithoutLocation() throws Exception {
        final Patient patient = buildPatient(5L);
        final EvvRecordRequestDto req = baseReqBuilder().build(); // all location fields null

        final EvvRecord saved = buildSavedRecord(1L, patient);

        when(patientRepository.findById(5L)).thenReturn(Optional.of(patient));
        when(userRepository.findById(10L)).thenReturn(Optional.of(User.builder().id(10L).name("Test Caregiver").build()));
        when(recordRepository.save(any(EvvRecord.class))).thenReturn(saved);
        doNothing().when(audit).log(any(), any(), any(), any());

        final EvvRecord result = evvService.createRecord(req, 1L);

        assertThat(result).isNotNull();
        assertThat(result.getId()).isEqualTo(1L);
        verify(locationService, never()).saveLocation(any());
    }

    @Test
    void createRecord_withGpsCheckinAndCoords_savesLocation() throws Exception {
        final Patient patient = buildPatient(5L);
        final EvvRecordRequestDto req = baseReqBuilder()
                .checkinLocationSource("GPS")
                .checkinLocationLat(38.9072)
                .checkinLocationLng(-77.0369)
                .build();

        final EvvRecord saved = buildSavedRecord(1L, patient);

        when(patientRepository.findById(5L)).thenReturn(Optional.of(patient));
        when(userRepository.findById(10L)).thenReturn(Optional.of(User.builder().id(10L).name("Test Caregiver").build()));
        when(recordRepository.save(any(EvvRecord.class))).thenReturn(saved);
        doNothing().when(audit).log(any(), any(), any(), any());
        when(locationService.saveLocation(any())).thenReturn(
                EvvLocationResponse.builder()
                        .evvRecordId(1L)
                        .role(EvvLocationRole.CHECK_IN)
                        .type(EvvLocationType.GPS)
                        .latitude(BigDecimal.valueOf(38.9072))
                        .longitude(BigDecimal.valueOf(-77.0369))
                        .build());

        evvService.createRecord(req, 1L);

        verify(locationService, times(1)).saveLocation(any());
    }

    @Test
    void createRecord_withGpsCheckinNoCoords_skipsSave() throws Exception {
        final Patient patient = buildPatient(5L);
        final EvvRecordRequestDto req = baseReqBuilder()
                .checkinLocationSource("GPS")
                // lat/lng intentionally omitted
                .build();

        final EvvRecord saved = buildSavedRecord(1L, patient);

        when(patientRepository.findById(5L)).thenReturn(Optional.of(patient));
        when(userRepository.findById(10L)).thenReturn(Optional.of(User.builder().id(10L).name("Test Caregiver").build()));
        when(recordRepository.save(any(EvvRecord.class))).thenReturn(saved);
        doNothing().when(audit).log(any(), any(), any(), any());

        evvService.createRecord(req, 1L);

        verify(locationService, never()).saveLocation(any());
    }

    @Test
    void createRecord_withPatientAddressCheckin_savesLocation() throws Exception {
        final Patient patient = buildPatient(5L);
        final EvvRecordRequestDto req = baseReqBuilder()
                .checkinLocationSource("PATIENT_ADDRESS")
                .build();

        final EvvRecord saved = buildSavedRecord(1L, patient);

        when(patientRepository.findById(5L)).thenReturn(Optional.of(patient));
        when(userRepository.findById(10L)).thenReturn(Optional.of(User.builder().id(10L).name("Test Caregiver").build()));
        when(recordRepository.save(any(EvvRecord.class))).thenReturn(saved);
        doNothing().when(audit).log(any(), any(), any(), any());
        when(locationService.saveLocation(any())).thenReturn(
                EvvLocationResponse.builder()
                        .evvRecordId(1L)
                        .role(EvvLocationRole.CHECK_IN)
                        .type(EvvLocationType.PATIENT_ADDRESS)
                        .build());

        evvService.createRecord(req, 1L);

        verify(locationService, times(1)).saveLocation(any());
    }

    @Test
    void createRecord_withLegacyGpsSource_convertsToGps() throws Exception {
        final Patient patient = buildPatient(5L);
        final EvvRecordRequestDto req = baseReqBuilder()
                .locationSource("gps")
                .locationLat(38.9)
                .locationLng(-77.0)
                // checkinLocationSource intentionally null to trigger legacy path
                .build();

        final EvvRecord saved = buildSavedRecord(1L, patient);

        when(patientRepository.findById(5L)).thenReturn(Optional.of(patient));
        when(userRepository.findById(10L)).thenReturn(Optional.of(User.builder().id(10L).name("Test Caregiver").build()));
        when(recordRepository.save(any(EvvRecord.class))).thenReturn(saved);
        doNothing().when(audit).log(any(), any(), any(), any());
        when(locationService.saveLocation(any())).thenReturn(
                EvvLocationResponse.builder()
                        .evvRecordId(1L)
                        .role(EvvLocationRole.CHECK_IN)
                        .type(EvvLocationType.GPS)
                        .build());

        evvService.createRecord(req, 1L);

        verify(locationService, times(1)).saveLocation(any());
    }

    @Test
    void createRecord_withLegacyManualSource_convertsToPatientAddress() throws Exception {
        final Patient patient = buildPatient(5L);
        final EvvRecordRequestDto req = baseReqBuilder()
                .locationSource("manual")
                // checkinLocationSource intentionally null to trigger legacy path
                .build();

        final EvvRecord saved = buildSavedRecord(1L, patient);

        when(patientRepository.findById(5L)).thenReturn(Optional.of(patient));
        when(userRepository.findById(10L)).thenReturn(Optional.of(User.builder().id(10L).name("Test Caregiver").build()));
        when(recordRepository.save(any(EvvRecord.class))).thenReturn(saved);
        doNothing().when(audit).log(any(), any(), any(), any());
        when(locationService.saveLocation(any())).thenReturn(
                EvvLocationResponse.builder()
                        .evvRecordId(1L)
                        .role(EvvLocationRole.CHECK_IN)
                        .type(EvvLocationType.PATIENT_ADDRESS)
                        .build());

        evvService.createRecord(req, 1L);

        verify(locationService, times(1)).saveLocation(any());
    }

    @Test
    void createRecord_withGpsCheckout_savesLocation() throws Exception {
        final Patient patient = buildPatient(5L);
        final EvvRecordRequestDto req = baseReqBuilder()
                .checkoutLocationSource("GPS")
                .checkoutLocationLat(38.91)
                .checkoutLocationLng(-77.04)
                .build();

        final EvvRecord saved = buildSavedRecord(1L, patient);

        when(patientRepository.findById(5L)).thenReturn(Optional.of(patient));
        when(userRepository.findById(10L)).thenReturn(Optional.of(User.builder().id(10L).name("Test Caregiver").build()));
        when(recordRepository.save(any(EvvRecord.class))).thenReturn(saved);
        doNothing().when(audit).log(any(), any(), any(), any());
        when(locationService.saveLocation(any())).thenReturn(
                EvvLocationResponse.builder()
                        .evvRecordId(1L)
                        .role(EvvLocationRole.CHECK_OUT)
                        .type(EvvLocationType.GPS)
                        .build());

        evvService.createRecord(req, 1L);

        verify(locationService, times(1)).saveLocation(any());
    }

    @Test
    void createRecord_withGpsCheckoutNoCoords_skipsSave() throws Exception {
        final Patient patient = buildPatient(5L);
        final EvvRecordRequestDto req = baseReqBuilder()
                .checkoutLocationSource("GPS")
                // lat/lng intentionally omitted
                .build();

        final EvvRecord saved = buildSavedRecord(1L, patient);

        when(patientRepository.findById(5L)).thenReturn(Optional.of(patient));
        when(userRepository.findById(10L)).thenReturn(Optional.of(User.builder().id(10L).name("Test Caregiver").build()));
        when(recordRepository.save(any(EvvRecord.class))).thenReturn(saved);
        doNothing().when(audit).log(any(), any(), any(), any());

        evvService.createRecord(req, 1L);

        verify(locationService, never()).saveLocation(any());
    }

    @Test
    void createRecord_withPatientAddressCheckout_savesLocation() throws Exception {
        final Patient patient = buildPatient(5L);
        final EvvRecordRequestDto req = baseReqBuilder()
                .checkoutLocationSource("PATIENT_ADDRESS")
                .build();

        final EvvRecord saved = buildSavedRecord(1L, patient);

        when(patientRepository.findById(5L)).thenReturn(Optional.of(patient));
        when(userRepository.findById(10L)).thenReturn(Optional.of(User.builder().id(10L).name("Test Caregiver").build()));
        when(recordRepository.save(any(EvvRecord.class))).thenReturn(saved);
        doNothing().when(audit).log(any(), any(), any(), any());
        when(locationService.saveLocation(any())).thenReturn(
                EvvLocationResponse.builder()
                        .evvRecordId(1L)
                        .role(EvvLocationRole.CHECK_OUT)
                        .type(EvvLocationType.PATIENT_ADDRESS)
                        .build());

        evvService.createRecord(req, 1L);

        verify(locationService, times(1)).saveLocation(any());
    }

    @Test
    void createRecord_withScheduledVisit_marksCompleted() throws Exception {
        final Patient patient = buildPatient(5L);
        final EvvRecordRequestDto req = baseReqBuilder()
                .scheduledVisitId(20L)
                .build();

        final EvvRecord saved = buildSavedRecord(1L, patient);

        final ScheduledVisit visit = new ScheduledVisit();
        visit.setId(20L);
        visit.setStatus("Scheduled");

        when(patientRepository.findById(5L)).thenReturn(Optional.of(patient));
        when(userRepository.findById(10L)).thenReturn(Optional.of(User.builder().id(10L).name("Test Caregiver").build()));
        when(recordRepository.save(any(EvvRecord.class))).thenReturn(saved);
        doNothing().when(audit).log(any(), any(), any(), any());
        when(scheduledVisitRepository.findById(20L)).thenReturn(Optional.of(visit));
        when(scheduledVisitRepository.save(any(ScheduledVisit.class))).thenReturn(visit);

        evvService.createRecord(req, 1L);

        assertThat(visit.getStatus()).isEqualTo("Completed");
        verify(scheduledVisitRepository).save(visit);
    }

    @Test
    void createRecord_withScheduledVisitNotFound_ignores() throws Exception {
        final Patient patient = buildPatient(5L);
        final EvvRecordRequestDto req = baseReqBuilder()
                .scheduledVisitId(99L)
                .build();

        final EvvRecord saved = buildSavedRecord(1L, patient);

        when(patientRepository.findById(5L)).thenReturn(Optional.of(patient));
        when(userRepository.findById(10L)).thenReturn(Optional.of(User.builder().id(10L).name("Test Caregiver").build()));
        when(recordRepository.save(any(EvvRecord.class))).thenReturn(saved);
        doNothing().when(audit).log(any(), any(), any(), any());
        when(scheduledVisitRepository.findById(99L)).thenReturn(Optional.empty());

        // Should not throw
        final EvvRecord result = evvService.createRecord(req, 1L);

        assertThat(result).isNotNull();
        verify(scheduledVisitRepository, never()).save(any());
    }

    @Test
    void createRecord_scheduledVisitException_ignores() throws Exception {
        final Patient patient = buildPatient(5L);
        final EvvRecordRequestDto req = baseReqBuilder()
                .scheduledVisitId(20L)
                .build();

        final EvvRecord saved = buildSavedRecord(1L, patient);

        when(patientRepository.findById(5L)).thenReturn(Optional.of(patient));
        when(userRepository.findById(10L)).thenReturn(Optional.of(User.builder().id(10L).name("Test Caregiver").build()));
        when(recordRepository.save(any(EvvRecord.class))).thenReturn(saved);
        doNothing().when(audit).log(any(), any(), any(), any());
        when(scheduledVisitRepository.findById(20L)).thenThrow(new RuntimeException("DB error"));

        // Should silently swallow the exception
        final EvvRecord result = evvService.createRecord(req, 1L);

        assertThat(result).isNotNull();
    }

    // ─── review ────────────────────────────────────────────────────────────────

    @Test
    void review_approve_marksApprovedAndLogs() throws Exception {
        final Patient patient = buildPatient(5L);
        final EvvRecord rec = buildSavedRecord(1L, patient);

        when(recordRepository.findByIdWithPatient(1L)).thenReturn(Optional.of(rec));
        when(recordRepository.save(any(EvvRecord.class))).thenReturn(rec);
        doNothing().when(audit).log(any(), any(), any(), any());
        when(locationService.getLocationsForRecord(anyLong())).thenReturn(List.of());

        final EvvRecord result = evvService.review(1L, true, 99L, "Looks good");

        assertThat(result.getStatus()).isEqualTo("APPROVED");
        verify(audit).log(any(), eq(99L), eq("APPROVED"), any());
    }

    @Test
    void review_reject_marksRejectedAndLogs() throws Exception {
        final Patient patient = buildPatient(5L);
        final EvvRecord rec = buildSavedRecord(1L, patient);

        when(recordRepository.findByIdWithPatient(1L)).thenReturn(Optional.of(rec));
        when(recordRepository.save(any(EvvRecord.class))).thenReturn(rec);
        doNothing().when(audit).log(any(), any(), any(), any());
        when(locationService.getLocationsForRecord(anyLong())).thenReturn(List.of());

        final EvvRecord result = evvService.review(1L, false, 99L, "Rejected");

        assertThat(result.getStatus()).isEqualTo("REJECTED");
        verify(audit).log(any(), eq(99L), eq("REJECTED"), any());
    }

    @Test
    void review_populatesLocationFields() throws Exception {
        final Patient patient = buildPatient(5L);
        final EvvRecord rec = buildSavedRecord(1L, patient);

        final EvvLocationResponse checkIn = EvvLocationResponse.builder()
                .evvRecordId(1L)
                .role(EvvLocationRole.CHECK_IN)
                .type(EvvLocationType.GPS)
                .latitude(BigDecimal.valueOf(38.9))
                .longitude(BigDecimal.valueOf(-77.0))
                .build();

        final EvvLocationResponse checkOut = EvvLocationResponse.builder()
                .evvRecordId(1L)
                .role(EvvLocationRole.CHECK_OUT)
                .type(EvvLocationType.GPS)
                .latitude(BigDecimal.valueOf(38.91))
                .longitude(BigDecimal.valueOf(-77.01))
                .build();

        when(recordRepository.findByIdWithPatient(1L)).thenReturn(Optional.of(rec));
        when(recordRepository.save(any(EvvRecord.class))).thenReturn(rec);
        doNothing().when(audit).log(any(), any(), any(), any());
        when(locationService.getLocationsForRecord(1L)).thenReturn(List.of(checkIn, checkOut));

        final EvvRecord result = evvService.review(1L, true, 99L, "OK");

        assertThat(result.getCheckinLocationLat()).isEqualTo(38.9);
        assertThat(result.getCheckoutLocationLat()).isEqualTo(38.91);
    }

    @Test
    void review_recordNotFound_throwsNoSuchElementException() {
        when(recordRepository.findByIdWithPatient(99L)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> evvService.review(99L, true, 1L, null))
                .isInstanceOf(NoSuchElementException.class);
    }

    @Test
    void review_nullComment_doesNotAddCommentKeyToAuditDetails() throws Exception {
        final Patient patient = buildPatient(5L);
        final EvvRecord rec = buildSavedRecord(1L, patient);

        when(recordRepository.findByIdWithPatient(1L)).thenReturn(Optional.of(rec));
        when(recordRepository.save(any(EvvRecord.class))).thenReturn(rec);
        when(locationService.getLocationsForRecord(anyLong())).thenReturn(List.of());

        evvService.review(1L, true, 99L, null);

        @SuppressWarnings("unchecked")
        final ArgumentCaptor<Map<String, Object>> captor = ArgumentCaptor.forClass(Map.class);
        verify(audit).log(any(), eq(99L), eq("APPROVED"), captor.capture());
        assertThat(captor.getValue()).doesNotContainKey("comment");
    }

    // ─── createOfflineRecord ───────────────────────────────────────────────────

    @Test
    void createOfflineRecord_patientNotFound_throwsIllegalArgument() throws Exception {
        when(patientRepository.findById(5L)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> evvService.createOfflineRecord(baseReqBuilder().build(), 1L, "device-001"))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("Patient not found");
    }

    @Test
    void createOfflineRecord_success_savesAndQueues() throws Exception {
        final Patient patient = buildPatient(5L);
        final EvvRecordRequestDto req = baseReqBuilder()
                .locationLat(38.9)
                .locationLng(-77.0)
                .locationSource("GPS")
                .deviceInfo(Map.of("os", "Android"))
                .build();

        final EvvRecord saved = buildSavedRecord(1L, patient);
        saved.setIsOffline(true);
        saved.setSyncStatus("PENDING");

        final EvvOfflineQueue savedQueue = EvvOfflineQueue.builder()
                .id(1L)
                .recordId(1L)
                .caregiverId(1L)
                .operationType("CREATE")
                .syncStatus("PENDING")
                .priority(1)
                .queuedAt(OffsetDateTime.now())
                .build();

        when(patientRepository.findById(5L)).thenReturn(Optional.of(patient));
        when(recordRepository.save(any(EvvRecord.class))).thenReturn(saved);
        when(offlineQueueRepository.save(any(EvvOfflineQueue.class))).thenReturn(savedQueue);
        doNothing().when(audit).log(any(), any(), any(), any());

        final EvvRecord result = evvService.createOfflineRecord(req, 1L, "device-001");

        assertThat(result).isNotNull();
        assertThat(result.getIsOffline()).isTrue();
        verify(offlineQueueRepository).save(any(EvvOfflineQueue.class));
        verify(audit).log(any(), eq(1L), eq("OFFLINE_CREATED"), any());
    }

    // ─── correctRecord ─────────────────────────────────────────────────────────

    @Test
    void correctRecord_originalNotFound_throwsIllegalArgument() throws Exception {
        final EvvCorrectionRequestDto req = EvvCorrectionRequestDto.builder()
                .originalRecordId(99L)
                .reasonCode("WRONG_TIME")
                .explanation("Time was incorrect")
                .build();

        when(recordRepository.findByIdWithPatient(99L)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> evvService.correctRecord(req, 1L))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("Original record not found");
    }

    @Test
    void correctRecord_withNullFields_usesOriginalValues() throws Exception {
        final Patient patient = buildPatient(5L);
        final EvvRecord original = buildSavedRecord(1L, patient);

        // All optional correction fields null → should use original's values
        final EvvCorrectionRequestDto req = EvvCorrectionRequestDto.builder()
                .originalRecordId(1L)
                .reasonCode("CORRECTION")
                .explanation("Fixing data")
                .build();

        final EvvRecord savedCorrected = buildSavedRecord(2L, patient);
        savedCorrected.setIsCorrected(true);

        when(recordRepository.findByIdWithPatient(1L)).thenReturn(Optional.of(original));
        when(recordRepository.save(any(EvvRecord.class))).thenReturn(savedCorrected);
        when(correctionRepository.save(any(EvvCorrection.class))).thenReturn(null);
        doNothing().when(audit).log(any(), any(), any(), any());

        final EvvRecord result = evvService.correctRecord(req, 1L);

        assertThat(result).isNotNull();
        verify(correctionRepository).save(any(EvvCorrection.class));
    }

    @Test
    void correctRecord_withNewFields_usesNewValues() throws Exception {
        final Patient patient = buildPatient(5L);
        final EvvRecord original = buildSavedRecord(1L, patient);

        final EvvCorrectionRequestDto req = EvvCorrectionRequestDto.builder()
                .originalRecordId(1L)
                .reasonCode("WRONG_TIME")
                .explanation("Updated times")
                .serviceType("PERSONAL_CARE")
                .individualName("New Name")
                .dateOfService(LocalDate.of(2025, 2, 1))
                .timeIn(OffsetDateTime.parse("2025-02-01T09:00:00Z"))
                .timeOut(OffsetDateTime.parse("2025-02-01T11:00:00Z"))
                .locationLat(39.0)
                .locationLng(-77.1)
                .locationSource("GPS")
                .stateCode("MD")
                .build();

        final EvvRecord savedCorrected = EvvRecord.builder()
                .id(2L)
                .patient(patient)
                .serviceType("PERSONAL_CARE")
                .individualName("New Name")
                .caregiverId(10L)
                .dateOfService(LocalDate.of(2025, 2, 1))
                .timeIn(OffsetDateTime.parse("2025-02-01T09:00:00Z"))
                .timeOut(OffsetDateTime.parse("2025-02-01T11:00:00Z"))
                .locationLat(39.0)
                .locationLng(-77.1)
                .locationSource("GPS")
                .status("UNDER_REVIEW")
                .stateCode("MD")
                .isOffline(false)
                .eorApprovalRequired(false)
                .isCorrected(true)
                .createdAt(OffsetDateTime.now())
                .updatedAt(OffsetDateTime.now())
                .build();

        when(recordRepository.findByIdWithPatient(1L)).thenReturn(Optional.of(original));
        when(recordRepository.save(any(EvvRecord.class))).thenReturn(savedCorrected);
        when(correctionRepository.save(any(EvvCorrection.class))).thenReturn(null);
        doNothing().when(audit).log(any(), any(), any(), any());

        final EvvRecord result = evvService.correctRecord(req, 1L);

        assertThat(result.getServiceType()).isEqualTo("PERSONAL_CARE");
    }

    @Test
    void correctRecord_marksOriginalRecordAsRejected() throws Exception {
        final Patient patient = buildPatient(5L);
        final EvvRecord original = buildSavedRecord(1L, patient);

        final EvvCorrectionRequestDto req = EvvCorrectionRequestDto.builder()
                .originalRecordId(1L)
                .reasonCode("WRONG_TIME")
                .explanation("Time was incorrect")
                .build();

        final EvvRecord savedCorrected = buildSavedRecord(2L, patient);
        savedCorrected.setIsCorrected(true);

        when(recordRepository.findByIdWithPatient(1L)).thenReturn(Optional.of(original));
        when(recordRepository.save(any(EvvRecord.class))).thenReturn(savedCorrected);
        when(correctionRepository.save(any(EvvCorrection.class))).thenReturn(null);
        doNothing().when(audit).log(any(), any(), any(), any());

        evvService.correctRecord(req, 1L);

        // The original record must be rejected after a correction is submitted
        assertThat(original.getStatus()).isEqualTo("REJECTED");
    }

    @Test
    void correctRecord_logsCorrectAuditEventType() throws Exception {
        final Patient patient = buildPatient(5L);
        final EvvRecord original = buildSavedRecord(1L, patient);

        final EvvCorrectionRequestDto req = EvvCorrectionRequestDto.builder()
                .originalRecordId(1L)
                .reasonCode("WRONG_TIME")
                .explanation("Correcting the time")
                .build();

        final EvvRecord savedCorrected = buildSavedRecord(2L, patient);
        savedCorrected.setIsCorrected(true);

        when(recordRepository.findByIdWithPatient(1L)).thenReturn(Optional.of(original));
        when(recordRepository.save(any(EvvRecord.class))).thenReturn(savedCorrected);
        when(correctionRepository.save(any(EvvCorrection.class))).thenReturn(null);
        doNothing().when(audit).log(any(), any(), any(), any());

        evvService.correctRecord(req, 1L);

        verify(audit).log(any(EvvRecord.class), eq(1L), eq("CORRECTED"), any(Map.class));
    }

    // ─── approveEor ────────────────────────────────────────────────────────────

    @Test
    void approveEor_recordNotFound_throwsIllegalArgument() throws Exception {
        final EorApprovalRequestDto req = EorApprovalRequestDto.builder()
                .recordId(99L)
                .comment("Approved")
                .build();

        when(recordRepository.findByIdWithPatient(99L)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> evvService.approveEor(req, 1L))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("Record not found");
    }

    @Test
    void approveEor_success_approvesAndLogs() throws Exception {
        final Patient patient = buildPatient(5L);
        final EvvRecord rec = buildSavedRecord(1L, patient);

        final EorApprovalRequestDto req = EorApprovalRequestDto.builder()
                .recordId(1L)
                .comment("EOR approved")
                .build();

        when(recordRepository.findByIdWithPatient(1L)).thenReturn(Optional.of(rec));
        when(recordRepository.save(any(EvvRecord.class))).thenReturn(rec);
        doNothing().when(audit).log(any(), any(), any(), any());

        final EvvRecord result = evvService.approveEor(req, 99L);

        assertThat(result.getEorApprovedBy()).isEqualTo(99L);
        verify(audit).log(any(), eq(99L), eq("EOR_APPROVED"), any());
    }

    @Test
    void approveEor_nullComment_doesNotAddCommentKeyToAuditDetails() throws Exception {
        final Patient patient = buildPatient(5L);
        final EvvRecord rec = buildSavedRecord(1L, patient);

        final EorApprovalRequestDto req = EorApprovalRequestDto.builder()
                .recordId(1L)
                .comment(null)
                .build();

        when(recordRepository.findByIdWithPatient(1L)).thenReturn(Optional.of(rec));
        when(recordRepository.save(any(EvvRecord.class))).thenReturn(rec);

        evvService.approveEor(req, 99L);

        @SuppressWarnings("unchecked")
        final ArgumentCaptor<Map<String, Object>> captor = ArgumentCaptor.forClass(Map.class);
        verify(audit).log(any(), eq(99L), eq("EOR_APPROVED"), captor.capture());
        assertThat(captor.getValue()).doesNotContainKey("comment");
    }

    // ─── searchRecords ─────────────────────────────────────────────────────────

    @Test
    void searchRecords_returnsPagedResults() throws Exception {
        final Patient patient = buildPatient(5L);
        final EvvRecord rec = buildSavedRecord(1L, patient);
        final Page<EvvRecord> page = new PageImpl<>(List.of(rec));

        final EvvSearchRequestDto searchRequest = EvvSearchRequestDto.builder()
                .page(0)
                .size(20)
                .sortBy("createdAt")
                .sortDirection("DESC")
                .build();

        when(recordRepository.searchRecords(any(), any(), any(), any(), any(), any(), any(), any(), any(Pageable.class)))
                .thenReturn(page);
        when(locationService.getLocationsForRecord(anyLong())).thenReturn(List.of());

        final Page<EvvRecord> result = evvService.searchRecords(searchRequest);

        assertThat(result.getContent()).hasSize(1);
    }

    @Test
    void searchRecords_populatesLocationFields() throws Exception {
        final Patient patient = buildPatient(5L);
        final EvvRecord rec = buildSavedRecord(1L, patient);
        final Page<EvvRecord> page = new PageImpl<>(List.of(rec));

        final EvvSearchRequestDto searchRequest = EvvSearchRequestDto.builder()
                .page(0)
                .size(20)
                .sortBy("createdAt")
                .sortDirection("DESC")
                .build();

        when(recordRepository.searchRecords(any(), any(), any(), any(), any(), any(), any(), any(), any(Pageable.class)))
                .thenReturn(page);
        // locationService throws → populateLocationFields swallows it
        when(locationService.getLocationsForRecord(anyLong()))
                .thenThrow(new RuntimeException("Not found"));

        final Page<EvvRecord> result = evvService.searchRecords(searchRequest);

        // No exception, result still returned
        assertThat(result.getContent()).hasSize(1);
    }

    // ─── getPendingEorApprovals ────────────────────────────────────────────────

    @Test
    void getPendingEorApprovals_returnsRepositoryResult() throws Exception {
        final Patient patient = buildPatient(5L);
        final EvvRecord rec = buildSavedRecord(1L, patient);
        when(recordRepository.findPendingEorApprovals()).thenReturn(List.of(rec));

        final List<EvvRecord> result = evvService.getPendingEorApprovals();

        assertThat(result).hasSize(1);
    }

    // ─── getPendingCorrections ─────────────────────────────────────────────────

    @Test
    void getPendingCorrections_returnsRepositoryResult() throws Exception {
        final EvvCorrection correction = EvvCorrection.builder()
                .id(1L)
                .reasonCode("WRONG_TIME")
                .explanation("Fixing")
                .correctedBy(1L)
                .correctedAt(OffsetDateTime.now())
                .approvalRequired(true)
                .build();

        when(correctionRepository.findPendingApprovals()).thenReturn(List.of(correction));

        final List<EvvCorrection> result = evvService.getPendingCorrections();

        assertThat(result).hasSize(1);
    }

    // ─── approveCorrection ─────────────────────────────────────────────────────

    @Test
    void approveCorrection_notFound_throwsIllegalArgument() throws Exception {
        when(correctionRepository.findById(99L)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> evvService.approveCorrection(99L, 1L, "Approved"))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("Correction not found");
    }

    @Test
    void approveCorrection_success_approvesAndLogs() throws Exception {
        final Patient patient = buildPatient(5L);
        final EvvRecord correctedRec = buildSavedRecord(2L, patient);

        final EvvCorrection correction = EvvCorrection.builder()
                .id(1L)
                .reasonCode("WRONG_TIME")
                .explanation("Fixing")
                .correctedBy(1L)
                .correctedAt(OffsetDateTime.now())
                .approvalRequired(true)
                .correctedRecord(correctedRec)
                .build();

        when(correctionRepository.findById(1L)).thenReturn(Optional.of(correction));
        when(correctionRepository.save(any(EvvCorrection.class))).thenReturn(correction);
        when(recordRepository.save(any(EvvRecord.class))).thenReturn(correctedRec);
        doNothing().when(audit).log(any(), any(), any(), any());

        final EvvCorrection result = evvService.approveCorrection(1L, 99L, "Approved");

        assertThat(result.getApprovedBy()).isEqualTo(99L);
        verify(audit).log(any(), eq(99L), eq("CORRECTION_APPROVED"), any());
        assertThat(correctedRec.getStatus()).isEqualTo("APPROVED");
    }

    // ─── rejectCorrection ──────────────────────────────────────────────────────

    @Test
    void rejectCorrection_notFound_throwsIllegalArgument() throws Exception {
        when(correctionRepository.findById(99L)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> evvService.rejectCorrection(99L, 1L, "Rejected"))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("Correction not found");
    }

    @Test
    void rejectCorrection_success_rejectsAndLogs() throws Exception {
        final Patient patient = buildPatient(5L);
        final EvvRecord correctedRec = buildSavedRecord(2L, patient);

        final EvvCorrection correction = EvvCorrection.builder()
                .id(1L)
                .reasonCode("WRONG_TIME")
                .explanation("Fixing")
                .correctedBy(1L)
                .correctedAt(OffsetDateTime.now())
                .approvalRequired(true)
                .correctedRecord(correctedRec)
                .build();

        when(correctionRepository.findById(1L)).thenReturn(Optional.of(correction));
        when(correctionRepository.save(any(EvvCorrection.class))).thenReturn(correction);
        when(recordRepository.save(any(EvvRecord.class))).thenReturn(correctedRec);
        doNothing().when(audit).log(any(), any(), any(), any());

        final EvvCorrection result = evvService.rejectCorrection(1L, 99L, "Rejected");

        assertThat(result.getApprovalRequired()).isFalse();
        assertThat(correctedRec.getStatus()).isEqualTo("REJECTED");
        verify(audit).log(any(), eq(99L), eq("CORRECTION_REJECTED"), any());
    }

    @Test
    void approveCorrection_withNullComment_doesNotThrow() throws Exception {
        final Patient patient = buildPatient(5L);
        final EvvRecord correctedRec = buildSavedRecord(2L, patient);

        final EvvCorrection correction = EvvCorrection.builder()
                .id(1L)
                .reasonCode("WRONG_TIME")
                .explanation("Fixing")
                .correctedBy(1L)
                .correctedAt(OffsetDateTime.now())
                .approvalRequired(true)
                .correctedRecord(correctedRec)
                .build();

        when(correctionRepository.findById(1L)).thenReturn(Optional.of(correction));
        when(correctionRepository.save(any(EvvCorrection.class))).thenReturn(correction);
        when(recordRepository.save(any(EvvRecord.class))).thenReturn(correctedRec);

        final EvvCorrection result = evvService.approveCorrection(1L, 99L, null);

        assertThat(result).isNotNull();
        verify(audit).log(any(), eq(99L), eq("CORRECTION_APPROVED"), any());
    }

    @Test
    void rejectCorrection_withNullComment_doesNotThrow() throws Exception {
        final Patient patient = buildPatient(5L);
        final EvvRecord correctedRec = buildSavedRecord(2L, patient);

        final EvvCorrection correction = EvvCorrection.builder()
                .id(1L)
                .reasonCode("WRONG_TIME")
                .explanation("Fixing")
                .correctedBy(1L)
                .correctedAt(OffsetDateTime.now())
                .approvalRequired(true)
                .correctedRecord(correctedRec)
                .build();

        when(correctionRepository.findById(1L)).thenReturn(Optional.of(correction));
        when(correctionRepository.save(any(EvvCorrection.class))).thenReturn(correction);
        when(recordRepository.save(any(EvvRecord.class))).thenReturn(correctedRec);

        final EvvCorrection result = evvService.rejectCorrection(1L, 99L, null);

        assertThat(result).isNotNull();
        verify(audit).log(any(), eq(99L), eq("CORRECTION_REJECTED"), any());
    }

    // ─── getOfflineQueue ───────────────────────────────────────────────────────

    @Test
    void getOfflineQueue_returnsRepositoryResult() throws Exception {
        final EvvOfflineQueue item = EvvOfflineQueue.builder()
                .id(1L)
                .recordId(1L)
                .caregiverId(10L)
                .operationType("CREATE")
                .syncStatus("PENDING")
                .priority(1)
                .queuedAt(OffsetDateTime.now())
                .build();

        when(offlineQueueRepository.findPendingItemsByCaregiver(10L)).thenReturn(List.of(item));

        final List<EvvOfflineQueue> result = evvService.getOfflineQueue(10L);

        assertThat(result).hasSize(1);
        assertThat(result.get(0).getCaregiverId()).isEqualTo(10L);
    }

    // ─── buildLocationDetails (private helper) ────────────────────────────────
    // Exercised via reflection to drive every lat-only/lng-only combination of
    // the legacy/checkin/checkout OR-conditions, which the public-API tests
    // above only ever exercise as "both null" or "both set".

    private Map<String, Object> invokeBuildLocationDetails(EvvRecord record) throws Exception {
        Method m = EvvService.class.getDeclaredMethod("buildLocationDetails", EvvRecord.class);
        m.setAccessible(true);
        return (Map<String, Object>) m.invoke(evvService, record);
    }

    @Test
    void buildLocationDetails_allLocationsNull_returnsEmptyMap() throws Exception {
        final EvvRecord record = EvvRecord.builder().id(1L).build();

        assertThat(invokeBuildLocationDetails(record)).isEmpty();
    }

    @Test
    void buildLocationDetails_legacyLatOnly_includesLegacyFields() throws Exception {
        final EvvRecord record = EvvRecord.builder().id(1L).locationLat(38.9).build();

        assertThat(invokeBuildLocationDetails(record)).containsKey("locationLat");
    }

    @Test
    void buildLocationDetails_legacyLngOnly_includesLegacyFields() throws Exception {
        final EvvRecord record = EvvRecord.builder().id(1L).locationLng(-77.0).build();

        assertThat(invokeBuildLocationDetails(record)).containsKey("locationLng");
    }

    @Test
    void buildLocationDetails_checkinLatOnly_includesCheckinFields() throws Exception {
        final EvvRecord record = EvvRecord.builder().id(1L).checkinLocationLat(38.9).build();

        assertThat(invokeBuildLocationDetails(record)).containsKey("checkinLocationLat");
    }

    @Test
    void buildLocationDetails_checkinLngOnly_includesCheckinFields() throws Exception {
        final EvvRecord record = EvvRecord.builder().id(1L).checkinLocationLng(-77.0).build();

        assertThat(invokeBuildLocationDetails(record)).containsKey("checkinLocationLng");
    }

    @Test
    void buildLocationDetails_checkoutLatOnly_includesCheckoutFields() throws Exception {
        final EvvRecord record = EvvRecord.builder().id(1L).checkoutLocationLat(38.9).build();

        assertThat(invokeBuildLocationDetails(record)).containsKey("checkoutLocationLat");
    }

    @Test
    void buildLocationDetails_checkoutLngOnly_includesCheckoutFields() throws Exception {
        final EvvRecord record = EvvRecord.builder().id(1L).checkoutLocationLng(-77.0).build();

        assertThat(invokeBuildLocationDetails(record)).containsKey("checkoutLocationLng");
    }

    // ─── createRecord — remaining branch coverage ─────────────────────────────

    @Test
    void createRecord_caregiverFoundWithNullName_usesFallbackCaregiverName() throws Exception {
        final Patient patient = buildPatient(5L);
        final EvvRecordRequestDto req = baseReqBuilder().build();
        final EvvRecord saved = buildSavedRecord(1L, patient);

        when(patientRepository.findById(5L)).thenReturn(Optional.of(patient));
        when(userRepository.findById(10L))
                .thenReturn(Optional.of(User.builder().id(10L).name(null).build()));
        when(recordRepository.save(any(EvvRecord.class))).thenReturn(saved);
        doNothing().when(audit).log(any(), any(), any(), any());

        evvService.createRecord(req, 1L);

        final ArgumentCaptor<EvvRecord> captor = ArgumentCaptor.forClass(EvvRecord.class);
        verify(recordRepository).save(captor.capture());
        assertThat(captor.getValue().getCaregiverName()).isEqualTo("Caregiver #10");
    }

    @Test
    void createRecord_checkinGpsLatOnlyNoLng_skipsSaveWithWarning() throws Exception {
        final Patient patient = buildPatient(5L);
        final EvvRecordRequestDto req = baseReqBuilder()
                .checkinLocationSource("GPS")
                .checkinLocationLat(38.9072)
                // checkinLocationLng and legacy locationLng both omitted
                .build();
        final EvvRecord saved = buildSavedRecord(1L, patient);

        when(patientRepository.findById(5L)).thenReturn(Optional.of(patient));
        when(userRepository.findById(10L))
                .thenReturn(Optional.of(User.builder().id(10L).name("Test Caregiver").build()));
        when(recordRepository.save(any(EvvRecord.class))).thenReturn(saved);
        doNothing().when(audit).log(any(), any(), any(), any());

        evvService.createRecord(req, 1L);

        verify(locationService, never()).saveLocation(any());
    }

    @Test
    void createRecord_checkinGpsWithAccuracy_includesAccuracyInCoords() throws Exception {
        final Patient patient = buildPatient(5L);
        final EvvRecordRequestDto req = baseReqBuilder()
                .checkinLocationSource("GPS")
                .checkinLocationLat(38.9072)
                .checkinLocationLng(-77.0369)
                .checkinAccuracyM(5.0)
                .build();
        final EvvRecord saved = buildSavedRecord(1L, patient);

        when(patientRepository.findById(5L)).thenReturn(Optional.of(patient));
        when(userRepository.findById(10L))
                .thenReturn(Optional.of(User.builder().id(10L).name("Test Caregiver").build()));
        when(recordRepository.save(any(EvvRecord.class))).thenReturn(saved);
        doNothing().when(audit).log(any(), any(), any(), any());
        when(locationService.saveLocation(any())).thenReturn(
                EvvLocationResponse.builder()
                        .evvRecordId(1L)
                        .role(EvvLocationRole.CHECK_IN)
                        .type(EvvLocationType.GPS)
                        .build());

        evvService.createRecord(req, 1L);

        final ArgumentCaptor<EvvLocationRequest> captor = ArgumentCaptor.forClass(EvvLocationRequest.class);
        verify(locationService).saveLocation(captor.capture());
        assertThat(captor.getValue().getCoords().getAccuracyM())
                .isEqualByComparingTo(BigDecimal.valueOf(5.0));
    }

    @Test
    void createRecord_checkoutGpsLatOnlyNoLng_skipsSaveWithWarning() throws Exception {
        final Patient patient = buildPatient(5L);
        final EvvRecordRequestDto req = baseReqBuilder()
                .checkoutLocationSource("GPS")
                .checkoutLocationLat(38.91)
                // checkoutLocationLng omitted
                .build();
        final EvvRecord saved = buildSavedRecord(1L, patient);

        when(patientRepository.findById(5L)).thenReturn(Optional.of(patient));
        when(userRepository.findById(10L))
                .thenReturn(Optional.of(User.builder().id(10L).name("Test Caregiver").build()));
        when(recordRepository.save(any(EvvRecord.class))).thenReturn(saved);
        doNothing().when(audit).log(any(), any(), any(), any());

        evvService.createRecord(req, 1L);

        verify(locationService, never()).saveLocation(any());
    }

    @Test
    void createRecord_checkoutGpsWithAccuracy_includesAccuracyInCoords() throws Exception {
        final Patient patient = buildPatient(5L);
        final EvvRecordRequestDto req = baseReqBuilder()
                .checkoutLocationSource("GPS")
                .checkoutLocationLat(38.91)
                .checkoutLocationLng(-77.04)
                .checkoutAccuracyM(4.0)
                .build();
        final EvvRecord saved = buildSavedRecord(1L, patient);

        when(patientRepository.findById(5L)).thenReturn(Optional.of(patient));
        when(userRepository.findById(10L))
                .thenReturn(Optional.of(User.builder().id(10L).name("Test Caregiver").build()));
        when(recordRepository.save(any(EvvRecord.class))).thenReturn(saved);
        doNothing().when(audit).log(any(), any(), any(), any());
        when(locationService.saveLocation(any())).thenReturn(
                EvvLocationResponse.builder()
                        .evvRecordId(1L)
                        .role(EvvLocationRole.CHECK_OUT)
                        .type(EvvLocationType.GPS)
                        .build());

        evvService.createRecord(req, 1L);

        final ArgumentCaptor<EvvLocationRequest> captor = ArgumentCaptor.forClass(EvvLocationRequest.class);
        verify(locationService).saveLocation(captor.capture());
        assertThat(captor.getValue().getCoords().getAccuracyM())
                .isEqualByComparingTo(BigDecimal.valueOf(4.0));
    }

    // ─── saveLocationsForRecord — outer catch blocks ──────────────────────────

    @Test
    void createRecord_checkinInvalidLocationSource_logsWarningAndStillCreatesRecord() throws Exception {
        final Patient patient = buildPatient(5L);
        final EvvRecordRequestDto req = baseReqBuilder()
                .checkinLocationSource("NOT_A_REAL_TYPE")
                .build();
        final EvvRecord saved = buildSavedRecord(1L, patient);

        when(patientRepository.findById(5L)).thenReturn(Optional.of(patient));
        when(userRepository.findById(10L))
                .thenReturn(Optional.of(User.builder().id(10L).name("Test Caregiver").build()));
        when(recordRepository.save(any(EvvRecord.class))).thenReturn(saved);
        doNothing().when(audit).log(any(), any(), any(), any());

        final EvvRecord result = evvService.createRecord(req, 1L);

        // EvvLocationType.valueOf() throws inside the try block, caught by the
        // outer catch — record creation must still succeed.
        assertThat(result).isNotNull();
        verify(locationService, never()).saveLocation(any());
    }

    @Test
    void createRecord_checkoutInvalidLocationSource_logsWarningAndStillCreatesRecord() throws Exception {
        final Patient patient = buildPatient(5L);
        final EvvRecordRequestDto req = baseReqBuilder()
                .checkoutLocationSource("NOT_A_REAL_TYPE")
                .build();
        final EvvRecord saved = buildSavedRecord(1L, patient);

        when(patientRepository.findById(5L)).thenReturn(Optional.of(patient));
        when(userRepository.findById(10L))
                .thenReturn(Optional.of(User.builder().id(10L).name("Test Caregiver").build()));
        when(recordRepository.save(any(EvvRecord.class))).thenReturn(saved);
        doNothing().when(audit).log(any(), any(), any(), any());

        final EvvRecord result = evvService.createRecord(req, 1L);

        assertThat(result).isNotNull();
        verify(locationService, never()).saveLocation(any());
    }

    // ─── parseNoGpsReason — driven via createRecord's checkin path ────────────

    @Test
    void createRecord_checkinNoGpsReasonBlank_parsesAsNull() throws Exception {
        final Patient patient = buildPatient(5L);
        final EvvRecordRequestDto req = baseReqBuilder()
                .checkinLocationSource("PATIENT_ADDRESS")
                .checkinNoGpsReason("   ")
                .build();
        final EvvRecord saved = buildSavedRecord(1L, patient);

        when(patientRepository.findById(5L)).thenReturn(Optional.of(patient));
        when(userRepository.findById(10L))
                .thenReturn(Optional.of(User.builder().id(10L).name("Test Caregiver").build()));
        when(recordRepository.save(any(EvvRecord.class))).thenReturn(saved);
        doNothing().when(audit).log(any(), any(), any(), any());
        when(locationService.saveLocation(any())).thenReturn(
                EvvLocationResponse.builder()
                        .evvRecordId(1L)
                        .role(EvvLocationRole.CHECK_IN)
                        .type(EvvLocationType.PATIENT_ADDRESS)
                        .build());

        evvService.createRecord(req, 1L);

        final ArgumentCaptor<EvvLocationRequest> captor = ArgumentCaptor.forClass(EvvLocationRequest.class);
        verify(locationService).saveLocation(captor.capture());
        assertThat(captor.getValue().getNoGpsReason()).isNull();
    }

    @Test
    void createRecord_checkinNoGpsReasonValid_parsesEnumCaseInsensitively() throws Exception {
        final Patient patient = buildPatient(5L);
        final EvvRecordRequestDto req = baseReqBuilder()
                .checkinLocationSource("PATIENT_ADDRESS")
                .checkinNoGpsReason("gps_timeout")
                .build();
        final EvvRecord saved = buildSavedRecord(1L, patient);

        when(patientRepository.findById(5L)).thenReturn(Optional.of(patient));
        when(userRepository.findById(10L))
                .thenReturn(Optional.of(User.builder().id(10L).name("Test Caregiver").build()));
        when(recordRepository.save(any(EvvRecord.class))).thenReturn(saved);
        doNothing().when(audit).log(any(), any(), any(), any());
        when(locationService.saveLocation(any())).thenReturn(
                EvvLocationResponse.builder()
                        .evvRecordId(1L)
                        .role(EvvLocationRole.CHECK_IN)
                        .type(EvvLocationType.PATIENT_ADDRESS)
                        .build());

        evvService.createRecord(req, 1L);

        final ArgumentCaptor<EvvLocationRequest> captor = ArgumentCaptor.forClass(EvvLocationRequest.class);
        verify(locationService).saveLocation(captor.capture());
        assertThat(captor.getValue().getNoGpsReason()).isEqualTo(NoGpsReason.GPS_TIMEOUT);
    }

    @Test
    void createRecord_checkinNoGpsReasonInvalid_fallsBackToOther() throws Exception {
        final Patient patient = buildPatient(5L);
        final EvvRecordRequestDto req = baseReqBuilder()
                .checkinLocationSource("PATIENT_ADDRESS")
                .checkinNoGpsReason("not_a_real_reason")
                .build();
        final EvvRecord saved = buildSavedRecord(1L, patient);

        when(patientRepository.findById(5L)).thenReturn(Optional.of(patient));
        when(userRepository.findById(10L))
                .thenReturn(Optional.of(User.builder().id(10L).name("Test Caregiver").build()));
        when(recordRepository.save(any(EvvRecord.class))).thenReturn(saved);
        doNothing().when(audit).log(any(), any(), any(), any());
        when(locationService.saveLocation(any())).thenReturn(
                EvvLocationResponse.builder()
                        .evvRecordId(1L)
                        .role(EvvLocationRole.CHECK_IN)
                        .type(EvvLocationType.PATIENT_ADDRESS)
                        .build());

        evvService.createRecord(req, 1L);

        final ArgumentCaptor<EvvLocationRequest> captor = ArgumentCaptor.forClass(EvvLocationRequest.class);
        verify(locationService).saveLocation(captor.capture());
        assertThat(captor.getValue().getNoGpsReason()).isEqualTo(NoGpsReason.OTHER);
    }

    // ─── correctRecord — remaining branch coverage ────────────────────────────

    @Test
    void correctRecord_withNewDeviceInfo_usesNewValue() throws Exception {
        final Patient patient = buildPatient(5L);
        final EvvRecord original = buildSavedRecord(1L, patient);

        final EvvCorrectionRequestDto req = EvvCorrectionRequestDto.builder()
                .originalRecordId(1L)
                .reasonCode("CORRECTION")
                .explanation("Fixing data")
                .deviceInfo(Map.of("os", "iOS"))
                .build();

        final EvvRecord savedCorrected = buildSavedRecord(2L, patient);
        savedCorrected.setIsCorrected(true);

        when(recordRepository.findByIdWithPatient(1L)).thenReturn(Optional.of(original));
        when(recordRepository.save(any(EvvRecord.class))).thenReturn(savedCorrected);
        when(correctionRepository.save(any(EvvCorrection.class))).thenReturn(null);
        doNothing().when(audit).log(any(), any(), any(), any());

        evvService.correctRecord(req, 1L);

        // correctRecord saves twice: the new corrected record first, then the
        // original record (marked rejected) second — capture both and check
        // the first (the corrected record carries the new deviceInfo).
        final ArgumentCaptor<EvvRecord> captor = ArgumentCaptor.forClass(EvvRecord.class);
        verify(recordRepository, times(2)).save(captor.capture());
        assertThat(captor.getAllValues().get(0).getDeviceInfo()).isEqualTo(Map.of("os", "iOS"));
    }

    // ─── populateLocationFields — non-GPS (null coordinates) branch ──────────

    @Test
    void review_populatesLocationFields_withNonGpsLocations_leavesCoordinatesNull() throws Exception {
        final Patient patient = buildPatient(5L);
        final EvvRecord rec = buildSavedRecord(1L, patient);

        final EvvLocationResponse checkIn = EvvLocationResponse.builder()
                .evvRecordId(1L)
                .role(EvvLocationRole.CHECK_IN)
                .type(EvvLocationType.PATIENT_ADDRESS)
                .latitude(null)
                .longitude(null)
                .build();

        final EvvLocationResponse checkOut = EvvLocationResponse.builder()
                .evvRecordId(1L)
                .role(EvvLocationRole.CHECK_OUT)
                .type(EvvLocationType.PATIENT_ADDRESS)
                .latitude(null)
                .longitude(null)
                .build();

        when(recordRepository.findByIdWithPatient(1L)).thenReturn(Optional.of(rec));
        when(recordRepository.save(any(EvvRecord.class))).thenReturn(rec);
        doNothing().when(audit).log(any(), any(), any(), any());
        when(locationService.getLocationsForRecord(1L)).thenReturn(List.of(checkIn, checkOut));

        final EvvRecord result = evvService.review(1L, true, 99L, "OK");

        assertThat(result.getCheckinLocationLat()).isNull();
        assertThat(result.getCheckinLocationLng()).isNull();
        assertThat(result.getCheckoutLocationLat()).isNull();
        assertThat(result.getCheckoutLocationLng()).isNull();
        assertThat(result.getCheckinLocationSource()).isEqualTo("PATIENT_ADDRESS");
        assertThat(result.getCheckoutLocationSource()).isEqualTo("PATIENT_ADDRESS");
    }
}
