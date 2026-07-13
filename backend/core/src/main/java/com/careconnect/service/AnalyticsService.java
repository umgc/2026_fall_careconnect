package com.careconnect.service;

import com.careconnect.dto.*;
import com.careconnect.model.SummaryMetric;
import com.careconnect.model.WearableMetric;
import com.careconnect.model.Patient;
import com.careconnect.model.User;
import com.careconnect.repository.*;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import com.lowagie.text.*;
import com.careconnect.exception.AppException;
import com.lowagie.text.pdf.*;
import java.util.Comparator;
import java.io.ByteArrayOutputStream;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.HashSet;
import java.util.Collections;
import java.time.Instant;
import java.util.stream.Collectors;
import java.time.*;
import org.springframework.http.HttpStatus;


@Service
@RequiredArgsConstructor
@Transactional(readOnly = true)
public class AnalyticsService {

    private final SymptomEntryRepository symptomRepo;
    private final WearableMetricRepository wearableRepo;
    private final SummaryMetricRepository summaryRepo;
    private final MoodPainLogRepository moodPainLogRepo;
    private final PatientRepository patientRepo;
    private final UserRepository userRepo;
    private final ExportSigner exportSigner;


    /* ---------------- Dashboard ---------------- */

    // MOCK: Replace real DB logic with static mock data for all patients
    public DashboardDTO getDashboard(Long patientId, Period period) {
        // Original DB-based implementation restored
        Instant to = Instant.now();
        Instant from = to.minus(period);
        Patient patient = getPatientById(patientId);
        Long patientUserId = patient.getUser().getId();
        SummaryMetric agg = summaryRepo.findTopByPatientUserIdAndPeriodStartAndPeriodEndOrderByCreatedAtDesc(patientUserId, from, to);
        double adherence;
        double avgHr;
        if (agg != null && agg.getGeneratedAt().isAfter(Instant.now().minus(Period.ofDays(1)))) {
            adherence = agg.getAdherenceRate();
            avgHr = agg.getAvgHeartRate();
        } else {
            long completed = symptomRepo.countCompleted(patientId, from, to);
            long total = symptomRepo.countTotal(patientId, from, to);
            adherence = total == 0 ? 0 : (completed * 100.0) / total;
            Double hr = wearableRepo.avgForPeriod(patientUserId, WearableMetric.MetricType.HEART_RATE, from, to);
            avgHr = hr == null ? 0 : hr;
        }
        double avgSpo2 = avgOrZero(patientUserId, WearableMetric.MetricType.SPO2, from, to);
        double avgSys = avgOrZero(patientUserId, WearableMetric.MetricType.BLOOD_PRESSURE_SYS, from, to);
        double avgDia = avgOrZero(patientUserId, WearableMetric.MetricType.BLOOD_PRESSURE_DIA, from, to);
        double avgWeight = avgOrZero(patientUserId, WearableMetric.MetricType.WEIGHT, from, to);
        LocalDateTime fromLdt = LocalDateTime.ofInstant(from, ZoneOffset.UTC);
        LocalDateTime toLdt = LocalDateTime.ofInstant(to, ZoneOffset.UTC);
        Double avgMood = moodPainLogRepo.avgMoodByPatientAndTimestampBetween(patient, fromLdt, toLdt);
        Double avgPain = moodPainLogRepo.avgPainByPatientAndTimestampBetween(patient, fromLdt, toLdt);
        Integer moodEntries = moodPainLogRepo.countMoodEntriesByPatientAndTimestampBetween(patient, fromLdt, toLdt);
        Integer painEntries = moodPainLogRepo.countPainEntriesByPatientAndTimestampBetween(patient, fromLdt, toLdt);
        return DashboardDTO.builder()
                .periodStart(from)
                .periodEnd(to)
                .adherenceRate(round1(adherence))
                .avgHeartRate(round0(avgHr))
                .avgSpo2(round1(avgSpo2))
                .avgSystolic(round0(avgSys))
                .avgDiastolic(round0(avgDia))
                .avgWeight(round1(avgWeight))
                .avgMood(avgMood != null ? round1(avgMood) : null)
                .avgPain(avgPain != null ? round1(avgPain) : null)
                .moodEntries(moodEntries != null ? moodEntries : 0)
                .painEntries(painEntries != null ? painEntries : 0)
                .build();
    }

