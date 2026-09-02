package com.careconnect.service;

import com.careconnect.dto.DashboardDTO;
import com.careconnect.dto.ExportLinkDTO;
import com.careconnect.dto.VitalSampleDTO;
import com.careconnect.exception.AppException;
import com.careconnect.model.MoodPainLog;
import com.careconnect.model.Patient;
import com.careconnect.model.SummaryMetric;
import com.careconnect.model.User;
import com.careconnect.model.WearableMetric;
import com.careconnect.repository.*;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.MockitoAnnotations;

import java.time.Instant;
import java.time.LocalDateTime;
import java.time.Period;
import java.time.ZoneOffset;
import java.util.Collections;
import java.util.List;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

class AnalyticsServiceTest {

    private static final Long PATIENT_USER_ID = 1L;
    @Mock
    private SymptomEntryRepository symptomRepo;
    @Mock
    private WearableMetricRepository wearableRepo;
    @Mock
    private SummaryMetricRepository summaryRepo;
    @Mock
    private MoodPainLogRepository moodPainLogRepo;
    @Mock
    private PatientRepository patientRepo;
    @Mock
    private UserRepository userRepo;
    @Mock
    private ExportSigner exportSigner;
    @InjectMocks
    private AnalyticsService analyticsService;
    private Patient testPatient;
    private User testUser;

    @BeforeEach
    void setUp() throws Exception {
        MockitoAnnotations.openMocks(this);

        testUser = new User();
        testUser.setId(1L);
        testUser.setEmail("patient@test.com");

        testPatient = Patient.builder()
                .id(10L)
                .firstName("John")
                .lastName("Doe")
                .user(testUser)
                .build();
    }

    // ==================== getDashboard Tests ====================

    @Nested
    @DisplayName("getDashboard tests")
    class GetDashboardTests {

        @Test
        @DisplayName("getDashboard_withRecentSummaryMetric_shouldUseAggregatedValues")
        void getDashboard_withRecentSummaryMetric_shouldUseAggregatedValues() throws Exception {
            final Long patientId = 10L;
            final Period period = Period.ofDays(7);

            final SummaryMetric agg = mock(SummaryMetric.class);
            when(agg.getGeneratedAt()).thenReturn(Instant.now()); // recent
            when(agg.getAdherenceRate()).thenReturn(85.0);
            when(agg.getAvgHeartRate()).thenReturn(72.5);

            when(summaryRepo.findTopByPatientUserIdAndPeriodStartAndPeriodEndOrderByCreatedAtDesc(
                    eq(PATIENT_USER_ID), any(Instant.class), any(Instant.class))).thenReturn(agg);

            when(wearableRepo.avgForPeriod(eq(PATIENT_USER_ID), eq(WearableMetric.MetricType.SPO2), any(), any())).thenReturn(98.2);
            when(wearableRepo.avgForPeriod(eq(PATIENT_USER_ID), eq(WearableMetric.MetricType.BLOOD_PRESSURE_SYS), any(), any())).thenReturn(120.0);
            when(wearableRepo.avgForPeriod(eq(PATIENT_USER_ID), eq(WearableMetric.MetricType.BLOOD_PRESSURE_DIA), any(), any())).thenReturn(80.0);
            when(wearableRepo.avgForPeriod(eq(PATIENT_USER_ID), eq(WearableMetric.MetricType.WEIGHT), any(), any())).thenReturn(170.5);

            when(patientRepo.findById(patientId)).thenReturn(Optional.of(testPatient));
            when(moodPainLogRepo.avgMoodByPatientAndTimestampBetween(eq(testPatient), any(), any())).thenReturn(7.5);
            when(moodPainLogRepo.avgPainByPatientAndTimestampBetween(eq(testPatient), any(), any())).thenReturn(3.2);
            when(moodPainLogRepo.countMoodEntriesByPatientAndTimestampBetween(eq(testPatient), any(), any())).thenReturn(5);
            when(moodPainLogRepo.countPainEntriesByPatientAndTimestampBetween(eq(testPatient), any(), any())).thenReturn(4);

            final DashboardDTO result = analyticsService.getDashboard(patientId, period);

            assertNotNull(result);
            assertEquals(85.0, result.adherenceRate());
            assertEquals(73.0, result.avgHeartRate()); // round0(72.5) = 73
            assertEquals(98.2, result.avgSpo2());
            assertEquals(120.0, result.avgSystolic());
            assertEquals(80.0, result.avgDiastolic());
            assertEquals(170.5, result.avgWeight());
            assertEquals(7.5, result.avgMood());
            assertEquals(3.2, result.avgPain());
            assertEquals(5, result.moodEntries());
            assertEquals(4, result.painEntries());
            assertNotNull(result.periodStart());
            assertNotNull(result.periodEnd());
        }

