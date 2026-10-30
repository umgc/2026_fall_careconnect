package com.careconnect.service;

import com.careconnect.config.VitalAlertThresholdProperties;
import com.careconnect.dto.NotificationResponse;
import com.careconnect.dto.VitalSampleDTO;
import com.careconnect.dto.WearableReadingIngestionRequest;
import com.careconnect.dto.WearableReadingIngestionRequest.WearableReadingPayload;
import com.careconnect.dto.WearableReadingIngestionResponse;
import com.careconnect.exception.AppException;
import com.careconnect.model.CaregiverPatientLink;
import com.careconnect.model.FamilyMemberLink;
import com.careconnect.model.Patient;
import com.careconnect.model.User;
import com.careconnect.model.VitalSample;
import com.careconnect.model.WearableMetric;
import com.careconnect.repository.FamilyMemberLinkRepository;
import com.careconnect.repository.PatientCaregiverRepository;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.VitalAlertEventRepository;
import com.careconnect.repository.VitalSampleRepository;
import com.careconnect.repository.WearableMetricRepository;
import com.careconnect.security.Role;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.mockito.junit.jupiter.MockitoSettings;
import org.mockito.quality.Strictness;
import org.springframework.dao.DataIntegrityViolationException;

import java.time.Instant;
import java.time.LocalDateTime;
import java.time.Period;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.Mockito.atLeastOnce;
import static org.mockito.Mockito.timeout;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
class VitalSampleServiceCoverageTest {

    @Mock private VitalSampleRepository vitalSampleRepository;
    @Mock private PatientRepository patientRepository;
    @Mock private WearableMetricRepository wearableMetricRepository;
    @Mock private CaregiverService caregiverService;
    @Mock private NotificationService notificationService;
    @Mock private PatientCaregiverRepository patientCaregiverRepository;
    @Mock private FamilyMemberLinkRepository familyMemberLinkRepository;
    @Mock private VitalAlertEventRepository vitalAlertEventRepository;

    private VitalSampleService service;
    private User patientUser;
    private Patient patient;

    @BeforeEach
    void setUp() {
        service = new VitalSampleService(vitalSampleRepository, patientRepository, wearableMetricRepository,
                caregiverService, notificationService, patientCaregiverRepository, familyMemberLinkRepository,
                vitalAlertEventRepository, new VitalAlertThresholdProperties());
        patientUser = User.builder().id(10L).name("Pat User").role(Role.PATIENT).build();
        patient = Patient.builder().id(1L).user(patientUser).firstName("Pat").lastName("User").build();
        when(patientRepository.findById(1L)).thenReturn(Optional.of(patient));
        when(patientRepository.findByUser(patientUser)).thenReturn(Optional.of(patient));
        when(wearableMetricRepository.save(any())).thenAnswer(inv -> inv.getArgument(0));
        when(vitalSampleRepository.saveAll(any())).thenAnswer(inv -> new ArrayList<>((List<?>) inv.getArgument(0)));
        when(patientCaregiverRepository.findByPatientUser(any())).thenReturn(List.of());
        when(familyMemberLinkRepository.findActiveFamilyMembersByPatient(any(), any())).thenReturn(List.of());
    }

    private static WearableReadingPayload reading(String metric, Double value, Instant at, String source) {
        return new WearableReadingPayload(metric, value, at, source);
    }

    @Test
    void ingestWearableReadingsAsPatientAcceptsAndRejectsReadings() {
        Instant t = Instant.now().minusSeconds(60);
        WearableMetric dupe = WearableMetric.builder().metric(WearableMetric.MetricType.STEPS).build();
        when(wearableMetricRepository.save(any())).thenAnswer(inv -> {
            WearableMetric m = inv.getArgument(0);
            if (m.getMetric() == WearableMetric.MetricType.TEMPERATURE) {
                throw new DataIntegrityViolationException("dup", new RuntimeException("duplicate key"));
            }
            if (m.getMetric() == WearableMetric.MetricType.STEPS) {
                throw new IllegalStateException();
            }
            return m;
        });
        List<WearableReadingPayload> readings = List.of(
                reading("heart_rate", 150.0, t, "watch"),
                reading("SPO2", 85.0, t, null),
                reading("blood_pressure_sys", 200.0, t, " "),
                reading("BLOOD_PRESSURE_DIA", 130.0, t, "x".repeat(80)),
                reading("WEIGHT", 70.0, t.minusSeconds(5), null),
                reading("TEMPERATURE", 37.0, t, null),
                reading("STEPS", 100.0, t, null),
                reading(null, 1.0, t, null),
                reading("bogus", 1.0, t, null),
                reading("HEART_RATE", null, t, null),
                reading("HEART_RATE", Double.NaN, t, null),
                reading("HEART_RATE", 70.0, null, null),
                reading("HEART_RATE", 70.0, Instant.now().plusSeconds(3600), null));

        WearableReadingIngestionResponse resp = service.ingestWearableReadings(patientUser,
                new WearableReadingIngestionRequest(null, null, readings));

        assertThat(resp.patientId()).isEqualTo(1L);
        assertThat(resp.source()).isEqualTo("wearable");
        assertThat(resp.acceptedCount()).isEqualTo(5);
        assertThat(resp.rejectedCount()).isEqualTo(8);
        verify(vitalSampleRepository).saveAll(any());
    }

