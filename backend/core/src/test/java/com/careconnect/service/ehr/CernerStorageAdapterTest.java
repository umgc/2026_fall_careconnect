package com.careconnect.service.ehr;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

import com.careconnect.model.Patient;
import com.careconnect.model.ehr.*;
import com.careconnect.repository.ehr.*;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import java.net.URI;
import java.time.*;
import java.util.*;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

class CernerStorageAdapterTest {
    private final ObjectMapper json = new ObjectMapper();
    private final EhrSourceRepository sources = mock(EhrSourceRepository.class);
    private final EhrPatientCrosswalkRepository links = mock(EhrPatientCrosswalkRepository.class);
    private final EhrRawPayloadRepository payloads = mock(EhrRawPayloadRepository.class);
    private final EhrAppointmentRecordRepository appointments = mock(EhrAppointmentRecordRepository.class);
    private final Map<String, EhrAppointmentRecord> rows = new HashMap<>();
    private final Map<String, EhrRawPayload> rawRows = new HashMap<>();
    private final Patient patient = Patient.builder().id(17L).firstName("Local")
            .lastName("Example").dob("1985-03-02").build();
    private final EhrSource source = EhrSource.builder().id(1L).code("CERNER_A").build();
    private final EhrSource other = EhrSource.builder().id(2L).code("CERNER_B").build();
    private CernerStorageAdapter adapter;

    @BeforeEach void setup() {
        for (EhrSource item : List.of(source, other)) {
            when(sources.findByCode(item.getCode())).thenReturn(Optional.of(item));
            when(links.findByPatientIdAndSourceId(17L, item.getId())).thenReturn(Optional.of(
                    EhrPatientCrosswalk.builder().patient(patient).source(item)
                            .externalPatientId("synthetic-p1").build()));
        }
        when(appointments.findByPatientIdAndSourceIdAndExternalAppointmentId(anyLong(), anyLong(), anyString()))
                .thenAnswer(i -> Optional.ofNullable(rows.get(i.getArgument(1) + ":" + i.getArgument(2))));
        when(appointments.save(any())).thenAnswer(i -> {
            EhrAppointmentRecord row = i.getArgument(0);
            if (row.getId() == null) { row.setId((long) rows.size() + 1); }
            rows.put(row.getSource().getId() + ":" + row.getExternalAppointmentId(), row);
            return row;
        });
        when(payloads.findByPatientIdAndSourceIdAndResourceTypeAndExternalResourceId(
                anyLong(), anyLong(), anyString(), anyString()))
                .thenAnswer(i -> Optional.ofNullable(rawRows.get(i.getArgument(1) + ":" + i.getArgument(3))));
        when(payloads.save(any())).thenAnswer(i -> {
            EhrRawPayload row = i.getArgument(0);
            if (row.getId() == null) { row.setId((long) rawRows.size() + 1); }
            rawRows.put(row.getSource().getId() + ":" + row.getExternalResourceId(), row);
            return row;
        });
        adapter = new CernerStorageAdapter(sources, links, payloads, appointments, json,
                Clock.fixed(Instant.parse("2026-09-24T16:00:00Z"), ZoneOffset.UTC),
                Map.of("CERNER_A", URI.create("https://a.example.invalid/r4/"),
                       "CERNER_B", URI.create("https://b.example.invalid/r4/")));
    }

    private ObjectNode fixture(String file) throws Exception {
        try (var input = getClass().getResourceAsStream("/cerner-compatibility/" + file)) {
            return (ObjectNode) json.readTree(Objects.requireNonNull(input));
        }
    }

    @Test void wrongPatientIsRejectedBeforeAnyStorage() throws Exception {
        ObjectNode data = fixture("appointment.json");
        ((ObjectNode) data.path("participant").get(0).get("actor"))
                .put("reference", "Patient/synthetic-wrong");
        assertThrows(IllegalArgumentException.class, () -> adapter.importAppointment(patient, "CERNER_A", data));
        verifyNoInteractions(payloads, appointments);
    }

    @Test void absoluteReferenceFromAnotherTenantIsRejected() throws Exception {
        ObjectNode data = fixture("appointment.json");
        ((ObjectNode) data.path("participant").get(0).get("actor"))
                .put("reference", "https://b.example.invalid/r4/Patient/synthetic-p1");
        assertThrows(IllegalArgumentException.class, () -> adapter.importAppointment(patient, "CERNER_A", data));
        verifyNoInteractions(payloads, appointments);
    }

    @Test void laterWrongPatientCannotHideBehindFirstMatch() throws Exception {
        ObjectNode data = fixture("appointment.json");
        ((com.fasterxml.jackson.databind.node.ArrayNode) data.get("participant"))
                .addObject().putObject("actor").put("reference", "Patient/wrong");
        assertThrows(IllegalArgumentException.class, () -> adapter.importAppointment(patient, "CERNER_A", data));
        verifyNoInteractions(payloads, appointments);
    }