    /* ---------------- Vitals series ---------------- */

    // MOCK: Replace real DB logic with static mock data for all patients
    public List<VitalSampleDTO> getVitals(Long patientId, Period period) {
        // Original DB-based implementation restored
        Instant to = Instant.now();
        Instant from = to.minus(period);
        Patient patient = getPatientById(patientId);
        Long patientUserId = patient.getUser().getId();
        List<WearableMetric> wearableMetrics = wearableRepo.findByPatientIdAndRecordedAtBetween(patientUserId, from, to);
        LocalDateTime fromLdt = LocalDateTime.ofInstant(from, ZoneOffset.UTC);
        LocalDateTime toLdt = LocalDateTime.ofInstant(to, ZoneOffset.UTC);
        List<com.careconnect.model.MoodPainLog> moodPainLogs = moodPainLogRepo.findByPatientAndTimestampBetween(patient, fromLdt, toLdt);
        Map<Instant, List<WearableMetric>> wearableByTime = wearableMetrics.stream().collect(Collectors.groupingBy(WearableMetric::getRecordedAt));
        Map<Instant, List<com.careconnect.model.MoodPainLog>> moodPainByTime = moodPainLogs.stream().collect(Collectors.groupingBy(log -> log.getTimestamp().atZone(ZoneOffset.UTC).toInstant()));
        Set<Instant> allTimestamps = new HashSet<>();
        allTimestamps.addAll(wearableByTime.keySet());
        allTimestamps.addAll(moodPainByTime.keySet());
        return allTimestamps.stream()
                .map(timestamp -> toDTO(patientId, timestamp, wearableByTime.getOrDefault(timestamp, Collections.emptyList()), moodPainByTime.getOrDefault(timestamp, Collections.emptyList())))
                .sorted(Comparator.comparing(VitalSampleDTO::timestamp))
                .toList();
    }

    /* ---------------- Exports ---------------- */

    public ExportLinkDTO createSignedExportLink(String path) {
        return exportSigner.sign(path);
    }

    /* ---------------- Helpers ---------------- */

    private VitalSampleDTO toDTO(Long pid, Instant ts, List<WearableMetric> wearableList, List<com.careconnect.model.MoodPainLog> moodPainList) {
        Map<WearableMetric.MetricType, Double> wearableMap = wearableList.stream()
                .collect(Collectors.toMap(WearableMetric::getMetric,
                        WearableMetric::getMetricValue,
                        (a, b) -> b)); // last wins

        // Get the most recent mood and pain values for this timestamp
        Integer moodValue = null;
        Integer painValue = null;
        if (!moodPainList.isEmpty()) {
            com.careconnect.model.MoodPainLog latestLog = moodPainList.stream()
                    .max(Comparator.comparing(com.careconnect.model.MoodPainLog::getTimestamp))
                    .orElse(null);
            if (latestLog != null) {
                moodValue = latestLog.getMoodValue();
                painValue = latestLog.getPainValue();
            }
        }

        return VitalSampleDTO.builder()
                .id(null) // This is aggregated data, not a specific entity
                .patientId(pid)
                .timestamp(ts)
                .heartRate(wearableMap.get(WearableMetric.MetricType.HEART_RATE))
                .spo2(wearableMap.get(WearableMetric.MetricType.SPO2))
                .systolic(doubleToInt(wearableMap.get(WearableMetric.MetricType.BLOOD_PRESSURE_SYS)))
                .diastolic(doubleToInt(wearableMap.get(WearableMetric.MetricType.BLOOD_PRESSURE_DIA)))
                .weight(wearableMap.get(WearableMetric.MetricType.WEIGHT))
                .moodValue(moodValue)
                .painValue(painValue)
                .build();
    }

