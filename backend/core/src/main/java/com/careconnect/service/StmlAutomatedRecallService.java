package com.careconnect.service;

import com.careconnect.dto.StmlRecallRequest;
import com.careconnect.model.Patient;
import com.careconnect.repository.CallRecordingRepository;
import com.careconnect.repository.PatientRepository;
import java.time.LocalDateTime;
import java.util.List;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;

/**
 * Automated recall service for Issue #142.
 *
 * <p>Runs nightly and generates a proactive STML recall brief
 * for every patient who had no calls today, so they are prepared
 * for the following day.
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class StmlAutomatedRecallService {

    private final PatientRepository patientRepository;
    private final CallRecordingRepository callRecordingRepository;
    private final StmlRecallService stmlRecallService;

    /**
     * Runs every night at 11 PM to generate automated recall briefs
     * for patients who had no calls today.
     */
    @Scheduled(cron = "${stml.automated-recall.cron:0 0 23 * * *}")
    public void generateAutomatedRecallsForNocallPatients() {
        log.info("Starting automated recall generation for no-call patients");

        LocalDateTime startOfDay = LocalDateTime.now().toLocalDate().atStartOfDay();
        LocalDateTime endOfDay = startOfDay.plusDays(1).minusSeconds(1);

        List<Patient> allPatients = patientRepository.findAll();
        log.info("Checking {} patients for no-call automated recall", allPatients.size());

        int generated = 0;
        int skipped = 0;

        for (Patient patient : allPatients) {
            try {
                Long patientId = patient.getId();
                Long userId = patient.getUser() != null ? patient.getUser().getId() : null;

                if (userId == null) {
                    log.warn("Patient {} has no user — skipping", patientId);
                    skipped++;
                    continue;
                }

                // Check if patient had any calls today
                boolean hadCallsToday = hadCallsToday(userId, startOfDay, endOfDay);

                if (hadCallsToday) {
                    log.debug("Patient {} had calls today — skipping automated recall", patientId);
                    skipped++;
                    continue;
                }

                // Generate automated recall for tomorrow
                generateRecallForPatient(patientId);
                generated++;
                log.info("Automated recall generated for patient {}", patientId);

            } catch (Exception e) {
                log.error("Failed to generate automated recall for patient {}: {}",
                        patient.getId(), e.getMessage());
            }
        }

        log.info("Automated recall complete — generated={} skipped={}", generated, skipped);
    }

    /**
     * Checks if a user had any call recordings today.
     *
     * @param userId     the user ID to check
     * @param startOfDay start of today
     * @param endOfDay   end of today
     * @return true if any calls were recorded today
     */
    private boolean hadCallsToday(Long userId, LocalDateTime startOfDay, LocalDateTime endOfDay) {
        return callRecordingRepository
                .findByInitiatedByUserIdOrderByStartedAtDesc(userId)
                .stream()
                .anyMatch(r -> r.getStartedAt() != null
                        && !r.getStartedAt().isBefore(startOfDay)
                        && !r.getStartedAt().isAfter(endOfDay));
    }

    /**
     * Generates a proactive recall brief for a patient for the following day.
     *
     * @param patientId the patient entity ID
     */
    private void generateRecallForPatient(Long patientId) {
        StmlRecallRequest request = new StmlRecallRequest();
        request.setPatientId(patientId);
        request.setQuestion(
                "Please provide a brief summary of my care plan, "
                + "upcoming tasks, and any medications I should be aware of for tomorrow.");
        stmlRecallService.recall(request);
    }
}