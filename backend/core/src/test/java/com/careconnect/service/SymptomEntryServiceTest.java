package com.careconnect.service;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

import java.time.Instant;
import java.util.List;
import java.util.Optional;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.MockitoAnnotations;

import com.careconnect.dto.SymptomEntryDTO;
import com.careconnect.model.Patient;
import com.careconnect.model.SymptomEntry;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.SymptomEntryRepository;

/**
 * Unit tests for {@link SymptomEntryService}.
 *
 * <p>All external dependencies (repositories) are mocked with Mockito so these
 * tests validate the service's business logic in isolation — no database or
 * Spring context is required.</p>
 */
class SymptomEntryServiceTest {

    @Mock
    private SymptomEntryRepository symptomEntryRepository;

    @Mock
    private PatientRepository patientRepository;

    @InjectMocks
    private SymptomEntryService symptomEntryService;

    /**
     * Shared patient instance reused across tests.
     */
    private Patient patient;

    @BeforeEach
    void setUp() throws Exception {
        MockitoAnnotations.openMocks(this);
        patient = Patient.builder().id(1L).firstName("Jane").lastName("Doe").build();
    }

    // ==========================================================================
    // createSymptom
    // ==========================================================================

    @Test
    @DisplayName("createSymptom: persists a new entry and returns mapped DTO with all fields")
    void testCreateSymptom_happyPath() throws Exception {
        // Given a valid patient and a fully-populated DTO, the service must
        // save the entry and return a DTO that mirrors all input fields.
        final Instant now = Instant.now();
        final SymptomEntryDTO dto = SymptomEntryDTO.builder()
                .patientId(1L)
                .symptomKey("headache")
                .symptomValue("mild")
                .severity(2)
                .takenAt(now)
                .build();

        when(patientRepository.findById(1L)).thenReturn(Optional.of(patient));
        when(symptomEntryRepository.save(any(SymptomEntry.class))).thenAnswer(inv -> {
            final SymptomEntry e = inv.getArgument(0);
            e.setId(10L);
            return e;
        });

        final SymptomEntryDTO result = symptomEntryService.createSymptom(dto);

        assertNotNull(result);
        assertEquals(10L, result.id());
        assertEquals(1L, result.patientId());
        assertEquals("headache", result.symptomKey());
        assertEquals("mild", result.symptomValue());
        assertEquals(2, result.severity());
        assertEquals(now, result.takenAt());
        assertTrue(result.completed());
        verify(patientRepository).findById(1L);
        verify(symptomEntryRepository).save(any(SymptomEntry.class));
    }

    @Test
    @DisplayName("createSymptom: uses current time when takenAt is null in the DTO")
    void testCreateSymptom_nullTakenAt_usesNow() throws Exception {
        // When the caller omits takenAt, the service must substitute Instant.now()
        // so the saved entry always has a valid timestamp.
        final SymptomEntryDTO dto = SymptomEntryDTO.builder()
                .patientId(1L)
                .symptomKey("cough")
                .symptomValue("dry")
                .takenAt(null)   // explicitly null
                .build();

        when(patientRepository.findById(1L)).thenReturn(Optional.of(patient));
        when(symptomEntryRepository.save(any(SymptomEntry.class))).thenAnswer(inv -> {
            final SymptomEntry e = inv.getArgument(0);
            e.setId(11L);
            return e;
        });

        final Instant before = Instant.now();
        final SymptomEntryDTO result = symptomEntryService.createSymptom(dto);
        final Instant after = Instant.now();

        assertNotNull(result.takenAt());
        // The auto-assigned timestamp must fall within the test execution window
        assertFalse(result.takenAt().isBefore(before));
        assertFalse(result.takenAt().isAfter(after));
    }

    @Test
    @DisplayName("createSymptom: throws IllegalArgumentException when the patient does not exist")
    void testCreateSymptom_patientNotFound_throws() throws Exception {
        // A symptom entry cannot exist without a valid patient reference;
        // the service must surface this as an IllegalArgumentException.
        final SymptomEntryDTO dto = SymptomEntryDTO.builder()
                .patientId(99L)
                .symptomKey("fever")
                .build();

        when(patientRepository.findById(99L)).thenReturn(Optional.empty());

        final IllegalArgumentException ex = assertThrows(
                IllegalArgumentException.class,
                () -> symptomEntryService.createSymptom(dto));

        assertTrue(ex.getMessage().contains("99"));
        verify(symptomEntryRepository, never()).save(any());
    }

    @Test
    @DisplayName("createSymptom: sets completed=true regardless of the DTO value")
    void testCreateSymptom_alwaysSetsCompleted() throws Exception {
        // The service always marks a newly created entry as completed=true;
        // the DTO's completed field (if any) is not consulted.
        final SymptomEntryDTO dto = SymptomEntryDTO.builder()
                .patientId(1L)
                .symptomKey("nausea")
                .symptomValue("moderate")
                .takenAt(Instant.now())
                .completed(false)   // caller's value — should be ignored
                .build();

        when(patientRepository.findById(1L)).thenReturn(Optional.of(patient));
        when(symptomEntryRepository.save(any(SymptomEntry.class))).thenAnswer(inv -> inv.getArgument(0));

        final SymptomEntryDTO result = symptomEntryService.createSymptom(dto);

        assertTrue(result.completed());
    }

    // ==========================================================================
    // getSymptomsForPatient
    // ==========================================================================