    @Test
    void ingestWearableReadingsSurvivesVitalSampleSaveFailure() {
        org.mockito.Mockito.doThrow(new RuntimeException("db down")).when(vitalSampleRepository).saveAll(any());
        WearableReadingIngestionResponse resp = service.ingestWearableReadings(patientUser,
                new WearableReadingIngestionRequest(1L, "fitbit",
                        List.of(reading("HEART_RATE", 70.0, Instant.now().minusSeconds(5), null))));
        assertThat(resp.acceptedCount()).isEqualTo(1);
    }

    @Test
    void ingestWearableReadingsPatientCannotTargetOtherPatient() {
        assertThatThrownBy(() -> service.ingestWearableReadings(patientUser,
                new WearableReadingIngestionRequest(99L, null, List.of())))
                .isInstanceOf(AppException.class);
    }

    @Test
    void ingestWearableReadingsCaregiverAndAdminAndOtherRoles() {
        User caregiver = User.builder().id(20L).role(Role.CAREGIVER).build();
        when(caregiverService.hasAccessToPatient(20L, 1L)).thenReturn(true);
        WearableReadingIngestionResponse resp = service.ingestWearableReadings(caregiver,
                new WearableReadingIngestionRequest(1L, null, List.of(reading("STEPS", 10.0, Instant.now().minusSeconds(1), null))));
        assertThat(resp.acceptedCount()).isEqualTo(1);

        when(caregiverService.hasAccessToPatient(20L, 1L)).thenReturn(false);
        assertThatThrownBy(() -> service.ingestWearableReadings(caregiver,
                new WearableReadingIngestionRequest(1L, null, List.of()))).isInstanceOf(AppException.class);

        User admin = User.builder().id(30L).role(Role.ADMIN).build();
        assertThat(service.ingestWearableReadings(admin,
                new WearableReadingIngestionRequest(1L, null, List.of())).acceptedCount()).isZero();

        assertThatThrownBy(() -> service.ingestWearableReadings(admin,
                new WearableReadingIngestionRequest(null, null, List.of()))).isInstanceOf(AppException.class);
        assertThatThrownBy(() -> service.ingestWearableReadings(admin,
                new WearableReadingIngestionRequest(77L, null, List.of()))).isInstanceOf(AppException.class);

        User other = User.builder().id(40L).role(Role.FAMILY_MEMBER).build();
        when(caregiverService.hasAccessToPatient(40L, 1L)).thenReturn(true);
        assertThat(service.ingestWearableReadings(other,
                new WearableReadingIngestionRequest(1L, null, List.of())).rejectedCount()).isZero();
    }

    @Test
    void updateGetDeleteAndLatest() {
        VitalSample existing = VitalSample.builder().id(5L).patient(patient).build();
        when(vitalSampleRepository.findById(5L)).thenReturn(Optional.of(existing));
        when(vitalSampleRepository.save(any())).thenAnswer(inv -> inv.getArgument(0));
        VitalSampleDTO updated = service.updateVitalSample(5L, VitalSampleDTO.builder()
                .timestamp(Instant.now()).heartRate(60.0).spo2(97.0).systolic(120).diastolic(80)
                .weight(70.0).moodValue(5).painValue(2).build());
        assertThat(updated.heartRate()).isEqualTo(60.0);

        when(vitalSampleRepository.findByPatientAndTimestampBetweenOrderByTimestampDesc(any(), any(), any()))
                .thenReturn(List.of(existing));
        assertThat(service.getVitalSamples(1L, Period.ofDays(7))).hasSize(1);
        assertThat(service.getVitalSample(5L)).isPresent();

        when(vitalSampleRepository.existsById(5L)).thenReturn(true);
        service.deleteVitalSample(5L);
        verify(vitalSampleRepository).deleteById(5L);
        when(vitalSampleRepository.existsById(6L)).thenReturn(false);
        assertThatThrownBy(() -> service.deleteVitalSample(6L)).isInstanceOf(IllegalArgumentException.class);

        when(vitalSampleRepository.findFirstByPatientOrderByTimestampDesc(patient)).thenReturn(Optional.of(existing));
        assertThat(service.getLatestVitalSample(1L)).isPresent();
    }