        @Test
        @DisplayName("getDashboard_withNullSummaryMetric_shouldComputeFromRawData")
        void getDashboard_withNullSummaryMetric_shouldComputeFromRawData() throws Exception {
            final Long patientId = 10L;
            final Period period = Period.ofDays(7);

            when(summaryRepo.findTopByPatientUserIdAndPeriodStartAndPeriodEndOrderByCreatedAtDesc(
                    eq(PATIENT_USER_ID), any(Instant.class), any(Instant.class))).thenReturn(null);

            when(symptomRepo.countCompleted(eq(patientId), any(), any())).thenReturn(8L);
            when(symptomRepo.countTotal(eq(patientId), any(), any())).thenReturn(10L);
            when(wearableRepo.avgForPeriod(eq(PATIENT_USER_ID), eq(WearableMetric.MetricType.HEART_RATE), any(), any())).thenReturn(75.0);
            when(wearableRepo.avgForPeriod(eq(PATIENT_USER_ID), eq(WearableMetric.MetricType.SPO2), any(), any())).thenReturn(97.0);
            when(wearableRepo.avgForPeriod(eq(PATIENT_USER_ID), eq(WearableMetric.MetricType.BLOOD_PRESSURE_SYS), any(), any())).thenReturn(118.0);
            when(wearableRepo.avgForPeriod(eq(PATIENT_USER_ID), eq(WearableMetric.MetricType.BLOOD_PRESSURE_DIA), any(), any())).thenReturn(78.0);
            when(wearableRepo.avgForPeriod(eq(PATIENT_USER_ID), eq(WearableMetric.MetricType.WEIGHT), any(), any())).thenReturn(165.0);

            when(patientRepo.findById(patientId)).thenReturn(Optional.of(testPatient));
            when(moodPainLogRepo.avgMoodByPatientAndTimestampBetween(eq(testPatient), any(), any())).thenReturn(null);
            when(moodPainLogRepo.avgPainByPatientAndTimestampBetween(eq(testPatient), any(), any())).thenReturn(null);
            when(moodPainLogRepo.countMoodEntriesByPatientAndTimestampBetween(eq(testPatient), any(), any())).thenReturn(null);
            when(moodPainLogRepo.countPainEntriesByPatientAndTimestampBetween(eq(testPatient), any(), any())).thenReturn(null);

            final DashboardDTO result = analyticsService.getDashboard(patientId, period);

            assertNotNull(result);
            assertEquals(80.0, result.adherenceRate()); // (8*100)/10 = 80
            assertEquals(75.0, result.avgHeartRate());
            assertNull(result.avgMood());
            assertNull(result.avgPain());
            assertEquals(0, result.moodEntries());
            assertEquals(0, result.painEntries());
        }

