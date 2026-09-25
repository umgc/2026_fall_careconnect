package com.careconnect.service.ehr;

import com.careconnect.model.Patient;
import com.careconnect.model.ehr.*;
import com.careconnect.repository.ehr.*;
import com.careconnect.service.cerner.CernerResourceMapper;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import java.net.URI;
import java.nio.charset.StandardCharsets;
import java.time.*;
import java.util.*;
import org.springframework.transaction.annotation.Transactional;

/** Isolated prototype. No component registration, HTTP, account linking, or patient writes. */
public class CernerStorageAdapter {
    private final EhrSourceRepository sources;
    private final EhrPatientCrosswalkRepository links;
    private final EhrRawPayloadRepository payloads;
    private final EhrAppointmentRecordRepository appointments;
    private final ObjectMapper json;
    private final Clock clock;
    private final CernerResourceMapper mapper;
    private final Map<String, URI> trustedBases;

    /** Source code to tenant base must come from trusted server configuration. */
    public CernerStorageAdapter(EhrSourceRepository sources,
            EhrPatientCrosswalkRepository links, EhrRawPayloadRepository payloads,
            EhrAppointmentRecordRepository appointments, ObjectMapper json, Clock clock,
            Map<String, URI> trustedBases) {
        this.sources = sources;
        this.links = links;
        this.payloads = payloads;
        this.appointments = appointments;
        this.json = json;
        this.clock = clock;
        this.mapper = new CernerResourceMapper(clock);
        this.trustedBases = Map.copyOf(trustedBases);
    }

    /** Caller must authorize this local patient. Transaction proxy needed before production use. */
    @Transactional
    public EhrAppointmentRecord importAppointment(Patient patient, String sourceCode, JsonNode input) {
        EhrSource source = source(sourceCode);
        CernerResourceMapper.PatientLink link = link(patient, source);
        // Snapshot and validate BEFORE either raw or canonical storage can be touched.
        ObjectNode projection = mapper.appointment(input, link).fields();
        JsonNode resource = input.deepCopy();
        ObjectNode normalized = (ObjectNode) resource.deepCopy();
        utcField(normalized, "start");
        utcField(normalized, "end");
        utcField(normalized, "created");
        if (normalized.hasNonNull("meta")) {
            utcField((ObjectNode) normalized.get("meta"), "lastUpdated");
        }
        EhrAppointmentRecord mapped = EhrAppointmentMapper.map(normalized, patient, source, null);
        for (String value : Arrays.asList(mapped.getProviderName(), mapped.getLocation(),
                mapped.getServiceType(), mapped.getReason())) {
            if (value != null && value.length() > 255) {
                throw invalid("appointment.textLength");
            }
        }
        String externalId = projection.path("externalId").asText();
        Optional<EhrAppointmentRecord> existing = appointments
                .findByPatientIdAndSourceIdAndExternalAppointmentId(
                        patient.getId(), source.getId(), externalId);
        // Do not let stale or unversioned data silently replace a timestamped record.
        existing.ifPresent(row -> {
            LocalDateTime previous = row.getSourceUpdatedAt();
            LocalDateTime incoming = mapped.getSourceUpdatedAt();
            if (previous != null && (incoming == null || incoming.isBefore(previous))) {
                throw invalid("appointment.staleOrUnknownVersion");
            }
            mapped.setId(row.getId());
        });
        EhrRawPayload raw = payloads
                .findByPatientIdAndSourceIdAndResourceTypeAndExternalResourceId(
                        patient.getId(), source.getId(), "Appointment", externalId)
                .orElseGet(EhrRawPayload::new);
        raw.setPatient(patient);
        raw.setSource(source);
        raw.setResourceType("Appointment");
        raw.setExternalResourceId(externalId);
        // Keep original date offsets and meta.versionId; never store the normalized clone.
        raw.setPayload(json.convertValue(resource, new TypeReference<Map<String, Object>>() { }));
        raw.setPayloadSizeBytes(resource.toString().getBytes(StandardCharsets.UTF_8).length);
        raw.setFetchedAt(LocalDateTime.ofInstant(clock.instant(), ZoneOffset.UTC));
        mapped.setRawPayload(payloads.save(raw));
        return appointments.save(mapped);
    }