    @Test
    void createVitalSampleWithMoodAndPainAlertsDispatchesToRecipients() {
        CaregiverPatientLink active = new CaregiverPatientLink();
        active.setCaregiverUser(User.builder().id(201L).build());
        active.setStatus(CaregiverPatientLink.LinkStatus.ACTIVE);
        CaregiverPatientLink expired = new CaregiverPatientLink();
        expired.setCaregiverUser(User.builder().id(202L).build());
        expired.setStatus(CaregiverPatientLink.LinkStatus.ACTIVE);
        expired.setExpiresAt(LocalDateTime.now().minusDays(1));
        CaregiverPatientLink noUser = new CaregiverPatientLink();
        List<CaregiverPatientLink> links = new ArrayList<>();
        links.add(active);
        links.add(expired);
        links.add(noUser);
        links.add(null);
        when(patientCaregiverRepository.findByPatientUser(any())).thenReturn(links);
        FamilyMemberLink fam = new FamilyMemberLink();
        fam.setFamilyUser(User.builder().id(301L).build());
        when(familyMemberLinkRepository.findActiveFamilyMembersByPatient(any(), any())).thenReturn(List.of(fam));
        when(notificationService.sendVitalAlertToRecipient(anyLong(), any(), any(), any(), any()))
                .thenAnswer(inv -> {
                    Long id = inv.getArgument(0);
                    if (id == 301L) {
                        throw new RuntimeException("push failed");
                    }
                    return List.of(NotificationResponse.success("ok"));
                });
        when(vitalSampleRepository.save(any())).thenAnswer(inv -> inv.getArgument(0));

        Patient unnamed = Patient.builder().id(1L).user(User.builder().id(10L).name("Display Name").build()).build();
        when(patientRepository.findById(1L)).thenReturn(Optional.of(unnamed));
        service.createVitalSample(VitalSampleDTO.builder().patientId(1L).moodValue(1).painValue(9).build());

        verify(notificationService, timeout(2000).atLeastOnce())
                .sendVitalAlertToRecipient(anyLong(), any(), any(), any(), any());
        verify(vitalAlertEventRepository, timeout(2000).atLeastOnce()).save(any());
    }

    @Test
    void createVitalSampleRecordsNoRecipientsAndUnnamedPatient() {
        when(vitalSampleRepository.save(any())).thenAnswer(inv -> inv.getArgument(0));
        when(vitalAlertEventRepository.save(any())).thenThrow(new RuntimeException("audit down"));
        Patient bare = Patient.builder().id(1L).user(User.builder().id(10L).build()).build();
        when(patientRepository.findById(1L)).thenReturn(Optional.of(bare));
        service.createVitalSample(VitalSampleDTO.builder().patientId(1L).heartRate(200.0).build());
        verify(vitalAlertEventRepository, atLeastOnce()).save(any());
    }

    @Test
    void createVitalSampleNoChannelSucceededRecordsFailure() {
        CaregiverPatientLink active = new CaregiverPatientLink();
        active.setCaregiverUser(User.builder().id(201L).build());
        active.setStatus(CaregiverPatientLink.LinkStatus.ACTIVE);
        CaregiverPatientLink pending = new CaregiverPatientLink();
        pending.setCaregiverUser(User.builder().id(203L).build());
        pending.setStatus(CaregiverPatientLink.LinkStatus.SUSPENDED);
        when(patientCaregiverRepository.findByPatientUser(any())).thenReturn(List.of(active, pending));
        when(notificationService.sendVitalAlertToRecipient(anyLong(), any(), any(), any(), any()))
                .thenReturn(List.of(NotificationResponse.failure("nope")));
        when(vitalSampleRepository.save(any())).thenAnswer(inv -> inv.getArgument(0));
        Patient bare = Patient.builder().id(1L).user(User.builder().id(10L).build()).build();
        when(patientRepository.findById(1L)).thenReturn(Optional.of(bare));
        service.createVitalSample(VitalSampleDTO.builder().patientId(1L).spo2(80.0).build());
        verify(vitalAlertEventRepository, timeout(2000).atLeastOnce()).save(any());
    }

    @Test
    void createVitalSampleWithoutPatientUserSkipsAlerts() {
        Patient noUser = Patient.builder().id(1L).build();
        when(patientRepository.findById(1L)).thenReturn(Optional.of(noUser));
        when(vitalSampleRepository.save(any())).thenAnswer(inv -> inv.getArgument(0));
        assertThat(service.createVitalSample(VitalSampleDTO.builder().patientId(1L).heartRate(200.0).build()))
                .isNotNull();
    }
}