        @Test
        @DisplayName("getDashboard_withZeroTotalSymptoms_shouldReturnZeroAdherence")
        void getDashboard_withZeroTotalSymptoms_shouldReturnZeroAdherence() throws Exception {
            final Long patientId = 10L;
            final Period period = Period.ofDays(7);

            when(summaryRepo.findTopByPatientUserIdAndPeriodStartAndPeriodEndOrderByCreatedAtDesc(
                    eq(PATIENT_USER_ID), any(), any())).thenReturn(null);

            when(symptomRepo.countCompleted(eq(patientId), any(), any())).thenReturn(0L);
            when(symptomRepo.countTotal(eq(patientId), any(), any())).thenReturn(0L);
            when(wearableRepo.avgForPeriod(eq(PATIENT_USER_ID), eq(WearableMetric.MetricType.HEART_RATE), any(), any())).thenReturn(null);
            when(wearableRepo.avgForPeriod(eq(PATIENT_USER_ID), eq(WearableMetric.MetricType.SPO2), any(), any())).thenReturn(null);
            when(wearableRepo.avgForPeriod(eq(PATIENT_USER_ID), eq(WearableMetric.MetricType.BLOOD_PRESSURE_SYS), any(), any())).thenReturn(null);
            when(wearableRepo.avgForPeriod(eq(PATIENT_USER_ID), eq(WearableMetric.MetricType.BLOOD_PRESSURE_DIA), any(), any())).thenReturn(null);
            when(wearableRepo.avgForPeriod(eq(PATIENT_USER_ID), eq(WearableMetric.MetricType.WEIGHT), any(), any())).thenReturn(null);

            when(patientRepo.findById(patientId)).thenReturn(Optional.of(testPatient));
            when(moodPainLogRepo.avgMoodByPatientAndTimestampBetween(eq(testPatient), any(), any())).thenReturn(null);
            when(moodPainLogRepo.avgPainByPatientAndTimestampBetween(eq(testPatient), any(), any())).thenReturn(null);
            when(moodPainLogRepo.countMoodEntriesByPatientAndTimestampBetween(eq(testPatient), any(), any())).thenReturn(0);
            when(moodPainLogRepo.countPainEntriesByPatientAndTimestampBetween(eq(testPatient), any(), any())).thenReturn(0);

            final DashboardDTO result = analyticsService.getDashboard(patientId, period);

            assertEquals(0.0, result.adherenceRate());
            assertEquals(0.0, result.avgHeartRate());
            assertEquals(0.0, result.avgSpo2());
        }

        @Test
        @DisplayName("getDashboard_patientNotFound_shouldThrowAppException")
        void getDashboard_patientNotFound_shouldThrowAppException() throws Exception {
            final Long patientId = 999L;
            final Period period = Period.ofDays(7);

            when(summaryRepo.findTopByPatientUserIdAndPeriodStartAndPeriodEndOrderByCreatedAtDesc(
                    eq(PATIENT_USER_ID), any(), any())).thenReturn(null);
            when(symptomRepo.countCompleted(eq(patientId), any(), any())).thenReturn(0L);
            when(symptomRepo.countTotal(eq(patientId), any(), any())).thenReturn(0L);
            when(wearableRepo.avgForPeriod(any(), any(), any(), any())).thenReturn(null);
            when(patientRepo.findById(patientId)).thenReturn(Optional.empty());

            assertThrows(AppException.class, () -> analyticsService.getDashboard(patientId, period));
        }