    /** Pure demographic review: holds the projection and pending conflicts in memory only. */
    public PatientReview reviewPatient(Patient patient, String sourceCode, JsonNode resource) {
        EhrSource source = source(sourceCode);
        ObjectNode fields = mapper.patient(resource, link(patient, source)).fields();
        List<EhrIdentityConflict> conflicts = new ArrayList<>();
        compare(conflicts, patient, source, "first_name", patient.getFirstName(),
                fields.path("display").path("firstName"));
        compare(conflicts, patient, source, "last_name", patient.getLastName(),
                fields.path("display").path("lastName"));
        compare(conflicts, patient, source, "date_of_birth", patient.getDob(),
                fields.path("source").path("birthDate"));
        // Contacts/addresses stay as full arrays until a shared selection policy is agreed.
        return new PatientReview(fields, resource, conflicts);
    }

    public static final class PatientReview {
        private final ObjectNode fields;
        private final JsonNode rawResource;
        private final List<EhrIdentityConflict> conflicts;
        private PatientReview(ObjectNode fields, JsonNode rawResource, List<EhrIdentityConflict> conflicts) {
            this.fields = fields.deepCopy();
            this.rawResource = rawResource.deepCopy();
            this.conflicts = List.copyOf(conflicts);
        }
        public ObjectNode fields() { return fields.deepCopy(); }
        public JsonNode rawResource() { return rawResource.deepCopy(); }
        public List<EhrIdentityConflict> conflicts() { return conflicts; }
        @Override public String toString() { return "CernerPatientReview[redacted]"; }
    }

    private void compare(List<EhrIdentityConflict> result, Patient patient, EhrSource source,
            String field, String current, JsonNode incoming) {
        if (!incoming.isTextual() || Objects.equals(current, incoming.textValue())) { return; }
        if (incoming.textValue().length() > 255 || current != null && current.length() > 255) {
            throw invalid("patient.textLength");
        }
        result.add(EhrIdentityConflict.builder().patient(patient).source(source)
                .fieldName(field).canonicalValue(current).incomingValue(incoming.textValue())
                .status(EhrConflictStatus.PENDING)
                .detectedAt(LocalDateTime.ofInstant(clock.instant(), ZoneOffset.UTC)).build());
    }

    private EhrSource source(String code) {
        if (!trustedBases.containsKey(code)) { throw invalid("source.configuration"); }
        EhrSource source = sources.findByCode(code).orElseThrow(() -> invalid("source.missing"));
        if (!source.isActive() || !"R4".equals(source.getFhirVersion())) {
            throw invalid("source.disabledOrUnsupported");
        }
        return source;
    }

    private CernerResourceMapper.PatientLink link(Patient patient, EhrSource source) {
        if (patient == null || patient.getId() == null) { throw invalid("patient.id"); }
        EhrPatientCrosswalk crosswalk = links
                .findByPatientIdAndSourceId(patient.getId(), source.getId())
                .orElseThrow(() -> invalid("link.missing"));
        if (crosswalk.getPatient() == null || crosswalk.getSource() == null
                || !Objects.equals(patient.getId(), crosswalk.getPatient().getId())
                || !Objects.equals(source.getId(), crosswalk.getSource().getId())) {
            throw invalid("link.mismatch");
        }
        return new CernerResourceMapper.PatientLink(patient.getId(),
                trustedBases.get(source.getCode()), crosswalk.getExternalPatientId());
    }

    private static void utcField(ObjectNode node, String field) {
        if (!node.hasNonNull(field)) { return; }
        try {
            if (!node.get(field).isTextual()) { throw invalid(field); }
            node.put(field, OffsetDateTime.parse(node.get(field).textValue())
                    .withOffsetSameInstant(ZoneOffset.UTC).toString());
        } catch (DateTimeException error) {
            throw invalid(field);
        }
    }

    private static IllegalArgumentException invalid(String field) {
        return new IllegalArgumentException("Invalid Cerner field: " + field);
    }
}
