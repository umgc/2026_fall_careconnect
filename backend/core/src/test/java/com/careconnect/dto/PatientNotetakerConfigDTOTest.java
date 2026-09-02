package com.careconnect.dto;

import com.careconnect.model.PatientNotetakerConfig;
import com.careconnect.model.PatientNotetakerKeyword;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.time.LocalDateTime;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class PatientNotetakerConfigDTOTest {

    private static final LocalDateTime NOW = LocalDateTime.of(2026, 1, 15, 10, 30);
    private static final List<PatientNotetakerKeyword> KEYWORDS = List.of(
            PatientNotetakerKeyword.builder()
                    .keyword("pain")
                    .eventType(PatientNotetakerKeyword.EventType.ALERT)
                    .build()
    );
    @Mock
    private PatientNotetakerConfig mockConfig;

    // ─── No-arg constructor ───────────────────────────────────────────────────

    @Test
    void noArgConstructor_createsInstance() throws Exception {
        final PatientNotetakerConfigDTO dto = new PatientNotetakerConfigDTO();

        assertThat(dto).isNotNull();
        assertThat(dto.getId()).isNull();
        assertThat(dto.getPatientId()).isNull();
        assertThat(dto.getIsEnabled()).isNull();
        assertThat(dto.getPermitCaregiverAccess()).isNull();
        assertThat(dto.getTriggerKeywords()).isNull();
        assertThat(dto.getUpdatedAt()).isNull();
    }

    // ─── All-args constructor ─────────────────────────────────────────────────

    @Test
    void allArgsConstructor_setsAllFields() throws Exception {
        final PatientNotetakerConfigDTO dto = new PatientNotetakerConfigDTO(
                1L, 2L, true, false, KEYWORDS, NOW);

        assertThat(dto.getId()).isEqualTo(1L);
        assertThat(dto.getPatientId()).isEqualTo(2L);
        assertThat(dto.getIsEnabled()).isTrue();
        assertThat(dto.getPermitCaregiverAccess()).isFalse();
        assertThat(dto.getTriggerKeywords()).isEqualTo(KEYWORDS);
        assertThat(dto.getUpdatedAt()).isEqualTo(NOW);
    }

    // ─── PatientNotetakerConfig constructor: non-null ─────────────────────────

    @Test
    void configConstructor_nonNull_copiesFields() throws Exception {
        when(mockConfig.getId()).thenReturn(10L);
        when(mockConfig.getPatientId()).thenReturn(20L);
        when(mockConfig.getIsEnabled()).thenReturn(true);
        when(mockConfig.getPermitCaregiverAccess()).thenReturn(false);
        when(mockConfig.getTriggerKeywords()).thenReturn(KEYWORDS);
        when(mockConfig.getUpdatedAt()).thenReturn(NOW);

        final PatientNotetakerConfigDTO dto = new PatientNotetakerConfigDTO(mockConfig);

        assertThat(dto.getId()).isEqualTo(10L);
        assertThat(dto.getPatientId()).isEqualTo(20L);
        assertThat(dto.getIsEnabled()).isTrue();
        assertThat(dto.getPermitCaregiverAccess()).isFalse();
        assertThat(dto.getTriggerKeywords()).isEqualTo(KEYWORDS);
        assertThat(dto.getUpdatedAt()).isEqualTo(NOW);
    }

    // ─── PatientNotetakerConfig constructor: null ─────────────────────────────

    @Test
    void configConstructor_null_setsAllFieldsToNull() throws Exception {
        final PatientNotetakerConfigDTO dto = new PatientNotetakerConfigDTO((PatientNotetakerConfig) null);

        assertThat(dto.getId()).isNull();
        assertThat(dto.getPatientId()).isNull();
        assertThat(dto.getIsEnabled()).isNull();
        assertThat(dto.getPermitCaregiverAccess()).isNull();
        assertThat(dto.getTriggerKeywords()).isNull();
        assertThat(dto.getUpdatedAt()).isNull();
    }

    // ─── Builder ──────────────────────────────────────────────────────────────

    @Test
    void builder_allFields_setsCorrectly() throws Exception {
        final PatientNotetakerConfigDTO dto = PatientNotetakerConfigDTO.builder()
                .id(5L)
                .patientId(6L)
                .isEnabled(false)
                .permitCaregiverAccess(true)
                .triggerKeywords(KEYWORDS)
                .updatedAt(NOW)
                .build();

        assertThat(dto.getId()).isEqualTo(5L);
        assertThat(dto.getPatientId()).isEqualTo(6L);
        assertThat(dto.getIsEnabled()).isFalse();
        assertThat(dto.getPermitCaregiverAccess()).isTrue();
        assertThat(dto.getTriggerKeywords()).isEqualTo(KEYWORDS);
        assertThat(dto.getUpdatedAt()).isEqualTo(NOW);
    }

    @Test
    void builder_staticMethod_returnsBuilderInstance() throws Exception {
        final PatientNotetakerConfigDTO.PatientNotetakerConfigDTOBuilder builder = PatientNotetakerConfigDTO.builder();
        assertThat(builder).isNotNull();
    }

    // ─── Setters ──────────────────────────────────────────────────────────────

    @Test
    void setters_updateFields() throws Exception {
        final PatientNotetakerConfigDTO dto = new PatientNotetakerConfigDTO();

        dto.setId(99L);
        dto.setPatientId(100L);
        dto.setIsEnabled(true);
        dto.setPermitCaregiverAccess(true);
        dto.setTriggerKeywords(KEYWORDS);
        dto.setUpdatedAt(NOW);

        assertThat(dto.getId()).isEqualTo(99L);
        assertThat(dto.getPatientId()).isEqualTo(100L);
        assertThat(dto.getIsEnabled()).isTrue();
        assertThat(dto.getPermitCaregiverAccess()).isTrue();
        assertThat(dto.getTriggerKeywords()).isEqualTo(KEYWORDS);
        assertThat(dto.getUpdatedAt()).isEqualTo(NOW);
    }

    // ─── toEntity() ───────────────────────────────────────────────────────────

    @Test
    void toEntity_mapsAllFieldsCorrectly() throws Exception {
        final PatientNotetakerConfigDTO dto = new PatientNotetakerConfigDTO(
                3L, 4L, true, false, KEYWORDS, NOW);

        final PatientNotetakerConfig entity = dto.toEntity();

        assertThat(entity.getId()).isEqualTo(3L);
        assertThat(entity.getPatientId()).isEqualTo(4L);
        assertThat(entity.getIsEnabled()).isTrue();
        assertThat(entity.getPermitCaregiverAccess()).isFalse();
        assertThat(entity.getTriggerKeywords()).isEqualTo(KEYWORDS);
        assertThat(entity.getUpdatedAt()).isEqualTo(NOW);
    }
}
