package com.careconnect.service;

import com.careconnect.config.VitalAlertThresholdProperties;
import com.careconnect.dto.VitalSampleDTO;
import com.careconnect.model.Patient;
import com.careconnect.model.User;
import com.careconnect.model.VitalSample;
import com.careconnect.model.CaregiverPatientLink;
import com.careconnect.model.FamilyMemberLink;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.VitalSampleRepository;
import com.careconnect.repository.WearableMetricRepository;
import com.careconnect.repository.PatientCaregiverRepository;
import com.careconnect.repository.FamilyMemberLinkRepository;
import com.careconnect.repository.VitalAlertEventRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.MockitoAnnotations;

import java.time.Instant;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.timeout;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class VitalSampleServiceTest {

    @Mock
    private VitalSampleRepository vitalSampleRepository;
    @Mock
    private PatientRepository patientRepository;
    @Mock
    private WearableMetricRepository wearableMetricRepository;
    @Mock
    private CaregiverService caregiverService;
    @Mock
    private NotificationService notificationService;
    @Mock
    private PatientCaregiverRepository patientCaregiverRepository;
    @Mock
    private FamilyMemberLinkRepository familyMemberLinkRepository;
    @Mock
    private VitalAlertEventRepository vitalAlertEventRepository;

    private VitalSampleService vitalSampleService;
    private Patient patient;
    private User caregiverUser;

    @BeforeEach
    void setUp() {
        MockitoAnnotations.openMocks(this);

        VitalAlertThresholdProperties thresholdProperties = new VitalAlertThresholdProperties();
        vitalSampleService = new VitalSampleService(
            vitalSampleRepository,
            patientRepository,
            wearableMetricRepository,
            caregiverService,
            notificationService,
            patientCaregiverRepository,
            familyMemberLinkRepository,
            vitalAlertEventRepository,
            thresholdProperties
        );

        User user = User.builder().id(101L).name("John Doe").build();
        patient = Patient.builder().id(1L).user(user).firstName("John").lastName("Doe").build();
        caregiverUser = User.builder().id(201L).name("Caregiver One").build();

        CaregiverPatientLink activeLink = new CaregiverPatientLink();
        activeLink.setCaregiverUser(caregiverUser);
        activeLink.setPatientUser(user);
        activeLink.setStatus(CaregiverPatientLink.LinkStatus.ACTIVE);
        activeLink.setExpiresAt(LocalDateTime.now().plusDays(7));

        when(patientCaregiverRepository.findByPatientUser(any(User.class)))
                .thenReturn(List.of(activeLink));
        when(familyMemberLinkRepository.findActiveFamilyMembersByPatient(any(), any()))
                .thenReturn(List.<FamilyMemberLink>of());
        when(notificationService.sendVitalAlertToRecipient(any(), any(), any(), any(), any()))
                .thenReturn(List.of(com.careconnect.dto.NotificationResponse.success("ok-1")));
    }

    @Test
    @DisplayName("heartRate normal does not dispatch alert")
    void createVitalSample_heartRateNormal_noAlert() {
        mockCreateFlow(VitalSample.builder().patient(patient).heartRate(80.0).build());

        vitalSampleService.createVitalSample(
            VitalSampleDTO.builder().patientId(1L).timestamp(Instant.now()).heartRate(80.0).build()
        );

        verify(notificationService, never()).sendVitalAlertToRecipient(any(), any(), any(), any(), any());
    }

    @Test
    @DisplayName("heartRate low dispatches LOW payload")
    void createVitalSample_heartRateLow_dispatchesLowPayload() {
        mockCreateFlow(VitalSample.builder().patient(patient).heartRate(55.0).build());

        vitalSampleService.createVitalSample(
            VitalSampleDTO.builder().patientId(1L).timestamp(Instant.now()).heartRate(55.0).build()
        );

        verify(notificationService, timeout(1000))
                .sendVitalAlertToRecipient(201L, "John Doe", "heart_rate", "55.0 bpm", "LOW");
    }

    @Test
    @DisplayName("heartRate high dispatches HIGH payload")
    void createVitalSample_heartRateHigh_dispatchesHighPayload() {
        mockCreateFlow(VitalSample.builder().patient(patient).heartRate(110.0).build());

        vitalSampleService.createVitalSample(
            VitalSampleDTO.builder().patientId(1L).timestamp(Instant.now()).heartRate(110.0).build()
        );

        verify(notificationService, timeout(1000))
                .sendVitalAlertToRecipient(201L, "John Doe", "heart_rate", "110.0 bpm", "HIGH");
    }

    @Test
    @DisplayName("heartRate critical dispatches CRITICAL payload")
    void createVitalSample_heartRateCritical_dispatchesCriticalPayload() {
        mockCreateFlow(VitalSample.builder().patient(patient).heartRate(130.0).build());

        vitalSampleService.createVitalSample(
            VitalSampleDTO.builder().patientId(1L).timestamp(Instant.now()).heartRate(130.0).build()
        );

        verify(notificationService, timeout(1000))
                .sendVitalAlertToRecipient(201L, "John Doe", "heart_rate", "130.0 bpm", "CRITICAL");
    }

    @Test
    @DisplayName("heartRate ordering evaluates critical before high")
    void createVitalSample_heartRateOrdering_criticalBeforeHigh() {
        VitalAlertThresholdProperties thresholdProperties = new VitalAlertThresholdProperties();
        thresholdProperties.getHeartRate().setHighMin(90.0);
        thresholdProperties.getHeartRate().setCriticalMin(100.0);
        vitalSampleService = new VitalSampleService(
            vitalSampleRepository,
            patientRepository,
            wearableMetricRepository,
            caregiverService,
            notificationService,
            patientCaregiverRepository,
            familyMemberLinkRepository,
            vitalAlertEventRepository,
            thresholdProperties
        );

        mockCreateFlow(VitalSample.builder().patient(patient).heartRate(105.0).build());

        vitalSampleService.createVitalSample(
            VitalSampleDTO.builder().patientId(1L).timestamp(Instant.now()).heartRate(105.0).build()
        );

        verify(notificationService, timeout(1000))
                .sendVitalAlertToRecipient(201L, "John Doe", "heart_rate", "105.0 bpm", "CRITICAL");
    }

    @Test
    @DisplayName("SpO2 normal does not dispatch alert")
    void createVitalSample_spo2Normal_noAlert() {
        mockCreateFlow(VitalSample.builder().patient(patient).spo2(97.0).build());

        vitalSampleService.createVitalSample(
            VitalSampleDTO.builder().patientId(1L).timestamp(Instant.now()).spo2(97.0).build()
        );

        verify(notificationService, never()).sendVitalAlertToRecipient(any(), any(), any(), any(), any());
    }

    @Test
    @DisplayName("SpO2 low oxygen dispatches HIGH payload")
    void createVitalSample_spo2High_dispatchesHighPayload() {
        mockCreateFlow(VitalSample.builder().patient(patient).spo2(92.0).build());

        vitalSampleService.createVitalSample(
            VitalSampleDTO.builder().patientId(1L).timestamp(Instant.now()).spo2(92.0).build()
        );

        verify(notificationService, timeout(1000))
                .sendVitalAlertToRecipient(201L, "John Doe", "spo2", "92.0%", "HIGH");
    }

    @Test
    @DisplayName("SpO2 critical oxygen dispatches CRITICAL payload")
    void createVitalSample_spo2Critical_dispatchesCriticalPayload() {
        mockCreateFlow(VitalSample.builder().patient(patient).spo2(85.0).build());

        vitalSampleService.createVitalSample(
            VitalSampleDTO.builder().patientId(1L).timestamp(Instant.now()).spo2(85.0).build()
        );

        verify(notificationService, timeout(1000))
                .sendVitalAlertToRecipient(201L, "John Doe", "spo2", "85.0%", "CRITICAL");
    }

    @Test
    @DisplayName("blood pressure normal does not dispatch alert")
    void createVitalSample_bpNormal_noAlert() {
        mockCreateFlow(VitalSample.builder().patient(patient).systolic(120).diastolic(80).build());

        vitalSampleService.createVitalSample(
            VitalSampleDTO.builder().patientId(1L).timestamp(Instant.now()).systolic(120).diastolic(80).build()
        );

        verify(notificationService, never()).sendVitalAlertToRecipient(any(), any(), any(), any(), any());
    }

    @Test
    @DisplayName("blood pressure low dispatches LOW payload")
    void createVitalSample_bpLow_dispatchesLowPayload() {
        mockCreateFlow(VitalSample.builder().patient(patient).systolic(85).diastolic(55).build());

        vitalSampleService.createVitalSample(
            VitalSampleDTO.builder().patientId(1L).timestamp(Instant.now()).systolic(85).diastolic(55).build()
        );

        verify(notificationService, timeout(1000))
                .sendVitalAlertToRecipient(201L, "John Doe", "blood_pressure", "85/55 mmHg", "LOW");
    }

    @Test
    @DisplayName("blood pressure high dispatches HIGH payload")
    void createVitalSample_bpHigh_dispatchesHighPayload() {
        mockCreateFlow(VitalSample.builder().patient(patient).systolic(150).diastolic(95).build());

        vitalSampleService.createVitalSample(
            VitalSampleDTO.builder().patientId(1L).timestamp(Instant.now()).systolic(150).diastolic(95).build()
        );

        verify(notificationService, timeout(1000))
                .sendVitalAlertToRecipient(201L, "John Doe", "blood_pressure", "150/95 mmHg", "HIGH");
    }

    @Test
    @DisplayName("blood pressure critical dispatches CRITICAL payload")
    void createVitalSample_bpCritical_dispatchesCriticalPayload() {
        mockCreateFlow(VitalSample.builder().patient(patient).systolic(190).diastolic(115).build());

        vitalSampleService.createVitalSample(
            VitalSampleDTO.builder().patientId(1L).timestamp(Instant.now()).systolic(190).diastolic(115).build()
        );

        verify(notificationService, timeout(1000))
                .sendVitalAlertToRecipient(201L, "John Doe", "blood_pressure", "190/115 mmHg", "CRITICAL");
    }

    @Test
    @DisplayName("alert payload includes metric type value and severity")
    void createVitalSample_payloadContainsRequiredFields() {
        mockCreateFlow(VitalSample.builder().patient(patient).heartRate(125.0).build());

        vitalSampleService.createVitalSample(
            VitalSampleDTO.builder().patientId(1L).timestamp(Instant.now()).heartRate(125.0).build()
        );

        ArgumentCaptor<String> metricTypeCaptor = ArgumentCaptor.forClass(String.class);
        ArgumentCaptor<String> valueCaptor = ArgumentCaptor.forClass(String.class);
        ArgumentCaptor<String> severityCaptor = ArgumentCaptor.forClass(String.class);

        verify(notificationService, timeout(1000)).sendVitalAlertToRecipient(
            eq(201L),
            eq("John Doe"),
            metricTypeCaptor.capture(),
            valueCaptor.capture(),
            severityCaptor.capture()
        );

        assertNotNull(metricTypeCaptor.getValue());
        assertNotNull(valueCaptor.getValue());
        assertNotNull(severityCaptor.getValue());
    }

    @Test
    @DisplayName("createVitalSample patient missing throws IllegalArgumentException")
    void createVitalSample_patientNotFound_throwsIllegalArgument() {
        when(patientRepository.findById(999L)).thenReturn(Optional.empty());

        assertThrows(
            IllegalArgumentException.class,
            () -> vitalSampleService.createVitalSample(VitalSampleDTO.builder().patientId(999L).build())
        );
    }

    @Test
    @DisplayName("no active care-circle recipients skips dispatch and records event")
    void createVitalSample_noRecipients_recordsNoRecipientsEvent() {
        when(patientCaregiverRepository.findByPatientUser(any(User.class))).thenReturn(List.of());
        when(familyMemberLinkRepository.findActiveFamilyMembersByPatient(any(), any())).thenReturn(List.of());
        mockCreateFlow(VitalSample.builder().patient(patient).heartRate(130.0).build());

        vitalSampleService.createVitalSample(
                VitalSampleDTO.builder().patientId(1L).timestamp(Instant.now()).heartRate(130.0).build()
        );

        verify(notificationService, never()).sendVitalAlertToRecipient(any(), any(), any(), any(), any());
        verify(vitalAlertEventRepository).save(any(com.careconnect.model.VitalAlertEvent.class));
    }

    private void mockCreateFlow(VitalSample returnedSample) {
        VitalSample sample = VitalSample.builder()
            .id(10L)
            .patient(patient)
            .timestamp(returnedSample.getTimestamp() == null ? Instant.now() : returnedSample.getTimestamp())
            .heartRate(returnedSample.getHeartRate())
            .spo2(returnedSample.getSpo2())
            .systolic(returnedSample.getSystolic())
            .diastolic(returnedSample.getDiastolic())
            .weight(returnedSample.getWeight())
            .moodValue(returnedSample.getMoodValue())
            .painValue(returnedSample.getPainValue())
            .build();
        when(patientRepository.findById(1L)).thenReturn(Optional.of(patient));
        when(vitalSampleRepository.save(any(VitalSample.class))).thenReturn(sample);
    }
}
