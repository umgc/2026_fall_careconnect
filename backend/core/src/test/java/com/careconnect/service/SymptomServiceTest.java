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

import com.careconnect.dto.SymptomDTO;
import com.careconnect.model.Patient;
import com.careconnect.model.SymptomEntry;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.SymptomEntryRepository;

/**
 * Unit tests for {@link SymptomService}.
 *
 * <p>All repository dependencies are mocked with Mockito so the service's
 * business logic is validated in isolation — no database or Spring context
 * is required.</p>
 */
class SymptomServiceTest {

    @Mock
    private SymptomEntryRepository symptomRepo;

    @Mock
    private PatientRepository patientRepo;

    @InjectMocks
    private SymptomService symptomService;

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
    // create
    // ==========================================================================

    @Test
    @DisplayName("create: saves entry and returns DTO with all fields mapped correctly")
    void testCreate_happyPath() throws Exception {
        // Given a valid patient and a fully-populated DTO, the service must
        // save the entry and return a DTO that mirrors every input field.
        final Instant ts = Instant.parse("2025-06-01T10:00:00Z");
        final SymptomDTO dto = SymptomDTO.builder()
                .patientId(1L)
                .symptomKey("headache")
                .symptomValue("mild")
                .severity(2)
                .notes("patient reports tension headache")
                .completed(true)
                .takenAt(ts)
                .build();

        when(patientRepo.findById(1L)).thenReturn(Optional.of(patient));
        when(symptomRepo.save(any(SymptomEntry.class))).thenAnswer(inv -> {
            final SymptomEntry e = inv.getArgument(0);
            e.setId(10L);
            return e;
        });

        final SymptomDTO result = symptomService.create(dto);

        assertNotNull(result);
        assertEquals(10L, result.id());
        assertEquals(1L, result.patientId());
        assertEquals("headache", result.symptomKey());
        assertEquals("mild", result.symptomValue());
        assertEquals(2, result.severity());
        assertEquals("patient reports tension headache", result.notes());
        assertTrue(result.completed());
        assertEquals(ts, result.takenAt());
        verify(patientRepo).findById(1L);
        verify(symptomRepo).save(any(SymptomEntry.class));
    }

    @Test
    @DisplayName("create: uses Instant.now() when takenAt is null in the DTO")
    void testCreate_nullTakenAt_usesNow() throws Exception {
        // When the caller omits takenAt the service must substitute Instant.now()
        // so the persisted entry always has a valid timestamp.
        final SymptomDTO dto = SymptomDTO.builder()
                .patientId(1L)
                .symptomKey("cough")
                .takenAt(null)
                .build();

        when(patientRepo.findById(1L)).thenReturn(Optional.of(patient));
        when(symptomRepo.save(any(SymptomEntry.class))).thenAnswer(inv -> {
            final SymptomEntry e = inv.getArgument(0);
            e.setId(11L);
            return e;
        });

        final Instant before = Instant.now();
        final SymptomDTO result = symptomService.create(dto);
        final Instant after = Instant.now();

        assertNotNull(result.takenAt());
        // The auto-assigned timestamp must fall within the test execution window
        assertFalse(result.takenAt().isBefore(before));
        assertFalse(result.takenAt().isAfter(after));
    }

    @Test
    @DisplayName("create: defaults completed to true when the DTO provides null")
    void testCreate_nullCompleted_defaultsTrue() throws Exception {
        // When the caller does not specify a completed flag the service must
        // default it to true, matching the business rule for new entries.
        final SymptomDTO dto = SymptomDTO.builder()
                .patientId(1L)
                .symptomKey("fever")
                .completed(null)
                .takenAt(Instant.now())
                .build();

        when(patientRepo.findById(1L)).thenReturn(Optional.of(patient));
        when(symptomRepo.save(any(SymptomEntry.class))).thenAnswer(inv -> inv.getArgument(0));

        final SymptomDTO result = symptomService.create(dto);

        assertTrue(result.completed());
    }

    @Test
    @DisplayName("create: preserves completed=false when explicitly set in the DTO")
    void testCreate_completedFalse_preserved() throws Exception {
        // An explicit false must survive — the default-true logic must not
        // override a value the caller intentionally provided.
        final SymptomDTO dto = SymptomDTO.builder()
                .patientId(1L)
                .symptomKey("rash")
                .completed(false)
                .takenAt(Instant.now())
                .build();

        when(patientRepo.findById(1L)).thenReturn(Optional.of(patient));
        when(symptomRepo.save(any(SymptomEntry.class))).thenAnswer(inv -> inv.getArgument(0));

        final SymptomDTO result = symptomService.create(dto);

        assertFalse(result.completed());
    }

    @Test
    @DisplayName("create: throws IllegalArgumentException when patient does not exist")
    void testCreate_patientNotFound_throws() throws Exception {
        // The service must refuse to create an entry without a valid patient
        // and must not call save under any circumstances.
        final SymptomDTO dto = SymptomDTO.builder().patientId(99L).symptomKey("pain").build();

        when(patientRepo.findById(99L)).thenReturn(Optional.empty());

        final IllegalArgumentException ex = assertThrows(
                IllegalArgumentException.class,
                () -> symptomService.create(dto));

        assertTrue(ex.getMessage().contains("99"));
        verify(symptomRepo, never()).save(any());
    }