        @Test
        @DisplayName("getDashboard_withNullHeartRateAvg_shouldReturnZero")
        void getDashboard_withNullHeartRateAvg_shouldReturnZero() throws Exception {
            final Long patientId = 10L;
            final Period period = Period.ofDays(7);

            when(summaryRepo.findTopByPatientUserIdAndPeriodStartAndPeriodEndOrderByCreatedAtDesc(
                    eq(PATIENT_USER_ID), any(), any())).thenReturn(null);

            when(symptomRepo.countCompleted(eq(patientId), any(), any())).thenReturn(5L);
            when(symptomRepo.countTotal(eq(patientId), any(), any())).thenReturn(10L);
            when(wearableRepo.avgForPeriod(eq(PATIENT_USER_ID), eq(WearableMetric.MetricType.HEART_RATE), any(), any())).thenReturn(null);
            when(wearableRepo.avgForPeriod(eq(PATIENT_USER_ID), eq(WearableMetric.MetricType.SPO2), any(), any())).thenReturn(null);
            when(wearableRepo.avgForPeriod(eq(PATIENT_USER_ID), eq(WearableMetric.MetricType.BLOOD_PRESSURE_SYS), any(), any())).thenReturn(null);
            when(wearableRepo.avgForPeriod(eq(PATIENT_USER_ID), eq(WearableMetric.MetricType.BLOOD_PRESSURE_DIA), any(), any())).thenReturn(null);
            when(wearableRepo.avgForPeriod(eq(PATIENT_USER_ID), eq(WearableMetric.MetricType.WEIGHT), any(), any())).thenReturn(null);

            when(patientRepo.findById(patientId)).thenReturn(Optional.of(testPatient));
            when(moodPainLogRepo.avgMoodByPatientAndTimestampBetween(eq(testPatient), any(), any())).thenReturn(null);
            when(moodPainLogRepo.avgPainByPatientAndTimestampBetween(eq(testPatient), any(), any())).thenReturn(null);
            when(moodPainLogRepo.countMoodEntriesByPatientAndTimestampBetween(eq(testPatient), any(), any())).thenReturn(null);
            when(moodPainLogRepo.countPainEntriesByPatientAndTimestampBetween(eq(testPatient), any(), any())).thenReturn(null);

            final DashboardDTO result = analyticsService.getDashboard(patientId, period);

            assertEquals(0.0, result.avgHeartRate());
        }

        @Test
        @DisplayName("getDashboard_avgOrZeroThrowsException_shouldReturnZero")
        void getDashboard_avgOrZeroThrowsException_shouldReturnZero() throws Exception {
            final Long patientId = 10L;
            final Period period = Period.ofDays(7);

            when(summaryRepo.findTopByPatientUserIdAndPeriodStartAndPeriodEndOrderByCreatedAtDesc(
                    eq(PATIENT_USER_ID), any(), any())).thenReturn(null);
            when(symptomRepo.countCompleted(eq(patientId), any(), any())).thenReturn(0L);
            when(symptomRepo.countTotal(eq(patientId), any(), any())).thenReturn(0L);
            when(wearableRepo.avgForPeriod(eq(PATIENT_USER_ID), eq(WearableMetric.MetricType.HEART_RATE), any(), any())).thenReturn(null);

            // Make SPO2 throw an exception to test the catch block in avgOrZero
            when(wearableRepo.avgForPeriod(eq(PATIENT_USER_ID), eq(WearableMetric.MetricType.SPO2), any(), any()))
                    .thenThrow(new RuntimeException("DB error"));
            when(wearableRepo.avgForPeriod(eq(PATIENT_USER_ID), eq(WearableMetric.MetricType.BLOOD_PRESSURE_SYS), any(), any())).thenReturn(null);
            when(wearableRepo.avgForPeriod(eq(PATIENT_USER_ID), eq(WearableMetric.MetricType.BLOOD_PRESSURE_DIA), any(), any())).thenReturn(null);
            when(wearableRepo.avgForPeriod(eq(PATIENT_USER_ID), eq(WearableMetric.MetricType.WEIGHT), any(), any())).thenReturn(null);

            when(patientRepo.findById(patientId)).thenReturn(Optional.of(testPatient));
            when(moodPainLogRepo.avgMoodByPatientAndTimestampBetween(eq(testPatient), any(), any())).thenReturn(null);
            when(moodPainLogRepo.avgPainByPatientAndTimestampBetween(eq(testPatient), any(), any())).thenReturn(null);
            when(moodPainLogRepo.countMoodEntriesByPatientAndTimestampBetween(eq(testPatient), any(), any())).thenReturn(0);
            when(moodPainLogRepo.countPainEntriesByPatientAndTimestampBetween(eq(testPatient), any(), any())).thenReturn(0);

            final DashboardDTO result = analyticsService.getDashboard(patientId, period);

            assertEquals(0.0, result.avgSpo2());
        }
    }

    // ==================== getVitals Tests ====================

    @Nested
    @DisplayName("getVitals tests")
    class GetVitalsTests {

