package com.careconnect.dto;

import com.careconnect.model.PatientNote;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.time.LocalDateTime;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class PatientNoteDTOTest {

    private static final LocalDateTime NOW = LocalDateTime.of(2026, 1, 15, 10, 30);
    @Mock
    private PatientNote mockNote;

    // ─── No-arg constructor ───────────────────────────────────────────────────

    @Test
    void noArgConstructor_createsInstance() throws Exception {
        final PatientNoteDTO dto = new PatientNoteDTO();

        assertThat(dto).isNotNull();
        assertThat(dto.getId()).isNull();
        assertThat(dto.getPatientId()).isNull();
        assertThat(dto.getNote()).isNull();
        assertThat(dto.getAiSummary()).isNull();
        assertThat(dto.getCreatedAt()).isNull();
        assertThat(dto.getUpdatedAt()).isNull();
    }

    // ─── All-args constructor ─────────────────────────────────────────────────

    @Test
    void allArgsConstructor_setsAllFields() throws Exception {
        final PatientNoteDTO dto = new PatientNoteDTO(
                1L, 2L, "note text", "ai summary", NOW, NOW.plusDays(1));

        assertThat(dto.getId()).isEqualTo(1L);
        assertThat(dto.getPatientId()).isEqualTo(2L);
        assertThat(dto.getNote()).isEqualTo("note text");
        assertThat(dto.getAiSummary()).isEqualTo("ai summary");
        assertThat(dto.getCreatedAt()).isEqualTo(NOW);
        assertThat(dto.getUpdatedAt()).isEqualTo(NOW.plusDays(1));
    }

    // ─── PatientNote constructor: non-null ────────────────────────────────────

    @Test
    void patientNoteConstructor_nonNull_copiesFields() throws Exception {
        when(mockNote.getId()).thenReturn(10L);
        when(mockNote.getPatientId()).thenReturn(20L);
        when(mockNote.getNote()).thenReturn("some note");
        when(mockNote.getAiSummary()).thenReturn("summary");
        when(mockNote.getCreatedAt()).thenReturn(NOW);
        when(mockNote.getUpdatedAt()).thenReturn(NOW.plusHours(1));

        final PatientNoteDTO dto = new PatientNoteDTO(mockNote);

        assertThat(dto.getId()).isEqualTo(10L);
        assertThat(dto.getPatientId()).isEqualTo(20L);
        assertThat(dto.getNote()).isEqualTo("some note");
        assertThat(dto.getAiSummary()).isEqualTo("summary");
        assertThat(dto.getCreatedAt()).isEqualTo(NOW);
        assertThat(dto.getUpdatedAt()).isEqualTo(NOW.plusHours(1));
    }

    // ─── PatientNote constructor: null ────────────────────────────────────────

    @Test
    void patientNoteConstructor_null_setsAllFieldsToNull() throws Exception {
        final PatientNoteDTO dto = new PatientNoteDTO((PatientNote) null);

        assertThat(dto.getId()).isNull();
        assertThat(dto.getPatientId()).isNull();
        assertThat(dto.getNote()).isNull();
        assertThat(dto.getAiSummary()).isNull();
        assertThat(dto.getCreatedAt()).isNull();
        assertThat(dto.getUpdatedAt()).isNull();
    }

    // ─── Builder ──────────────────────────────────────────────────────────────

    @Test
    void builder_allFields_setsCorrectly() throws Exception {
        final PatientNoteDTO dto = PatientNoteDTO.builder()
                .id(5L)
                .patientId(6L)
                .note("builder note")
                .aiSummary("builder summary")
                .createdAt(NOW)
                .updatedAt(NOW.plusDays(2))
                .build();

        assertThat(dto.getId()).isEqualTo(5L);
        assertThat(dto.getPatientId()).isEqualTo(6L);
        assertThat(dto.getNote()).isEqualTo("builder note");
        assertThat(dto.getAiSummary()).isEqualTo("builder summary");
        assertThat(dto.getCreatedAt()).isEqualTo(NOW);
        assertThat(dto.getUpdatedAt()).isEqualTo(NOW.plusDays(2));
    }

    @Test
    void builder_staticMethod_returnsBuilderInstance() throws Exception {
        final PatientNoteDTO.PatientNoteDTOBuilder builder = PatientNoteDTO.builder();
        assertThat(builder).isNotNull();
    }

    // ─── Setters ──────────────────────────────────────────────────────────────

    @Test
    void setters_updateFields() throws Exception {
        final PatientNoteDTO dto = new PatientNoteDTO();

        dto.setId(99L);
        dto.setPatientId(100L);
        dto.setNote("updated note");
        dto.setAiSummary("updated summary");
        dto.setCreatedAt(NOW);
        dto.setUpdatedAt(NOW.plusDays(3));

        assertThat(dto.getId()).isEqualTo(99L);
        assertThat(dto.getPatientId()).isEqualTo(100L);
        assertThat(dto.getNote()).isEqualTo("updated note");
        assertThat(dto.getAiSummary()).isEqualTo("updated summary");
        assertThat(dto.getCreatedAt()).isEqualTo(NOW);
        assertThat(dto.getUpdatedAt()).isEqualTo(NOW.plusDays(3));
    }

    // ─── toEntity() ───────────────────────────────────────────────────────────

    @Test
    void toEntity_mapsAllFieldsCorrectly() throws Exception {
        final PatientNoteDTO dto = new PatientNoteDTO(
                3L, 4L, "entity note", "entity summary", NOW, NOW.plusDays(1));

        final PatientNote entity = dto.toEntity();

        assertThat(entity.getId()).isEqualTo(3L);
        assertThat(entity.getPatientId()).isEqualTo(4L);
        assertThat(entity.getNote()).isEqualTo("entity note");
        assertThat(entity.getAiSummary()).isEqualTo("entity summary");
        assertThat(entity.getCreatedAt()).isEqualTo(NOW);
        assertThat(entity.getUpdatedAt()).isEqualTo(NOW.plusDays(1));
    }
}
