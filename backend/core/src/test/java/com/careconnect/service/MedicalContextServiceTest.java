package com.careconnect.service;

import com.careconnect.dto.ChatRequest;
import com.careconnect.dto.UploadedFileDTO;
import com.careconnect.model.Allergy;
import com.careconnect.model.ClinicalNote;
import com.careconnect.model.Gender;
import com.careconnect.model.Medication;
import com.careconnect.model.MoodPainLog;
import com.careconnect.model.Patient;
import com.careconnect.model.UserAIConfig;
import com.careconnect.model.Vital;
import com.careconnect.repository.AllergyRepository;
import com.careconnect.repository.ClinicalNotesRepository;
import com.careconnect.repository.MedicationRepository;
import com.careconnect.repository.MoodPainLogRepository;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.VitalsRepository;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class MedicalContextServiceTest {

    @Mock PatientRepository patientRepository;
    @Mock MoodPainLogRepository moodPainLogRepository;
    @Mock ClinicalNotesRepository clinicalNotesRepository;
    @Mock MedicationRepository medicationRepository;
    @Mock VitalsRepository vitalsRepository;
    @Mock AllergyRepository allergyRepository;
    @Mock DocumentProcessingService documentProcessingService;

    @InjectMocks
    MedicalContextService service;

    // ── Helpers ───────────────────────────────────────────────────────────────

    private Patient patient(Long id) {
        return Patient.builder().id(id).firstName("John").lastName("Doe").build();
    }

    /** All include-by-default flags false so only explicit request overrides trigger sections */
    private UserAIConfig cfg() throws Exception {
        final UserAIConfig c = new UserAIConfig();
        c.setUserId(1L);
        c.setPreferredAiProvider(UserAIConfig.AIProvider.OPENAI);
        c.setIncludeVitalsByDefault(false);
        c.setIncludeMedicationsByDefault(false);
        c.setIncludeNotesByDefault(false);
        c.setIncludeMoodPainByDefault(false);
        c.setIncludeAllergiesByDefault(false);
        return c;
    }

    /** Request with every Boolean include-flag null → defers to aiConfig defaults */
    private ChatRequest bareRequest() throws Exception {
        return new ChatRequest();
    }

    // ═════════════════════════════════════════════════════════════════════════
    // buildPatientContext – top-level path
    // ═════════════════════════════════════════════════════════════════════════

    @Test
    void buildPatientContext_patientNotFound_returnsEmptyString() throws Exception {
        when(patientRepository.findById(1L)).thenReturn(Optional.empty());
        assertThat(service.buildPatientContext(1L, bareRequest(), cfg())).isEmpty();
    }

    @Test
    void buildPatientContext_minimalPatient_containsNameAndFooter() throws Exception {
        when(patientRepository.findById(1L)).thenReturn(Optional.of(patient(1L)));
        final String result = service.buildPatientContext(1L, bareRequest(), cfg());
        assertThat(result).contains("John Doe");
        assertThat(result).contains("IMPORTANT:");
    }

    @Test
    void buildPatientContext_withSystemPrompt_appended() throws Exception {
        when(patientRepository.findById(1L)).thenReturn(Optional.of(patient(1L)));
        final UserAIConfig c = cfg();
        c.setSystemPrompt("Be concise");
        assertThat(service.buildPatientContext(1L, bareRequest(), c))
                .contains("System Instructions: Be concise");
    }

    @Test
    void buildPatientContext_withBlankSystemPrompt_notAppended() throws Exception {
        when(patientRepository.findById(1L)).thenReturn(Optional.of(patient(1L)));
        final UserAIConfig c = cfg();
        c.setSystemPrompt("   ");
        assertThat(service.buildPatientContext(1L, bareRequest(), c))
                .doesNotContain("System Instructions:");
    }

    @Test
    void buildPatientContext_withNullSystemPrompt_notAppended() throws Exception {
        when(patientRepository.findById(1L)).thenReturn(Optional.of(patient(1L)));
        final UserAIConfig c = cfg();
        c.setSystemPrompt(null);
        assertThat(service.buildPatientContext(1L, bareRequest(), c))
                .doesNotContain("System Instructions:");
    }

    @Test
    void buildPatientContext_withDob_included() throws Exception {
        final Patient p = Patient.builder().id(1L).firstName("Jane").lastName("Smith")
                .dob("1985-05-20").build();
        when(patientRepository.findById(1L)).thenReturn(Optional.of(p));
        assertThat(service.buildPatientContext(1L, bareRequest(), cfg()))
                .contains("Date of Birth: 1985-05-20");
    }

    @Test
    void buildPatientContext_withGender_included() throws Exception {
        final Patient p = Patient.builder().id(1L).firstName("Jane").lastName("Smith")
                .gender(Gender.FEMALE).build();
        when(patientRepository.findById(1L)).thenReturn(Optional.of(p));
        assertThat(service.buildPatientContext(1L, bareRequest(), cfg()))
                .contains("Gender:");
    }

    @Test
    void buildPatientContext_withAdditionalContext_allItemsPresent() throws Exception {
        when(patientRepository.findById(1L)).thenReturn(Optional.of(patient(1L)));
        final ChatRequest req = bareRequest();
        req.setAdditionalContext(List.of("Context A", "Context B"));
        final String result = service.buildPatientContext(1L, req, cfg());
        assertThat(result).contains("ADDITIONAL CONTEXT:");
        assertThat(result).contains("- Context A");
        assertThat(result).contains("- Context B");
    }

    @Test
    void buildPatientContext_withUploadedFile_contentExtracted() throws Exception {
        when(patientRepository.findById(1L)).thenReturn(Optional.of(patient(1L)));
        final UploadedFileDTO file = UploadedFileDTO.builder()
                .filename("report.pdf").contentType("application/pdf").build();
        when(documentProcessingService.extractTextContent(file)).thenReturn("PDF text");
        final ChatRequest req = bareRequest();
        req.setUploadedFiles(List.of(file));
        final String result = service.buildPatientContext(1L, req, cfg());
        assertThat(result).contains("UPLOADED FILES:");
        assertThat(result).contains("File: report.pdf");
        assertThat(result).contains("PDF text");
    }

    // ═════════════════════════════════════════════════════════════════════════
    // shouldInclude* – request override (non-null) vs. aiConfig default
    // ═════════════════════════════════════════════════════════════════════════

    @Test
    void shouldIncludeVitals_requestOverrideTrue_callsRepo() throws Exception {
        when(patientRepository.findById(1L)).thenReturn(Optional.of(patient(1L)));
        when(vitalsRepository.findByPatientIdOrderByRecordedAtDesc(1L)).thenReturn(Collections.emptyList());
        final ChatRequest req = bareRequest();
        req.setIncludeVitals(true);
        service.buildPatientContext(1L, req, cfg()); // reaches vitals repo
    }

    @Test
    void shouldIncludeVitals_requestOverrideFalse_skipsVitals() throws Exception {
        when(patientRepository.findById(1L)).thenReturn(Optional.of(patient(1L)));
        final ChatRequest req = bareRequest();
        req.setIncludeVitals(false);
        assertThat(service.buildPatientContext(1L, req, cfg())).doesNotContain("RECENT VITALS:");
    }

    @Test
    void shouldIncludeVitals_requestNullAiConfigTrue_callsRepo() throws Exception {
        when(patientRepository.findById(1L)).thenReturn(Optional.of(patient(1L)));
        when(vitalsRepository.findByPatientIdOrderByRecordedAtDesc(1L)).thenReturn(Collections.emptyList());
        final UserAIConfig c = cfg();
        c.setIncludeVitalsByDefault(true);
        service.buildPatientContext(1L, bareRequest(), c);
    }

    @Test
    void shouldIncludeMedications_requestNullAiConfigTrue_callsRepo() throws Exception {
        when(patientRepository.findById(1L)).thenReturn(Optional.of(patient(1L)));
        when(medicationRepository.findActiveByPatientId(1L)).thenReturn(Collections.emptyList());
        final UserAIConfig c = cfg();
        c.setIncludeMedicationsByDefault(true);
        service.buildPatientContext(1L, bareRequest(), c);
    }

    @Test
    void shouldIncludeNotes_requestNullAiConfigTrue_callsRepo() throws Exception {
        when(patientRepository.findById(1L)).thenReturn(Optional.of(patient(1L)));
        when(clinicalNotesRepository.findByPatientIdOrderByCreatedAtDesc(1L)).thenReturn(Collections.emptyList());
        final UserAIConfig c = cfg();
        c.setIncludeNotesByDefault(true);
        service.buildPatientContext(1L, bareRequest(), c);
    }

    @Test
    void shouldIncludeMoodPainLogs_requestNullAiConfigTrue_callsRepo() throws Exception {
        final Patient p = patient(1L);
        when(patientRepository.findById(1L)).thenReturn(Optional.of(p));
        when(moodPainLogRepository.findByPatientOrderByTimestampDesc(p)).thenReturn(Collections.emptyList());
        final UserAIConfig c = cfg();
        c.setIncludeMoodPainByDefault(true);
        service.buildPatientContext(1L, bareRequest(), c);
    }

    @Test
    void shouldIncludeAllergies_requestNullAiConfigTrue_callsRepo() throws Exception {
        when(patientRepository.findById(1L)).thenReturn(Optional.of(patient(1L)));
        when(allergyRepository.findByPatientId(1L)).thenReturn(Collections.emptyList());
        final UserAIConfig c = cfg();
        c.setIncludeAllergiesByDefault(true);
        service.buildPatientContext(1L, bareRequest(), c);
    }

    // ═════════════════════════════════════════════════════════════════════════
    // addVitalsContext
    // ═════════════════════════════════════════════════════════════════════════

    @Test
    void addVitalsContext_emptyList_noHeader() throws Exception {
        when(patientRepository.findById(1L)).thenReturn(Optional.of(patient(1L)));
        when(vitalsRepository.findByPatientIdOrderByRecordedAtDesc(1L)).thenReturn(Collections.emptyList());
        final ChatRequest req = bareRequest();
        req.setIncludeVitals(true);
        assertThat(service.buildPatientContext(1L, req, cfg())).doesNotContain("RECENT VITALS:");
    }

    @Test
    void addVitalsContext_withUnit_unitLinePresent() throws Exception {
        when(patientRepository.findById(1L)).thenReturn(Optional.of(patient(1L)));
        final Vital v = Vital.builder().vitalType("BLOOD_PRESSURE").value("120/80").unit("mmHg")
                .recordedAt(LocalDateTime.of(2025, 1, 10, 9, 0)).build();
        when(vitalsRepository.findByPatientIdOrderByRecordedAtDesc(1L)).thenReturn(List.of(v));
        final ChatRequest req = bareRequest();
        req.setIncludeVitals(true);
        final String result = service.buildPatientContext(1L, req, cfg());
        assertThat(result).contains("RECENT VITALS:");
        assertThat(result).contains("Type: BLOOD_PRESSURE");
        assertThat(result).contains("Unit: mmHg");
    }

    @Test
    void addVitalsContext_withoutUnit_noUnitLine() throws Exception {
        when(patientRepository.findById(1L)).thenReturn(Optional.of(patient(1L)));
        final Vital v = Vital.builder().vitalType("HEART_RATE").value("72").unit(null)
                .recordedAt(LocalDateTime.of(2025, 1, 10, 9, 0)).build();
        when(vitalsRepository.findByPatientIdOrderByRecordedAtDesc(1L)).thenReturn(List.of(v));
        final ChatRequest req = bareRequest();
        req.setIncludeVitals(true);
        final String result = service.buildPatientContext(1L, req, cfg());
        assertThat(result).contains("Type: HEART_RATE");
        assertThat(result).doesNotContain("Unit:");
    }

    @Test
    void addVitalsContext_moreThan10_limitedTo10() throws Exception {
        when(patientRepository.findById(1L)).thenReturn(Optional.of(patient(1L)));
        final List<Vital> vitals = new ArrayList<>();
        for (int i = 0; i < 15; i++) {
            vitals.add(Vital.builder().vitalType("TYPE_" + i).value(String.valueOf(i))
                    .recordedAt(LocalDateTime.now()).build());
        }
        when(vitalsRepository.findByPatientIdOrderByRecordedAtDesc(1L)).thenReturn(vitals);
        final ChatRequest req = bareRequest();
        req.setIncludeVitals(true);
        final String result = service.buildPatientContext(1L, req, cfg());
        assertThat(result).contains("TYPE_9");
        assertThat(result).doesNotContain("TYPE_10");
    }

    @Test
    void addVitalsContext_repoThrows_exceptionSuppressed() throws Exception {
        when(patientRepository.findById(1L)).thenReturn(Optional.of(patient(1L)));
        when(vitalsRepository.findByPatientIdOrderByRecordedAtDesc(1L))
                .thenThrow(new RuntimeException("DB error"));
        final ChatRequest req = bareRequest();
        req.setIncludeVitals(true);
        assertThat(service.buildPatientContext(1L, req, cfg()))
                .isNotNull().doesNotContain("RECENT VITALS:");
    }

    // ═════════════════════════════════════════════════════════════════════════
    // addMedicationsContext
    // ═════════════════════════════════════════════════════════════════════════

    @Test
    void addMedicationsContext_emptyList_noHeader() throws Exception {
        when(patientRepository.findById(1L)).thenReturn(Optional.of(patient(1L)));
        when(medicationRepository.findActiveByPatientId(1L)).thenReturn(Collections.emptyList());
        final ChatRequest req = bareRequest();
        req.setIncludeMedications(true);
        assertThat(service.buildPatientContext(1L, req, cfg())).doesNotContain("CURRENT MEDICATIONS:");
    }

    @Test
    void addMedicationsContext_withAllOptionalFields_allPresent() throws Exception {
        when(patientRepository.findById(1L)).thenReturn(Optional.of(patient(1L)));
        final Medication med = Medication.builder()
                .medicationName("Aspirin").dosage("100mg")
                .frequency("once daily").notes("Take with food").build();
        when(medicationRepository.findActiveByPatientId(1L)).thenReturn(List.of(med));
        final ChatRequest req = bareRequest();
        req.setIncludeMedications(true);
        final String result = service.buildPatientContext(1L, req, cfg());
        assertThat(result).contains("CURRENT MEDICATIONS:");
        assertThat(result).contains("Aspirin").contains("(100mg)").contains("once daily").contains("Take with food");
    }

    @Test
    void addMedicationsContext_withNullOptionalFields_onlyNamePresent() throws Exception {
        when(patientRepository.findById(1L)).thenReturn(Optional.of(patient(1L)));
        final Medication med = Medication.builder()
                .medicationName("Vitamin D").dosage(null).frequency(null).notes(null).build();
        when(medicationRepository.findActiveByPatientId(1L)).thenReturn(List.of(med));
        final ChatRequest req = bareRequest();
        req.setIncludeMedications(true);
        final String result = service.buildPatientContext(1L, req, cfg());
        assertThat(result).contains("- Vitamin D\n");
        assertThat(result).doesNotContain("(null)");
    }

    @Test
    void addMedicationsContext_repoThrows_exceptionSuppressed() throws Exception {
        when(patientRepository.findById(1L)).thenReturn(Optional.of(patient(1L)));
        when(medicationRepository.findActiveByPatientId(1L)).thenThrow(new RuntimeException("DB error"));
        final ChatRequest req = bareRequest();
        req.setIncludeMedications(true);
        assertThat(service.buildPatientContext(1L, req, cfg())).doesNotContain("CURRENT MEDICATIONS:");
    }

    // ═════════════════════════════════════════════════════════════════════════
    // addNotesContext
    // ═════════════════════════════════════════════════════════════════════════

    @Test
    void addNotesContext_emptyList_noHeader() throws Exception {
        when(patientRepository.findById(1L)).thenReturn(Optional.of(patient(1L)));
        when(clinicalNotesRepository.findByPatientIdOrderByCreatedAtDesc(1L)).thenReturn(Collections.emptyList());
        final ChatRequest req = bareRequest();
        req.setIncludeNotes(true);
        assertThat(service.buildPatientContext(1L, req, cfg())).doesNotContain("RECENT CLINICAL NOTES:");
    }

    @Test
    void addNotesContext_withCaregiverId_caregiverLinePresent() throws Exception {
        when(patientRepository.findById(1L)).thenReturn(Optional.of(patient(1L)));
        final ClinicalNote note = ClinicalNote.builder()
                .noteType("ASSESSMENT").content("Patient is stable").caregiverId(42L)
                .createdAt(LocalDateTime.of(2025, 3, 1, 10, 0)).build();
        when(clinicalNotesRepository.findByPatientIdOrderByCreatedAtDesc(1L)).thenReturn(List.of(note));
        final ChatRequest req = bareRequest();
        req.setIncludeNotes(true);
        final String result = service.buildPatientContext(1L, req, cfg());
        assertThat(result).contains("RECENT CLINICAL NOTES:");
        assertThat(result).contains("By: Provider ID 42");
    }

    @Test
    void addNotesContext_withNullCaregiverId_noCaregiverLine() throws Exception {
        when(patientRepository.findById(1L)).thenReturn(Optional.of(patient(1L)));
        final ClinicalNote note = ClinicalNote.builder()
                .noteType("OBSERVATION").content("Good progress").caregiverId(null)
                .createdAt(LocalDateTime.of(2025, 3, 1, 10, 0)).build();
        when(clinicalNotesRepository.findByPatientIdOrderByCreatedAtDesc(1L)).thenReturn(List.of(note));
        final ChatRequest req = bareRequest();
        req.setIncludeNotes(true);
        assertThat(service.buildPatientContext(1L, req, cfg())).doesNotContain("By: Provider ID");
    }

    @Test
    void addNotesContext_moreThan5Notes_limitedTo5() throws Exception {
        when(patientRepository.findById(1L)).thenReturn(Optional.of(patient(1L)));
        final List<ClinicalNote> notes = new ArrayList<>();
        for (int i = 0; i < 7; i++) {
            notes.add(ClinicalNote.builder().noteType("TYPE_" + i).content("Content " + i)
                    .createdAt(LocalDateTime.now()).build());
        }
        when(clinicalNotesRepository.findByPatientIdOrderByCreatedAtDesc(1L)).thenReturn(notes);
        final ChatRequest req = bareRequest();
        req.setIncludeNotes(true);
        final String result = service.buildPatientContext(1L, req, cfg());
        assertThat(result).contains("TYPE_4");
        assertThat(result).doesNotContain("TYPE_5");
    }

    @Test
    void addNotesContext_repoThrows_exceptionSuppressed() throws Exception {
        when(patientRepository.findById(1L)).thenReturn(Optional.of(patient(1L)));
        when(clinicalNotesRepository.findByPatientIdOrderByCreatedAtDesc(1L))
                .thenThrow(new RuntimeException("DB error"));
        final ChatRequest req = bareRequest();
        req.setIncludeNotes(true);
        assertThat(service.buildPatientContext(1L, req, cfg())).doesNotContain("RECENT CLINICAL NOTES:");
    }

    // ═════════════════════════════════════════════════════════════════════════
    // addMoodPainLogsContext
    // ═════════════════════════════════════════════════════════════════════════

    @Test
    void addMoodPainLogsContext_secondPatientLookupNull_returnsEarly() throws Exception {
        final Patient p = patient(1L);
        when(patientRepository.findById(1L))
                .thenReturn(Optional.of(p))     // first call in buildPatientContext
                .thenReturn(Optional.empty());   // second call inside addMoodPainLogsContext
        final ChatRequest req = bareRequest();
        req.setIncludeMoodPainLogs(true);
        assertThat(service.buildPatientContext(1L, req, cfg())).doesNotContain("RECENT MOOD/PAIN LOGS:");
    }

    @Test
    void addMoodPainLogsContext_emptyList_noHeader() throws Exception {
        final Patient p = patient(1L);
        when(patientRepository.findById(1L)).thenReturn(Optional.of(p));
        when(moodPainLogRepository.findByPatientOrderByTimestampDesc(p)).thenReturn(Collections.emptyList());
        final ChatRequest req = bareRequest();
        req.setIncludeMoodPainLogs(true);
        assertThat(service.buildPatientContext(1L, req, cfg())).doesNotContain("RECENT MOOD/PAIN LOGS:");
    }

    @Test
    void addMoodPainLogsContext_withAllOptionalFields_allPresent() throws Exception {
        final Patient p = patient(1L);
        when(patientRepository.findById(1L)).thenReturn(Optional.of(p));
        final MoodPainLog entry = MoodPainLog.builder().patient(p)
                .moodValue(8).painValue(3).note("Feeling better")
                .timestamp(LocalDateTime.of(2025, 1, 15, 8, 0)).build();
        when(moodPainLogRepository.findByPatientOrderByTimestampDesc(p)).thenReturn(List.of(entry));
        final ChatRequest req = bareRequest();
        req.setIncludeMoodPainLogs(true);
        final String result = service.buildPatientContext(1L, req, cfg());
        assertThat(result).contains("RECENT MOOD/PAIN LOGS:");
        assertThat(result).contains("Mood: 8/10");
        assertThat(result).contains("Pain: 3/10");
        assertThat(result).contains("Notes: Feeling better");
    }

    @Test
    void addMoodPainLogsContext_withNullOptionalFields_noExtraLines() throws Exception {
        final Patient p = patient(1L);
        when(patientRepository.findById(1L)).thenReturn(Optional.of(p));
        final MoodPainLog entry = MoodPainLog.builder().patient(p)
                .moodValue(null).painValue(null).note(null)
                .timestamp(LocalDateTime.of(2025, 1, 15, 8, 0)).build();
        when(moodPainLogRepository.findByPatientOrderByTimestampDesc(p)).thenReturn(List.of(entry));
        final ChatRequest req = bareRequest();
        req.setIncludeMoodPainLogs(true);
        final String result = service.buildPatientContext(1L, req, cfg());
        assertThat(result).contains("RECENT MOOD/PAIN LOGS:");
        assertThat(result).doesNotContain("Mood:").doesNotContain("Pain:").doesNotContain("Notes:");
    }

    @Test
    void addMoodPainLogsContext_moreThan10Logs_limitedTo10() throws Exception {
        final Patient p = patient(1L);
        when(patientRepository.findById(1L)).thenReturn(Optional.of(p));
        final List<MoodPainLog> logs = new ArrayList<>();
        for (int i = 0; i < 12; i++) {
            logs.add(MoodPainLog.builder().patient(p).moodValue(i).painValue(i)
                    .note("Note " + i).timestamp(LocalDateTime.now()).build());
        }
        when(moodPainLogRepository.findByPatientOrderByTimestampDesc(p)).thenReturn(logs);
        final ChatRequest req = bareRequest();
        req.setIncludeMoodPainLogs(true);
        final String result = service.buildPatientContext(1L, req, cfg());
        assertThat(result).contains("Note 9");
        assertThat(result).doesNotContain("Note 10");
    }

    @Test
    void addMoodPainLogsContext_repoThrows_exceptionSuppressed() throws Exception {
        final Patient p = patient(1L);
        when(patientRepository.findById(1L)).thenReturn(Optional.of(p));
        when(moodPainLogRepository.findByPatientOrderByTimestampDesc(p))
                .thenThrow(new RuntimeException("DB error"));
        final ChatRequest req = bareRequest();
        req.setIncludeMoodPainLogs(true);
        assertThat(service.buildPatientContext(1L, req, cfg())).doesNotContain("RECENT MOOD/PAIN LOGS:");
    }

    // ═════════════════════════════════════════════════════════════════════════
    // addAllergiesContext
    // ═════════════════════════════════════════════════════════════════════════

    @Test
    void addAllergiesContext_emptyList_noHeader() throws Exception {
        when(patientRepository.findById(1L)).thenReturn(Optional.of(patient(1L)));
        when(allergyRepository.findByPatientId(1L)).thenReturn(Collections.emptyList());
        final ChatRequest req = bareRequest();
        req.setIncludeAllergies(true);
        assertThat(service.buildPatientContext(1L, req, cfg())).doesNotContain("KNOWN ALLERGIES:");
    }

    @Test
    void addAllergiesContext_withReactionAndSeverity_allPresent() throws Exception {
        when(patientRepository.findById(1L)).thenReturn(Optional.of(patient(1L)));
        final Allergy allergy = Allergy.builder()
                .allergen("Peanuts").reaction("Anaphylaxis")
                .severity(Allergy.AllergySeverity.SEVERE).build();
        when(allergyRepository.findByPatientId(1L)).thenReturn(List.of(allergy));
        final ChatRequest req = bareRequest();
        req.setIncludeAllergies(true);
        final String result = service.buildPatientContext(1L, req, cfg());
        assertThat(result).contains("KNOWN ALLERGIES:");
        assertThat(result).contains("(Reaction: Anaphylaxis)");
        assertThat(result).contains("[Severity: SEVERE]");
    }

    @Test
    void addAllergiesContext_withNullOptionals_noExtraFields() throws Exception {
        when(patientRepository.findById(1L)).thenReturn(Optional.of(patient(1L)));
        final Allergy allergy = Allergy.builder().allergen("Shellfish").reaction(null).severity(null).build();
        when(allergyRepository.findByPatientId(1L)).thenReturn(List.of(allergy));
        final ChatRequest req = bareRequest();
        req.setIncludeAllergies(true);
        final String result = service.buildPatientContext(1L, req, cfg());
        assertThat(result).contains("- Shellfish");
        assertThat(result).doesNotContain("Reaction:").doesNotContain("Severity:");
    }

    @Test
    void addAllergiesContext_repoThrows_exceptionSuppressed() throws Exception {
        when(patientRepository.findById(1L)).thenReturn(Optional.of(patient(1L)));
        when(allergyRepository.findByPatientId(1L)).thenThrow(new RuntimeException("DB error"));
        final ChatRequest req = bareRequest();
        req.setIncludeAllergies(true);
        assertThat(service.buildPatientContext(1L, req, cfg())).doesNotContain("KNOWN ALLERGIES:");
    }

    // ═════════════════════════════════════════════════════════════════════════
    // Documents data-source gate (WBS 3.15.7 / SAF-6)
    // ═════════════════════════════════════════════════════════════════════════

    @Test
    void shouldIncludeDocuments_flagTrue_true() throws Exception {
        final UserAIConfig c = cfg();
        c.setIncludeDocumentsByDefault(true);
        assertThat(service.shouldIncludeDocuments(c)).isTrue();
    }

    @Test
    void shouldIncludeDocuments_flagFalse_false() throws Exception {
        final UserAIConfig c = cfg();
        c.setIncludeDocumentsByDefault(false);
        assertThat(service.shouldIncludeDocuments(c)).isFalse();
    }

    @Test
    void shouldIncludeDocuments_flagNull_defaultsTrue() throws Exception {
        final UserAIConfig c = cfg();
        c.setIncludeDocumentsByDefault(null);
        assertThat(service.shouldIncludeDocuments(c)).isTrue();
    }

    @Test
    void buildPatientContext_documentsExcluded_uploadedFilesOmitted() throws Exception {
        when(patientRepository.findById(1L)).thenReturn(Optional.of(patient(1L)));
        final UploadedFileDTO file = UploadedFileDTO.builder()
                .filename("report.pdf").contentType("application/pdf").build();
        final ChatRequest req = bareRequest();
        req.setUploadedFiles(List.of(file));
        final UserAIConfig c = cfg();
        c.setIncludeDocumentsByDefault(false);
        final String result = service.buildPatientContext(1L, req, c);
        assertThat(result).doesNotContain("UPLOADED FILES:");
        assertThat(result).doesNotContain("report.pdf");
    }

    @Test
    void buildPatientContext_documentsIncluded_uploadedFilesPresent() throws Exception {
        when(patientRepository.findById(1L)).thenReturn(Optional.of(patient(1L)));
        final UploadedFileDTO file = UploadedFileDTO.builder()
                .filename("report.pdf").contentType("application/pdf").build();
        when(documentProcessingService.extractTextContent(file)).thenReturn("PDF text");
        final ChatRequest req = bareRequest();
        req.setUploadedFiles(List.of(file));
        final UserAIConfig c = cfg();
        c.setIncludeDocumentsByDefault(true);
        final String result = service.buildPatientContext(1L, req, c);
        assertThat(result).contains("UPLOADED FILES:").contains("report.pdf").contains("PDF text");
    }
}