    @Test void utcInstantAndOriginalOffsetBothSurvive() throws Exception {
        ObjectNode data = fixture("appointment.json");
        EhrAppointmentRecord row = adapter.importAppointment(patient, "CERNER_A", data);
        assertEquals(LocalDateTime.parse("2026-11-01T05:30:00"), row.getStartTime());
        assertEquals(LocalDateTime.parse("2026-11-01T06:30:00"), row.getEndTime());
        assertEquals(LocalDateTime.parse("2026-09-20T14:00:00"), row.getSourceCreatedAt());
        assertEquals(LocalDateTime.parse("2026-09-23T23:00:00"), row.getSourceUpdatedAt());
        assertEquals("2026-11-01T01:30:00-04:00", row.getRawPayload().getPayload().get("start"));
        assertEquals(json.convertValue(data, Map.class), row.getRawPayload().getPayload());
        assertEquals(LocalDateTime.parse("2026-09-24T16:00:00"), row.getRawPayload().getFetchedAt());
    }

    @Test void positiveOffsetCrossesUtcDateBoundary() throws Exception {
        ObjectNode data = fixture("appointment.json");
        data.put("start", "2026-09-25T00:15:00+05:30");
        data.put("end", "2026-09-25T00:45:00+05:30");
        assertEquals(LocalDateTime.parse("2026-09-24T18:45:00"),
                adapter.importAppointment(patient, "CERNER_A", data).getStartTime());
    }

    @Test void importingSameAppointmentTwiceKeepsOneRowAndOneRawPayload() throws Exception {
        ObjectNode data = fixture("appointment.json");
        Long first = adapter.importAppointment(patient, "CERNER_A", data).getId();
        data.put("status", "fulfilled");
        assertEquals(first, adapter.importAppointment(patient, "CERNER_A", data).getId());
        assertEquals(1, rows.size());
        assertEquals(1, rawRows.size());
        assertEquals("fulfilled", rows.values().iterator().next().getStatus());
    }

    @Test void sameExternalIdAtSeparateSourcesStaysSeparate() throws Exception {
        ObjectNode data = fixture("appointment.json");
        Long first = adapter.importAppointment(patient, "CERNER_A", data).getId();
        Long second = adapter.importAppointment(patient, "CERNER_B", data).getId();
        assertNotEquals(first, second);
        assertEquals(2, rows.size());
        assertEquals(2, rawRows.size());
    }

    @Test void missingLinkBlocksAllStorage() throws Exception {
        when(links.findByPatientIdAndSourceId(17L, 1L)).thenReturn(Optional.empty());
        ObjectNode data = fixture("appointment.json");
        assertThrows(IllegalArgumentException.class, () -> adapter.importAppointment(patient, "CERNER_A", data));
        verifyNoInteractions(payloads, appointments);
    }

    @Test void disabledSourceBlocksAllStorage() throws Exception {
        source.setActive(false);
        ObjectNode data = fixture("appointment.json");
        assertThrows(IllegalArgumentException.class, () -> adapter.importAppointment(patient, "CERNER_A", data));
        verifyNoInteractions(payloads, appointments);
    }

    @Test void missingRequiredTimeBlocksAllStorage() throws Exception {
        ObjectNode data = fixture("appointment.json");
        data.remove("start");
        assertThrows(IllegalArgumentException.class, () -> adapter.importAppointment(patient, "CERNER_A", data));
        verifyNoInteractions(payloads, appointments);
    }

    @Test void malformedCreatedTimeFailsBeforeRawWrite() throws Exception {
        ObjectNode data = fixture("appointment.json");
        data.put("created", "bad");
        assertThrows(IllegalArgumentException.class, () -> adapter.importAppointment(patient, "CERNER_A", data));
        verifyNoInteractions(payloads, appointments);
    }

    @Test void partialBirthDateAndConflictsRemainForReview() throws Exception {
        ObjectNode data = fixture("patient-partial.json");
        var review = adapter.reviewPatient(patient, "CERNER_A", data);
        assertEquals("MONTH", review.fields().path("birthDatePrecision").asText());
        assertEquals("1985-03", review.fields().path("source").path("birthDate").asText());
        assertEquals(2, review.conflicts().size());
        assertTrue(review.conflicts().stream().allMatch(c -> c.getStatus() == EhrConflictStatus.PENDING
                && c.getResolvedAt() == null && c.getResolvedBy() == null));
        assertEquals("Local", patient.getFirstName());
        assertEquals("1985-03-02", patient.getDob());
        assertEquals("opaque-v7", review.fields().path("sourceVersion").asText());
        assertFalse(review.toString().contains("1985"));
        verifyNoInteractions(payloads, appointments);
    }