        @Test
        @DisplayName("getVitals_withWearableAndMoodPainData_shouldMergeAndSort")
        void getVitals_withWearableAndMoodPainData_shouldMergeAndSort() throws Exception {
            final Long patientId = 10L;
            final Period period = Period.ofDays(7);
            final Instant ts1 = Instant.parse("2025-01-01T10:00:00Z");
            final Instant ts2 = Instant.parse("2025-01-02T10:00:00Z");

            final WearableMetric hrMetric = WearableMetric.builder()
                    .metric(WearableMetric.MetricType.HEART_RATE)
                    .metricValue(72.0)
                    .recordedAt(ts1)
                    .build();

            final WearableMetric spo2Metric = WearableMetric.builder()
                    .metric(WearableMetric.MetricType.SPO2)
                    .metricValue(98.0)
                    .recordedAt(ts1)
                    .build();

            when(wearableRepo.findByPatientIdAndRecordedAtBetween(eq(PATIENT_USER_ID), any(), any()))
                    .thenReturn(List.of(hrMetric, spo2Metric));

            when(patientRepo.findById(patientId)).thenReturn(Optional.of(testPatient));

            final MoodPainLog moodLog = MoodPainLog.builder()
                    .moodValue(7)
                    .painValue(3)
                    .timestamp(LocalDateTime.ofInstant(ts2, ZoneOffset.UTC))
                    .build();

            when(moodPainLogRepo.findByPatientAndTimestampBetween(eq(testPatient), any(), any()))
                    .thenReturn(List.of(moodLog));

            final List<VitalSampleDTO> result = analyticsService.getVitals(patientId, period);

            assertNotNull(result);
            assertEquals(2, result.size());
            // Should be sorted by timestamp
            assertTrue(result.get(0).timestamp().isBefore(result.get(1).timestamp()));
        }

        @Test
        @DisplayName("getVitals_withNoData_shouldReturnEmptyList")
        void getVitals_withNoData_shouldReturnEmptyList() throws Exception {
            final Long patientId = 10L;
            final Period period = Period.ofDays(7);

            when(wearableRepo.findByPatientIdAndRecordedAtBetween(eq(PATIENT_USER_ID), any(), any()))
                    .thenReturn(Collections.emptyList());
            when(patientRepo.findById(patientId)).thenReturn(Optional.of(testPatient));
            when(moodPainLogRepo.findByPatientAndTimestampBetween(eq(testPatient), any(), any()))
                    .thenReturn(Collections.emptyList());

            final List<VitalSampleDTO> result = analyticsService.getVitals(patientId, period);

            assertNotNull(result);
            assertTrue(result.isEmpty());
        }

        @Test
        @DisplayName("getVitals_patientNotFound_shouldThrowAppException")
        void getVitals_patientNotFound_shouldThrowAppException() throws Exception {
            final Long patientId = 999L;
            final Period period = Period.ofDays(7);

            when(wearableRepo.findByPatientIdAndRecordedAtBetween(eq(PATIENT_USER_ID), any(), any()))
                    .thenReturn(Collections.emptyList());
            when(patientRepo.findById(patientId)).thenReturn(Optional.empty());

            assertThrows(AppException.class, () -> analyticsService.getVitals(patientId, period));
        }

