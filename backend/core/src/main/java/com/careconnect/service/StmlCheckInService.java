package com.careconnect.service;

import com.careconnect.dto.StmlCheckInDTO;
import com.careconnect.dto.StmlCheckInDTO.StmlCheckInItemDTO;
import com.careconnect.model.Allergy;
import com.careconnect.model.ClinicalNote;
import com.careconnect.model.Medication;
import com.careconnect.model.Task;
import com.careconnect.model.User;
import com.careconnect.repository.AllergyRepository;
import com.careconnect.repository.CaregiverPatientLinkRepository;
import com.careconnect.repository.ClinicalNotesRepository;
import com.careconnect.repository.MedicationRepository;
import com.careconnect.repository.TaskRepository;
import com.careconnect.repository.UserRepository;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

/**
 * Service for STML-3 caregiver check-in preparation view.
 * Gated by explicit care-recipient consent via active caregiver-patient link.
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class StmlCheckInService {

  private final CaregiverPatientLinkRepository caregiverPatientLinkRepository;
  private final UserRepository userRepository;
  private final ClinicalNotesRepository clinicalNotesRepository;
  private final TaskRepository taskRepository;
  private final MedicationRepository medicationRepository;
  private final AllergyRepository allergyRepository;

  /**
   * Returns a check-in preparation view for a caregiver.
   * Access is gated by an active caregiver-patient consent link.
   *
   * @param patientId   the ID of the patient
   * @param caregiverId the ID of the caregiver requesting the view
   * @return the check-in preparation DTO
   */
  public StmlCheckInDTO getCheckInView(final Long patientId, final Long caregiverId) {
    User caregiver = userRepository.findById(caregiverId).orElse(null);
    User patient = userRepository.findById(patientId).orElse(null);

    boolean hasConsent = false;
    if (caregiver != null && patient != null) {
      hasConsent = caregiverPatientLinkRepository
          .existsActiveNonExpiredLink(caregiver, patient, LocalDateTime.now());
    }

    if (!hasConsent) {
      return StmlCheckInDTO.builder()
          .patientId(patientId)
          .caregiverId(caregiverId)
          .generatedAt(LocalDateTime.now())
          .consentGranted(false)
          .notes(List.of())
          .pendingItems(List.of())
          .disclaimer(
              "Access denied. The care recipient has not granted"
              + " consent for caregiver check-in view.")
          .build();
    }

    List<StmlCheckInItemDTO> notes = new ArrayList<>();
    List<StmlCheckInItemDTO> pendingItems = new ArrayList<>();

    try {
      List<ClinicalNote> clinicalNotes = clinicalNotesRepository
          .findByPatientIdOrderByCreatedAtDesc(patientId)
          .stream().limit(5).toList();
      for (ClinicalNote n : clinicalNotes) {
        notes.add(StmlCheckInItemDTO.builder()
            .type("NOTE")
            .summary(n.getNoteType() + ": " + n.getContent())
            .date(n.getCreatedAt().toLocalDate().toString())
            .source("CLINICAL_NOTE")
            .build());
      }
    } catch (Exception e) {
      log.warn("Could not load notes for patient {}: {}", patientId, e.getMessage());
    }

    try {
      List<Medication> meds = medicationRepository.findActiveByPatientId(patientId);
      for (Medication m : meds) {
        notes.add(StmlCheckInItemDTO.builder()
            .type("MEDICATION")
            .summary(m.getMedicationName()
                + (m.getDosage() != null ? " " + m.getDosage() : "")
                + (m.getFrequency() != null ? ", " + m.getFrequency() : ""))
            .date(null)
            .source("MEDICATION")
            .build());
      }
    } catch (Exception e) {
      log.warn("Could not load medications for patient {}: {}", patientId, e.getMessage());
    }

    try {
      List<Allergy> allergies = allergyRepository.findByPatientId(patientId);
      for (Allergy a : allergies) {
        notes.add(StmlCheckInItemDTO.builder()
            .type("ALLERGY")
            .summary(a.getAllergen()
                + (a.getReaction() != null ? " - " + a.getReaction() : ""))
            .date(null)
            .source("ALLERGY")
            .build());
      }
    } catch (Exception e) {
      log.warn("Could not load allergies for patient {}: {}", patientId, e.getMessage());
    }

    try {
      List<Task> tasks = taskRepository
          .findByPatientId(patientId).orElse(List.of());
      tasks.stream()
          .filter(t -> !t.isCompleted())
          .forEach(t -> pendingItems.add(StmlCheckInItemDTO.builder()
              .type("TASK")
              .summary(t.getName()
                  + (t.getDescription() != null ? ": " + t.getDescription() : ""))
              .date(t.getDate())
              .source("TASK")
              .build()));
    } catch (Exception e) {
      log.warn("Could not load tasks for patient {}: {}", patientId, e.getMessage());
    }

    return StmlCheckInDTO.builder()
        .patientId(patientId)
        .caregiverId(caregiverId)
        .generatedAt(LocalDateTime.now())
        .consentGranted(true)
        .notes(notes)
        .pendingItems(pendingItems)
        .disclaimer(
            "This information is drawn from the care recipient's records."
            + " It is not medical advice.")
        .build();
  }
}