    // ==========================================================================
    // update
    // ==========================================================================

    @Test
    @DisplayName("update: applies all non-null DTO fields to the existing entry")
    void testUpdate_allFieldsChanged() throws Exception {
        // Every non-null field in the patch DTO must overwrite the stored value.
        final Instant newTs = Instant.parse("2025-07-01T08:00:00Z");
        final SymptomEntry existing = SymptomEntry.builder()
                .id(1L).patient(patient)
                .symptomKey("old-key").symptomValue("old-value")
                .severity(1).notes("old note").completed(false)
                .takenAt(Instant.parse("2025-01-01T00:00:00Z"))
                .build();

        when(symptomRepo.findById(1L)).thenReturn(Optional.of(existing));
        when(symptomRepo.save(any(SymptomEntry.class))).thenAnswer(inv -> inv.getArgument(0));

        final SymptomDTO patch = SymptomDTO.builder()
                .symptomKey("new-key")
                .symptomValue("new-value")
                .severity(5)
                .notes("updated note")
                .completed(true)
                .takenAt(newTs)
                .build();

        final SymptomDTO result = symptomService.update(1L, patch);

        assertEquals("new-key", result.symptomKey());
        assertEquals("new-value", result.symptomValue());
        assertEquals(5, result.severity());
        assertEquals("updated note", result.notes());
        assertTrue(result.completed());
        assertEquals(newTs, result.takenAt());
        verify(symptomRepo).save(existing);
    }

    @Test
    @DisplayName("update: leaves existing fields unchanged when DTO fields are null (partial patch)")
    void testUpdate_nullFieldsNotOverwritten() throws Exception {
        // Null fields in the patch DTO represent "no change"; the service
        // must leave the stored values untouched for those fields.
        final SymptomEntry existing = SymptomEntry.builder()
                .id(2L).patient(patient)
                .symptomKey("headache").symptomValue("mild")
                .severity(3).notes("original note").completed(true)
                .takenAt(Instant.parse("2025-03-01T00:00:00Z"))
                .build();

        when(symptomRepo.findById(2L)).thenReturn(Optional.of(existing));
        when(symptomRepo.save(any(SymptomEntry.class))).thenAnswer(inv -> inv.getArgument(0));

        // Only severity changes; all other fields are null (omitted)
        final SymptomDTO patch = SymptomDTO.builder().severity(5).build();

        final SymptomDTO result = symptomService.update(2L, patch);

        assertEquals("headache", result.symptomKey());   // unchanged
        assertEquals("mild", result.symptomValue()); // unchanged
        assertEquals("original note", result.notes());        // unchanged
        assertTrue(result.completed());                         // unchanged
        assertEquals(5, result.severity());                    // updated
    }

    @Test
    @DisplayName("update: throws IllegalArgumentException when the symptom entry does not exist")
    void testUpdate_notFound_throws() throws Exception {
        // An update targeting an unknown ID must fail with a descriptive
        // exception before any save is attempted.
        when(symptomRepo.findById(99L)).thenReturn(Optional.empty());

        final SymptomDTO patch = SymptomDTO.builder().symptomKey("cough").build();

        final IllegalArgumentException ex = assertThrows(
                IllegalArgumentException.class,
                () -> symptomService.update(99L, patch));

        assertTrue(ex.getMessage().contains("99"));
        verify(symptomRepo, never()).save(any());
    }

    @Test
    @DisplayName("update: returns updated DTO with patientId correctly mapped from the entity")
    void testUpdate_returnsDtoWithPatientId() throws Exception {
        // The patientId must be taken from the existing entity's patient
        // relationship, not from the patch DTO (which has no patientId).
        final SymptomEntry existing = SymptomEntry.builder()
                .id(3L).patient(patient)
                .symptomKey("nausea").takenAt(Instant.now()).completed(true)
                .build();

        when(symptomRepo.findById(3L)).thenReturn(Optional.of(existing));
        when(symptomRepo.save(any(SymptomEntry.class))).thenAnswer(inv -> inv.getArgument(0));

        final SymptomDTO patch = SymptomDTO.builder().symptomValue("severe").build();

        final SymptomDTO result = symptomService.update(3L, patch);

        assertEquals(1L, result.patientId());
    }

    // ==========================================================================
    // get
    // ==========================================================================

    @Test
    @DisplayName("get: returns a populated Optional<SymptomDTO> when the entry exists")
    void testGet_found() throws Exception {
        // The returned Optional must contain a DTO with all fields from the entity.
        final SymptomEntry entry = SymptomEntry.builder()
                .id(5L).patient(patient)
                .symptomKey("fatigue").symptomValue("chronic")
                .severity(4).takenAt(Instant.now()).completed(true)
                .build();

        when(symptomRepo.findById(5L)).thenReturn(Optional.of(entry));

        final Optional<SymptomDTO> result = symptomService.get(5L);

        assertTrue(result.isPresent());
        assertEquals(5L, result.get().id());
        assertEquals("fatigue", result.get().symptomKey());
        verify(symptomRepo).findById(5L);
    }