        @Test
        @DisplayName("getVitals_withBloodPressure_shouldMapSystolicAndDiastolicAsIntegers")
        void getVitals_withBloodPressure_shouldMapSystolicAndDiastolicAsIntegers() throws Exception {
            final Long patientId = 10L;
            final Period period = Period.ofDays(7);
            final Instant ts1 = Instant.parse("2025-01-01T10:00:00Z");

            final WearableMetric sysMetric = WearableMetric.builder()
                    .metric(WearableMetric.MetricType.BLOOD_PRESSURE_SYS)
                    .metricValue(120.7)
                    .recordedAt(ts1)
                    .build();

            final WearableMetric diaMetric = WearableMetric.builder()
                    .metric(WearableMetric.MetricType.BLOOD_PRESSURE_DIA)
                    .metricValue(80.3)
                    .recordedAt(ts1)
                    .build();

            when(wearableRepo.findByPatientIdAndRecordedAtBetween(eq(PATIENT_USER_ID), any(), any()))
                    .thenReturn(List.of(sysMetric, diaMetric));
            when(patientRepo.findById(patientId)).thenReturn(Optional.of(testPatient));
            when(moodPainLogRepo.findByPatientAndTimestampBetween(eq(testPatient), any(), any()))
                    .thenReturn(Collections.emptyList());

            final List<VitalSampleDTO> result = analyticsService.getVitals(patientId, period);

            assertEquals(1, result.size());
            assertEquals(120, result.get(0).systolic()); // doubleToInt truncates
            assertEquals(80, result.get(0).diastolic());
        }

        @Test
        @DisplayName("getVitals_withEmptyMoodPainList_shouldHaveNullMoodAndPain")
        void getVitals_withEmptyMoodPainList_shouldHaveNullMoodAndPain() throws Exception {
            final Long patientId = 10L;
            final Period period = Period.ofDays(7);
            final Instant ts1 = Instant.parse("2025-01-01T10:00:00Z");

            final WearableMetric hrMetric = WearableMetric.builder()
                    .metric(WearableMetric.MetricType.HEART_RATE)
                    .metricValue(72.0)
                    .recordedAt(ts1)
                    .build();

            when(wearableRepo.findByPatientIdAndRecordedAtBetween(eq(PATIENT_USER_ID), any(), any()))
                    .thenReturn(List.of(hrMetric));
            when(patientRepo.findById(patientId)).thenReturn(Optional.of(testPatient));
            when(moodPainLogRepo.findByPatientAndTimestampBetween(eq(testPatient), any(), any()))
                    .thenReturn(Collections.emptyList());

            final List<VitalSampleDTO> result = analyticsService.getVitals(patientId, period);

            assertEquals(1, result.size());
            assertNull(result.get(0).moodValue());
            assertNull(result.get(0).painValue());
        }

        @Test
        @DisplayName("getVitals_withDuplicateMetricTypes_shouldLastWin")
        void getVitals_withDuplicateMetricTypes_shouldLastWin() throws Exception {
            final Long patientId = 10L;
            final Period period = Period.ofDays(7);
            final Instant ts1 = Instant.parse("2025-01-01T10:00:00Z");

            final WearableMetric hr1 = WearableMetric.builder()
                    .metric(WearableMetric.MetricType.HEART_RATE)
                    .metricValue(70.0)
                    .recordedAt(ts1)
                    .build();

            final WearableMetric hr2 = WearableMetric.builder()
                    .metric(WearableMetric.MetricType.HEART_RATE)
                    .metricValue(80.0)
                    .recordedAt(ts1)
                    .build();

            when(wearableRepo.findByPatientIdAndRecordedAtBetween(eq(PATIENT_USER_ID), any(), any()))
                    .thenReturn(List.of(hr1, hr2));
            when(patientRepo.findById(patientId)).thenReturn(Optional.of(testPatient));
            when(moodPainLogRepo.findByPatientAndTimestampBetween(eq(testPatient), any(), any()))
                    .thenReturn(Collections.emptyList());

            final List<VitalSampleDTO> result = analyticsService.getVitals(patientId, period);

            assertEquals(1, result.size());
            assertEquals(80.0, result.get(0).heartRate()); // last wins
        }
    }

    // ==================== createSignedExportLink Tests ====================

    @Nested
    @DisplayName("createSignedExportLink tests")
    class CreateSignedExportLinkTests {