    @Test void absentDemographicsDoNotClearCanonicalValues() throws Exception {
        ObjectNode data = json.createObjectNode().put("resourceType", "Patient").put("id", "synthetic-p1");
        var review = adapter.reviewPatient(patient, "CERNER_A", data);
        assertTrue(review.conflicts().isEmpty());
        assertFalse(review.fields().path("source").has("birthDate"));
        assertEquals("Local", patient.getFirstName());
        assertEquals("1985-03-02", patient.getDob());
    }

    @Test void explicitNullRemainsDistinctFromAbsent() throws Exception {
        ObjectNode data = fixture("patient-partial.json");
        data.putNull("birthDate");
        var review = adapter.reviewPatient(patient, "CERNER_A", data);
        assertTrue(review.fields().path("source").has("birthDate"));
        assertTrue(review.fields().path("source").get("birthDate").isNull());
        assertEquals("1985-03-02", patient.getDob());
    }

    @Test void staleVersionCannotReplaceNewerData() throws Exception {
        ObjectNode data = fixture("appointment.json");
        adapter.importAppointment(patient, "CERNER_A", data);
        clearInvocations(payloads, appointments);
        ((ObjectNode) data.get("meta")).put("lastUpdated", "2026-09-22T00:00:00Z");
        assertThrows(IllegalArgumentException.class, () -> adapter.importAppointment(patient, "CERNER_A", data));
        verify(payloads, never()).save(any());
        verify(appointments, never()).save(any());
    }

    @Test void currentSourceVersionIsRetainedWithoutInventingHistory() throws Exception {
        ObjectNode data = fixture("appointment.json");
        adapter.importAppointment(patient, "CERNER_A", data);
        ((ObjectNode) data.get("meta")).put("versionId", "opaque-v8").put("lastUpdated", "2026-09-24T00:00:00Z");
        var row = adapter.importAppointment(patient, "CERNER_A", data);
        assertEquals("opaque-v8", ((Map<?, ?>) row.getRawPayload().getPayload().get("meta")).get("versionId"));
        assertEquals(1, rawRows.size());
    }

    @Test void sharedMapperAloneExhibitsOffsetLoss() throws Exception {
        var row = EhrAppointmentMapper.map(fixture("appointment.json"), patient, source, null);
        assertEquals(LocalDateTime.parse("2026-11-01T01:30:00"), row.getStartTime());
        assertEquals(row.getStartTime(), row.getEndTime());
    }

    @Test void sharedMapperAloneAcceptsWrongPatient() throws Exception {
        ObjectNode data = fixture("appointment.json");
        ((ObjectNode) data.path("participant").get(0).get("actor")).put("reference", "Patient/wrong");
        assertEquals(patient, EhrAppointmentMapper.map(data, patient, source, null).getPatient());
    }

    @Test void fullPatientSourceIsRetainedAsDefensiveCopy() throws Exception {
        ObjectNode data = fixture("patient-partial.json");
        data.putObject("text").put("status", "generated").put("div", "Synthetic narrative");
        var review = adapter.reviewPatient(patient, "CERNER_A", data);
        data.remove("text");
        assertEquals("Synthetic narrative", review.rawResource().path("text").path("div").asText());
        ((ObjectNode) review.rawResource()).remove("birthDate");
        assertEquals("1985-03", review.rawResource().path("birthDate").asText());
    }

    @Test void yearOnlyBirthDateIsNotExpandedToFullDate() throws Exception {
        ObjectNode data = fixture("patient-partial.json");
        data.put("birthDate", "1985");
        var review = adapter.reviewPatient(patient, "CERNER_A", data);
        assertEquals("YEAR", review.fields().path("birthDatePrecision").asText());
        assertEquals("1985", review.rawResource().path("birthDate").asText());
        assertEquals("1985-03-02", patient.getDob());
    }

    @Test void timezoneFreeStartIsRejected() throws Exception {
        ObjectNode data = fixture("appointment.json");
        data.put("start", "2026-11-01T01:30:00");
        assertThrows(IllegalArgumentException.class, () -> adapter.importAppointment(patient, "CERNER_A", data));
        verifyNoInteractions(payloads, appointments);
    }

    @Test void proposedAppointmentCanHaveNoTimes() throws Exception {
        ObjectNode data = fixture("appointment.json");
        data.put("status", "proposed");
        data.remove(List.of("start", "end"));
        var row = adapter.importAppointment(patient, "CERNER_A", data);
        assertNull(row.getStartTime());
        assertNull(row.getEndTime());
    }
}