    @Test
    @DisplayName("get: returns an empty Optional when the entry does not exist")
    void testGet_notFound() throws Exception {
        // A missing entry must produce Optional.empty(), not throw or return null.
        when(symptomRepo.findById(99L)).thenReturn(Optional.empty());

        final Optional<SymptomDTO> result = symptomService.get(99L);

        assertTrue(result.isEmpty());
    }

    // ==========================================================================
    // listByPatient
    // ==========================================================================

    @Test
    @DisplayName("listByPatient: returns ordered DTOs for all entries belonging to the patient")
    void testListByPatient_returnsMappedList() throws Exception {
        // The repository already returns entries in descending takenAt order;
        // the service must map every entry to a DTO and preserve that order.
        final SymptomEntry e1 = SymptomEntry.builder().id(1L).patient(patient)
                .symptomKey("headache").takenAt(Instant.parse("2025-06-02T00:00:00Z"))
                .completed(true).build();
        final SymptomEntry e2 = SymptomEntry.builder().id(2L).patient(patient)
                .symptomKey("fatigue").takenAt(Instant.parse("2025-06-01T00:00:00Z"))
                .completed(true).build();

        when(symptomRepo.findByPatientIdOrderByTakenAtDesc(1L)).thenReturn(List.of(e1, e2));

        final List<SymptomDTO> result = symptomService.listByPatient(1L);

        assertEquals(2, result.size());
        assertEquals("headache", result.get(0).symptomKey());
        assertEquals("fatigue", result.get(1).symptomKey());
        verify(symptomRepo).findByPatientIdOrderByTakenAtDesc(1L);
    }

    @Test
    @DisplayName("listByPatient: returns an empty list when the patient has no symptom entries")
    void testListByPatient_noEntries_returnsEmpty() throws Exception {
        // An empty repository result must produce an empty list, not null or an exception.
        when(symptomRepo.findByPatientIdOrderByTakenAtDesc(2L)).thenReturn(List.of());

        final List<SymptomDTO> result = symptomService.listByPatient(2L);

        assertNotNull(result);
        assertTrue(result.isEmpty());
    }

    @Test
    @DisplayName("listByPatient: maps all DTO fields from each entity correctly")
    void testListByPatient_fieldMapping() throws Exception {
        // Spot-check that the private toDto helper transfers every field
        // correctly when called via listByPatient.
        final Instant ts = Instant.parse("2025-05-15T12:00:00Z");
        final SymptomEntry entry = SymptomEntry.builder()
                .id(7L).patient(patient)
                .symptomKey("pain").symptomValue("acute")
                .severity(5).notes("clinical note")
                .takenAt(ts).completed(false).build();

        when(symptomRepo.findByPatientIdOrderByTakenAtDesc(1L)).thenReturn(List.of(entry));

        final SymptomDTO dto = symptomService.listByPatient(1L).get(0);

        assertEquals(7L, dto.id());
        assertEquals(1L, dto.patientId());
        assertEquals("pain", dto.symptomKey());
        assertEquals("acute", dto.symptomValue());
        assertEquals(5, dto.severity());
        assertEquals("clinical note", dto.notes());
        assertEquals(ts, dto.takenAt());
        assertFalse(dto.completed());
    }

    // ==========================================================================
    // delete
    // ==========================================================================

    @Test
    @DisplayName("delete: calls deleteById when the entry exists")
    void testDelete_exists_deletesEntry() throws Exception {
        // The happy path: existsById returns true, so the service delegates to deleteById.
        when(symptomRepo.existsById(1L)).thenReturn(true);

        symptomService.delete(1L);

        verify(symptomRepo).deleteById(1L);
    }

    @Test
    @DisplayName("delete: throws IllegalArgumentException when the entry does not exist")
    void testDelete_notFound_throws() throws Exception {
        // A delete on a non-existent entry must surface as a descriptive
        // IllegalArgumentException before any deletion is attempted.
        when(symptomRepo.existsById(99L)).thenReturn(false);

        final IllegalArgumentException ex = assertThrows(
                IllegalArgumentException.class,
                () -> symptomService.delete(99L));

        assertTrue(ex.getMessage().contains("99"));
        verify(symptomRepo, never()).deleteById(any());
    }

    @Test
    @DisplayName("delete: does not call deleteById when the entry is absent")
    void testDelete_notFound_noSideEffects() throws Exception {
        // Verify no repository mutation occurs when the guard throws.
        when(symptomRepo.existsById(42L)).thenReturn(false);

        assertThrows(IllegalArgumentException.class, () -> symptomService.delete(42L));

        verify(symptomRepo, never()).deleteById(42L);
    }
}