        @Test
        @DisplayName("createSignedExportLink_validPath_shouldDelegateToExportSigner")
        void createSignedExportLink_validPath_shouldDelegateToExportSigner() throws Exception {
            final String path = "/exports/vitals.csv";
            final ExportLinkDTO expected = new ExportLinkDTO();
            expected.setUrl("https://files.careconnect.ai/exports/vitals.csv?sig=mock123");

            when(exportSigner.sign(path)).thenReturn(expected);

            final ExportLinkDTO result = analyticsService.createSignedExportLink(path);

            assertNotNull(result);
            assertEquals(expected.getUrl(), result.getUrl());
            verify(exportSigner).sign(path);
        }
    }

    // ==================== exportVitalsCsv Tests ====================

    @Nested
    @DisplayName("exportVitalsCsv tests")
    class ExportVitalsCsvTests {

        @Test
        @DisplayName("exportVitalsCsv_withData_shouldReturnCsvBytes")
        void exportVitalsCsv_withData_shouldReturnCsvBytes() throws Exception {
            final Long patientId = 10L;
            final Period period = Period.ofDays(7);
            final Instant ts = Instant.parse("2025-01-01T10:00:00Z");

            final WearableMetric hrMetric = WearableMetric.builder()
                    .metric(WearableMetric.MetricType.HEART_RATE)
                    .metricValue(72.0)
                    .recordedAt(ts)
                    .build();

            when(wearableRepo.findByPatientIdAndRecordedAtBetween(eq(PATIENT_USER_ID), any(), any()))
                    .thenReturn(List.of(hrMetric));
            when(patientRepo.findById(patientId)).thenReturn(Optional.of(testPatient));
            when(moodPainLogRepo.findByPatientAndTimestampBetween(eq(testPatient), any(), any()))
                    .thenReturn(Collections.emptyList());

            final byte[] result = analyticsService.exportVitalsCsv(patientId, period);

            assertNotNull(result);
            final String csv = new String(result);
            assertTrue(csv.startsWith("timestamp,heartRate,spo2,systolic,diastolic,weight,moodValue,painValue"));
            assertTrue(csv.contains("72.0"));
        }

        @Test
        @DisplayName("exportVitalsCsv_withNoData_shouldReturnHeaderOnly")
        void exportVitalsCsv_withNoData_shouldReturnHeaderOnly() throws Exception {
            final Long patientId = 10L;
            final Period period = Period.ofDays(7);

            when(wearableRepo.findByPatientIdAndRecordedAtBetween(eq(PATIENT_USER_ID), any(), any()))
                    .thenReturn(Collections.emptyList());
            when(patientRepo.findById(patientId)).thenReturn(Optional.of(testPatient));
            when(moodPainLogRepo.findByPatientAndTimestampBetween(eq(testPatient), any(), any()))
                    .thenReturn(Collections.emptyList());

            final byte[] result = analyticsService.exportVitalsCsv(patientId, period);

            final String csv = new String(result);
            assertEquals("timestamp,heartRate,spo2,systolic,diastolic,weight,moodValue,painValue\n", csv);
        }
    }

    // ==================== exportVitalsPdf Tests ====================

    @Nested
    @DisplayName("exportVitalsPdf tests")
    class ExportVitalsPdfTests {

        @Test
        @DisplayName("exportVitalsPdf_withData_shouldReturnPdfBytes")
        void exportVitalsPdf_withData_shouldReturnPdfBytes() throws Exception {
            final Long patientId = 10L;
            final Period period = Period.ofDays(7);
            final Instant ts = Instant.parse("2025-01-01T10:00:00Z");

            final WearableMetric hrMetric = WearableMetric.builder()
                    .metric(WearableMetric.MetricType.HEART_RATE)
                    .metricValue(72.0)
                    .recordedAt(ts)
                    .build();

            when(wearableRepo.findByPatientIdAndRecordedAtBetween(eq(PATIENT_USER_ID), any(), any()))
                    .thenReturn(List.of(hrMetric));
            when(patientRepo.findById(patientId)).thenReturn(Optional.of(testPatient));
            when(moodPainLogRepo.findByPatientAndTimestampBetween(eq(testPatient), any(), any()))
                    .thenReturn(Collections.emptyList());

            final byte[] result = analyticsService.exportVitalsPdf(patientId, period);

            assertNotNull(result);
            assertTrue(result.length > 0);
            // PDF files start with %PDF
            final String header = new String(result, 0, Math.min(5, result.length));
            assertTrue(header.startsWith("%PDF"));
        }

