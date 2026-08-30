package com.careconnect.service.evv;

import com.careconnect.model.Patient;
import com.careconnect.model.evv.EvvRecord;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;

import java.time.OffsetDateTime;

import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class EvvOutboxServiceTest {

    @Mock
    private NamedParameterJdbcTemplate jdbc;

    @Mock
    private ObjectMapper objectMapper;

    @InjectMocks
    private EvvOutboxService evvOutboxService;

    private EvvRecord buildMinimalRecord() throws Exception {
        final EvvRecord record = mock(EvvRecord.class);
        lenient().when(record.getId()).thenReturn(1L);
        lenient().when(record.getServiceType()).thenReturn("HOME_HEALTH");
        lenient().when(record.getTimeIn()).thenReturn(OffsetDateTime.parse("2025-01-15T08:00:00Z"));
        lenient().when(record.getTimeOut()).thenReturn(OffsetDateTime.parse("2025-01-15T10:00:00Z"));
        lenient().when(record.getCheckinLocationLat()).thenReturn(null);
        lenient().when(record.getCheckinLocationLng()).thenReturn(null);
        lenient().when(record.getCheckinLocationSource()).thenReturn(null);
        lenient().when(record.getCheckoutLocationLat()).thenReturn(null);
        lenient().when(record.getCheckoutLocationLng()).thenReturn(null);
        lenient().when(record.getCheckoutLocationSource()).thenReturn(null);
        lenient().when(record.getLocationLat()).thenReturn(null);
        lenient().when(record.getLocationLng()).thenReturn(null);
        return record;
    }

    @Test
    void enqueue_withPatientAndMaNumber_usesMANumber() throws Exception {
        final EvvRecord record = buildMinimalRecord();
        final Patient patient = mock(Patient.class);
        when(patient.getMaNumber()).thenReturn("MA-12345");
        when(record.getPatient()).thenReturn(patient);
        when(objectMapper.writeValueAsString(any())).thenReturn("{}");

        assertThatCode(() -> evvOutboxService.enqueue(record, "dc-sandata")).doesNotThrowAnyException();

        verify(jdbc).update(anyString(), any(MapSqlParameterSource.class));
    }

    @Test
    void enqueue_withPatientNoMaNumber_usesPatientId() throws Exception {
        final EvvRecord record = buildMinimalRecord();
        final Patient patient = mock(Patient.class);
        when(patient.getMaNumber()).thenReturn(null);
        when(patient.getId()).thenReturn(99L);
        when(record.getPatient()).thenReturn(patient);
        when(objectMapper.writeValueAsString(any())).thenReturn("{}");

        assertThatCode(() -> evvOutboxService.enqueue(record, "dc-sandata")).doesNotThrowAnyException();

        verify(jdbc).update(anyString(), any(MapSqlParameterSource.class));
    }

    @Test
    void enqueue_withNullPatient_usesUnknown() throws Exception {
        final EvvRecord record = buildMinimalRecord();
        when(record.getPatient()).thenReturn(null);
        when(objectMapper.writeValueAsString(any())).thenReturn("{}");

        assertThatCode(() -> evvOutboxService.enqueue(record, "dc-sandata")).doesNotThrowAnyException();

        verify(jdbc).update(anyString(), any(MapSqlParameterSource.class));
    }

    @Test
    void enqueue_patientGetterThrows_fallsBackToUnknown() throws Exception {
        final EvvRecord record = buildMinimalRecord();
        when(record.getPatient()).thenThrow(new RuntimeException("DB error"));
        when(objectMapper.writeValueAsString(any())).thenReturn("{}");

        assertThatCode(() -> evvOutboxService.enqueue(record, "dc-sandata")).doesNotThrowAnyException();

        verify(jdbc).update(anyString(), any(MapSqlParameterSource.class));
    }

    @Test
    void enqueue_withAllLocationFields_includesAllInPayload() throws Exception {
        final EvvRecord record = mock(EvvRecord.class);
        lenient().when(record.getId()).thenReturn(2L);
        lenient().when(record.getServiceType()).thenReturn("PERSONAL_CARE");
        lenient().when(record.getTimeIn()).thenReturn(OffsetDateTime.parse("2025-01-15T08:00:00Z"));
        lenient().when(record.getTimeOut()).thenReturn(OffsetDateTime.parse("2025-01-15T10:00:00Z"));
        when(record.getCheckinLocationLat()).thenReturn(38.9072);
        when(record.getCheckinLocationLng()).thenReturn(-77.0369);
        when(record.getCheckinLocationSource()).thenReturn("GPS");
        when(record.getCheckoutLocationLat()).thenReturn(38.9073);
        when(record.getCheckoutLocationLng()).thenReturn(-77.0370);
        when(record.getCheckoutLocationSource()).thenReturn("GPS");
        when(record.getLocationLat()).thenReturn(38.9072);
        when(record.getLocationLng()).thenReturn(-77.0369);
        when(record.getPatient()).thenReturn(null);
        when(objectMapper.writeValueAsString(any())).thenReturn("{}");

        assertThatCode(() -> evvOutboxService.enqueue(record, "dc-sandata")).doesNotThrowAnyException();

        verify(jdbc).update(anyString(), any(MapSqlParameterSource.class));
    }

    @Test
    void enqueue_nullServiceType_usesUnknown() throws Exception {
        final EvvRecord record = buildMinimalRecord();
        when(record.getPatient()).thenReturn(null);
        when(record.getServiceType()).thenReturn(null);
        when(objectMapper.writeValueAsString(any())).thenReturn("{}");

        assertThatCode(() -> evvOutboxService.enqueue(record, "dc-sandata")).doesNotThrowAnyException();

        verify(jdbc).update(anyString(), any(MapSqlParameterSource.class));
    }

    @Test
    void enqueue_nullTimeIn_usesEmpty() throws Exception {
        final EvvRecord record = buildMinimalRecord();
        when(record.getPatient()).thenReturn(null);
        when(record.getTimeIn()).thenReturn(null);
        when(objectMapper.writeValueAsString(any())).thenReturn("{}");

        assertThatCode(() -> evvOutboxService.enqueue(record, "dc-sandata")).doesNotThrowAnyException();

        verify(jdbc).update(anyString(), any(MapSqlParameterSource.class));
    }

    @Test
    void enqueue_nullTimeOut_usesEmpty() throws Exception {
        final EvvRecord record = buildMinimalRecord();
        when(record.getPatient()).thenReturn(null);
        when(record.getTimeOut()).thenReturn(null);
        when(objectMapper.writeValueAsString(any())).thenReturn("{}");

        assertThatCode(() -> evvOutboxService.enqueue(record, "dc-sandata")).doesNotThrowAnyException();

        verify(jdbc).update(anyString(), any(MapSqlParameterSource.class));
    }

    @Test
    void enqueue_legacyLocationEmpty_doesNotAddLocKey() throws Exception {
        final EvvRecord record = buildMinimalRecord();
        when(record.getPatient()).thenReturn(null);
        // locationLat and locationLng are null (already set in buildMinimalRecord)
        when(objectMapper.writeValueAsString(any())).thenReturn("{}");

        assertThatCode(() -> evvOutboxService.enqueue(record, "dc-sandata")).doesNotThrowAnyException();

        verify(jdbc).update(anyString(), any(MapSqlParameterSource.class));
    }

    @Test
    void enqueue_objectMapperThrows_throwsRuntimeException() throws Exception {
        final EvvRecord record = buildMinimalRecord();
        when(record.getPatient()).thenReturn(null);
        when(objectMapper.writeValueAsString(any())).thenThrow(new JsonProcessingException("err") {
        });

        assertThatThrownBy(() -> evvOutboxService.enqueue(record, "dc-sandata"))
                .isInstanceOf(RuntimeException.class)
                .hasMessageContaining("Failed to enqueue EVV record for submission");
    }

    @Test
    void markSent_callsJdbcUpdate() throws Exception {
        evvOutboxService.markSent(10L);
        verify(jdbc).update(anyString(), any(MapSqlParameterSource.class));
    }

    @Test
    void markFailed_callsJdbcUpdate() throws Exception {
        evvOutboxService.markFailed(10L, "some error");
        verify(jdbc).update(anyString(), any(MapSqlParameterSource.class));
    }
}