    private double round1(double v) { return Math.round(v * 10) / 10.0; }
    private double round0(double v) { return Math.round(v); }

    private Integer doubleToInt(Double d) { return d == null ? null : d.intValue(); }

    /**
     * Get patient by user ID
     */
    private Patient getPatientUserId(Long userId) {
        User user = userRepo.findById(userId)
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "User not found"));
        return patientRepo.findByUser(user)
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Patient profile not found"));
    }

    /**
     * Get patient by patient ID
     * Note: patientId is the actual patient table ID, not the user ID
     */
    private Patient getPatientById(Long patientId) {
        return patientRepo.findById(patientId)
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Patient profile not found"));
    }

    public byte[] exportVitalsCsv(Long patientId, Period period) {
        List<VitalSampleDTO> vitals = getVitals(patientId, period);

        StringBuilder sb = new StringBuilder();
        sb.append("timestamp,heartRate,spo2,systolic,diastolic,weight,moodValue,painValue\n");
        for (VitalSampleDTO v : vitals) {
            sb.append(v.timestamp()).append(",")
                    .append(v.heartRate()).append(",")
                    .append(v.spo2()).append(",")
                    .append(v.systolic()).append(",")
                    .append(v.diastolic()).append(",")
                    .append(v.weight()).append(",")
                    .append(v.moodValue()).append(",")
                    .append(v.painValue()).append("\n");
        }
        return sb.toString().getBytes(java.nio.charset.StandardCharsets.UTF_8);
    }

    public byte[] exportVitalsPdf(Long patientId, Period period) {
        List<VitalSampleDTO> vitals = getVitals(patientId, period);

        try (ByteArrayOutputStream baos = new ByteArrayOutputStream()) {
            Document document = new Document();
            PdfWriter.getInstance(document, baos);
            document.open();

            document.add(new Paragraph("Vitals & Wellness Report"));
            document.add(new Paragraph("Patient ID: " + patientId));
            document.add(new Paragraph("Period: Last " + period.getDays() + " days"));
            document.add(new Paragraph(" "));

            PdfPTable table = new PdfPTable(8);
            table.addCell("Timestamp");
            table.addCell("Heart Rate");
            table.addCell("SpO2");
            table.addCell("Systolic");
            table.addCell("Diastolic");
            table.addCell("Weight");
            table.addCell("Mood (1-10)");
            table.addCell("Pain (1-10)");

            for (VitalSampleDTO v : vitals) {
                table.addCell(String.valueOf(v.timestamp()));
                table.addCell(String.valueOf(v.heartRate()));
                table.addCell(String.valueOf(v.spo2()));
                table.addCell(String.valueOf(v.systolic()));
                table.addCell(String.valueOf(v.diastolic()));
                table.addCell(String.valueOf(v.weight()));
                table.addCell(String.valueOf(v.moodValue()));
                table.addCell(String.valueOf(v.painValue()));
            }

            document.add(table);
            document.close();
            return baos.toByteArray();
        } catch (Exception e) {
            throw new RuntimeException("Failed to generate PDF", e);
        }
    }

    private VitalSampleDTO createEmptyVitalSample(Long patientId, Instant timestamp) {
        return VitalSampleDTO.builder()
                .id(null) // This is an empty template, not a persisted entity
                .patientId(patientId)
                .timestamp(timestamp)
                .heartRate(0.0)
                .spo2(0.0)
                .systolic(0)
                .diastolic(0)
                .weight(0.0)
                .moodValue(0)
                .painValue(0)
                .build();
    }

    private double avgOrZero(Long pid, WearableMetric.MetricType type,
                             Instant from, Instant to) {
        try {
            Double v = wearableRepo.avgForPeriod(pid, type, from, to);
            return v == null ? 0 : v;
        } catch (Exception e) {
            return 0.0;
        }
    }

}