        @Test
        @DisplayName("exportVitalsPdf_withEmptyData_shouldReturnValidPdf")
        void exportVitalsPdf_withEmptyData_shouldReturnValidPdf() throws Exception {
            final Long patientId = 10L;
            final Period period = Period.ofDays(7);

            when(wearableRepo.findByPatientIdAndRecordedAtBetween(eq(PATIENT_USER_ID), any(), any()))
                    .thenReturn(Collections.emptyList());
            when(patientRepo.findById(patientId)).thenReturn(Optional.of(testPatient));
            when(moodPainLogRepo.findByPatientAndTimestampBetween(eq(testPatient), any(), any()))
                    .thenReturn(Collections.emptyList());

            final byte[] result = analyticsService.exportVitalsPdf(patientId, period);

            assertNotNull(result);
            assertTrue(result.length > 0);
        }
    }

    // ==================== toDTO (private) coverage via getVitals ====================

    @Nested
    @DisplayName("toDTO helper coverage via getVitals")
    class ToDtoTests {

        @Test
        @DisplayName("getVitals_withMoodPainLogsAtSameTimestamp_shouldPickLatest")
        void getVitals_withMoodPainLogsAtSameTimestamp_shouldPickLatest() throws Exception {
            final Long patientId = 10L;
            final Period period = Period.ofDays(7);
            final LocalDateTime logTime = LocalDateTime.of(2025, 1, 1, 10, 0);

            when(wearableRepo.findByPatientIdAndRecordedAtBetween(eq(PATIENT_USER_ID), any(), any()))
                    .thenReturn(Collections.emptyList());
            when(patientRepo.findById(patientId)).thenReturn(Optional.of(testPatient));

            final MoodPainLog log1 = MoodPainLog.builder()
                    .moodValue(5)
                    .painValue(2)
                    .timestamp(logTime)
                    .build();

            final MoodPainLog log2 = MoodPainLog.builder()
                    .moodValue(8)
                    .painValue(4)
                    .timestamp(logTime.plusMinutes(1))
                    .build();

            // Both logs map to the same Instant bucket since they share the same ZoneOffset.UTC conversion
            // but log2 has a later timestamp within the list
            when(moodPainLogRepo.findByPatientAndTimestampBetween(eq(testPatient), any(), any()))
                    .thenReturn(List.of(log1, log2));

            final List<VitalSampleDTO> result = analyticsService.getVitals(patientId, period);

            assertNotNull(result);
            assertFalse(result.isEmpty());
        }

        @Test
        @DisplayName("getVitals_withWeightMetric_shouldMapWeightValue")
        void getVitals_withWeightMetric_shouldMapWeightValue() throws Exception {
            final Long patientId = 10L;
            final Period period = Period.ofDays(7);
            final Instant ts = Instant.parse("2025-01-01T10:00:00Z");

            final WearableMetric weightMetric = WearableMetric.builder()
                    .metric(WearableMetric.MetricType.WEIGHT)
                    .metricValue(175.5)
                    .recordedAt(ts)
                    .build();

            when(wearableRepo.findByPatientIdAndRecordedAtBetween(eq(PATIENT_USER_ID), any(), any()))
                    .thenReturn(List.of(weightMetric));
            when(patientRepo.findById(patientId)).thenReturn(Optional.of(testPatient));
            when(moodPainLogRepo.findByPatientAndTimestampBetween(eq(testPatient), any(), any()))
                    .thenReturn(Collections.emptyList());

            final List<VitalSampleDTO> result = analyticsService.getVitals(patientId, period);

            assertEquals(1, result.size());
            assertEquals(175.5, result.get(0).weight());
            assertNull(result.get(0).heartRate());
            assertNull(result.get(0).systolic());
            assertNull(result.get(0).diastolic());
        }
    }
}