    @Test
    @DisplayName("getSymptomsForPatient: returns only entries belonging to the requested patient")
    void testGetSymptomsForPatient_filtersCorrectly() throws Exception {
        // The repository returns all entries; the service must filter to the
        // requested patient ID so unrelated entries are excluded.
        final Patient other = Patient.builder().id(2L).build();

        final SymptomEntry match = SymptomEntry.builder()
                .id(1L).patient(patient)
                .symptomKey("headache").symptomValue("mild")
                .takenAt(Instant.now()).completed(true).build();

        final SymptomEntry noMatch = SymptomEntry.builder()
                .id(2L).patient(other)
                .symptomKey("fever").symptomValue("high")
                .takenAt(Instant.now()).completed(true).build();

        when(symptomEntryRepository.findAll()).thenReturn(List.of(match, noMatch));

        final List<SymptomEntryDTO> result = symptomEntryService.getSymptomsForPatient(1L);

        assertEquals(1, result.size());
        assertEquals(1L, result.get(0).id());
        assertEquals("headache", result.get(0).symptomKey());
        verify(symptomEntryRepository).findAll();
    }

    @Test
    @DisplayName("getSymptomsForPatient: returns an empty list when no entries exist for the patient")
    void testGetSymptomsForPatient_noMatches_returnsEmpty() throws Exception {
        // If the patient has no recorded symptoms the result must be an empty
        // list, not null or an exception.
        final Patient other = Patient.builder().id(2L).build();
        final SymptomEntry entry = SymptomEntry.builder()
                .id(1L).patient(other)
                .symptomKey("cough").takenAt(Instant.now()).completed(true).build();

        when(symptomEntryRepository.findAll()).thenReturn(List.of(entry));

        final List<SymptomEntryDTO> result = symptomEntryService.getSymptomsForPatient(1L);

        assertNotNull(result);
        assertTrue(result.isEmpty());
    }

    @Test
    @DisplayName("getSymptomsForPatient: returns all entries when every entry belongs to the patient")
    void testGetSymptomsForPatient_multipleMatches_returnsAll() throws Exception {
        // All three entries belong to patient 1; all must be included in order.
        final SymptomEntry e1 = SymptomEntry.builder().id(1L).patient(patient)
                .symptomKey("headache").takenAt(Instant.now()).completed(true).build();
        final SymptomEntry e2 = SymptomEntry.builder().id(2L).patient(patient)
                .symptomKey("fatigue").takenAt(Instant.now()).completed(true).build();
        final SymptomEntry e3 = SymptomEntry.builder().id(3L).patient(patient)
                .symptomKey("nausea").takenAt(Instant.now()).completed(true).build();

        when(symptomEntryRepository.findAll()).thenReturn(List.of(e1, e2, e3));

        final List<SymptomEntryDTO> result = symptomEntryService.getSymptomsForPatient(1L);

        assertEquals(3, result.size());
    }

    @Test
    @DisplayName("getSymptomsForPatient: maps severity and symptomValue fields correctly into the DTO")
    void testGetSymptomsForPatient_mapsAllDtoFields() throws Exception {
        // Verify that the private mapToDTO helper correctly transfers all fields
        // by inspecting the returned DTO's individual properties.
        final Instant ts = Instant.parse("2025-06-01T10:00:00Z");
        final SymptomEntry entry = SymptomEntry.builder()
                .id(5L).patient(patient)
                .symptomKey("pain").symptomValue("severe")
                .severity(4).takenAt(ts).completed(true).build();

        when(symptomEntryRepository.findAll()).thenReturn(List.of(entry));

        final SymptomEntryDTO dto = symptomEntryService.getSymptomsForPatient(1L).get(0);

        assertEquals(5L, dto.id());
        assertEquals(1L, dto.patientId());
        assertEquals("pain", dto.symptomKey());
        assertEquals("severe", dto.symptomValue());
        assertEquals(4, dto.severity());
        assertEquals(ts, dto.takenAt());
        assertTrue(dto.completed());
    }

    // ==========================================================================
    // deleteSymptom
    // ==========================================================================

    @Test
    @DisplayName("deleteSymptom: calls deleteById when the entry exists")
    void testDeleteSymptom_exists_deletesEntry() throws Exception {
        // The happy path: the entry is present, so the service must delegate
        // to the repository's deleteById without throwing.
        when(symptomEntryRepository.existsById(1L)).thenReturn(true);

        symptomEntryService.deleteSymptom(1L);

        verify(symptomEntryRepository).deleteById(1L);
    }

    @Test
    @DisplayName("deleteSymptom: throws IllegalArgumentException when the entry does not exist")
    void testDeleteSymptom_notFound_throws() throws Exception {
        // A delete request for a non-existent entry must fail fast with a
        // descriptive IllegalArgumentException before any delete is attempted.
        when(symptomEntryRepository.existsById(99L)).thenReturn(false);

        final IllegalArgumentException ex = assertThrows(
                IllegalArgumentException.class,
                () -> symptomEntryService.deleteSymptom(99L));

        assertTrue(ex.getMessage().contains("99"));
        verify(symptomEntryRepository, never()).deleteById(any());
    }

    @Test
    @DisplayName("deleteSymptom: does not call deleteById when the entry is absent")
    void testDeleteSymptom_notFound_noDeletion() throws Exception {
        // Verify no side effects occur beyond the exception when the entry is missing.
        when(symptomEntryRepository.existsById(42L)).thenReturn(false);

        assertThrows(IllegalArgumentException.class,
                () -> symptomEntryService.deleteSymptom(42L));

        verify(symptomEntryRepository, never()).deleteById(42L);
    }
}
