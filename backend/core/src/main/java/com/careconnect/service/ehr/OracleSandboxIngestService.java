package com.careconnect.service.ehr;

import com.careconnect.config.OracleProperties;
import com.careconnect.model.Patient;
import com.careconnect.model.ehr.EhrRawPayload;
import com.careconnect.model.ehr.EhrSource;
import com.careconnect.model.ehr.MedicareProperties;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.ehr.EhrRawPayloadRepository;
import com.careconnect.repository.ehr.EhrResourceRepository;
import com.careconnect.repository.ehr.EhrSourceRepository;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Standalone, no-merge ingest for Oracle Health (Cerner) and Medicare (WBS 5.2.86, "Option B").
 *
 * <p>Writes verbatim FHIR into {@code ehr_raw_payload} under the source's catalog code, then hands
 * off to {@link EhrMirrorProjector} to produce the {@code ehr_resource} mirror rows that make the
 * records show up in the Unified Health {@code ?source=ALL} union. It does NOT touch Team C's Cerner
 * code and needs no vendor credentials:
 * <ul>
 *   <li><b>Oracle Health</b> — pulled live from the <b>open</b> Cerner FHIR R4 sandbox
 *       ({@code fhir-open.cerner.com}, no auth). If the network is unavailable the ingest falls back
 *       to a small synthetic set so the pipeline still demonstrates end-to-end.</li>
 *   <li><b>Medicare</b> — CMS BlueButton has no open (no-auth) sandbox, so a small synthetic,
 *       clearly-labelled claim/clinical set is generated locally. The production Medicare connector
 *       ({@code MedicareRecordCache}) already writes real raw payloads once credentialed; this
 *       projector/ingest is the mirror half it is missing (the 5.2.85 gap).</li>
 * </ul>
 * Gated on {@code careconnect.oracle.enabled} (dev only).
 */
@Slf4j
@Service
@ConditionalOnProperty(name = "careconnect.oracle.enabled", havingValue = "true")
public class OracleSandboxIngestService {

    /** Resource types pulled from the open Oracle/Cerner sandbox (patient-search supported). */
    private static final List<String> ORACLE_TYPES = List.of(
            "Condition", "Observation", "AllergyIntolerance", "Immunization", "MedicationRequest");

    private final OracleProperties oracle;
    private final EhrSourceRepository sourceRepo;
    private final EhrRawPayloadRepository rawPayloadRepo;
    private final EhrResourceRepository resourceRepo;
    private final PatientRepository patientRepository;
    private final EhrMirrorProjector projector;
    private final ObjectMapper objectMapper;
    /** Self-proxy so {@link #persistAndMirror} runs through Spring's transactional advice. */
    private final ObjectProvider<OracleSandboxIngestService> selfProvider;
    private final HttpClient http;

    @Autowired
    public OracleSandboxIngestService(final OracleProperties oracle,
                                      final EhrSourceRepository sourceRepo,
                                      final EhrRawPayloadRepository rawPayloadRepo,
                                      final EhrResourceRepository resourceRepo,
                                      final PatientRepository patientRepository,
                                      final EhrMirrorProjector projector,
                                      final ObjectMapper objectMapper,
                                      final ObjectProvider<OracleSandboxIngestService> selfProvider) {
        this(oracle, sourceRepo, rawPayloadRepo, resourceRepo, patientRepository, projector, objectMapper,
                selfProvider, HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(8)).build());
    }

    /** Package-private seam: lets tests supply a stub {@link HttpClient} for the open-sandbox fetch. */
    OracleSandboxIngestService(final OracleProperties oracle,
                               final EhrSourceRepository sourceRepo,
                               final EhrRawPayloadRepository rawPayloadRepo,
                               final EhrResourceRepository resourceRepo,
                               final PatientRepository patientRepository,
                               final EhrMirrorProjector projector,
                               final ObjectMapper objectMapper,
                               final ObjectProvider<OracleSandboxIngestService> selfProvider,
                               final HttpClient http) {
        this.oracle = oracle;
        this.sourceRepo = sourceRepo;
        this.rawPayloadRepo = rawPayloadRepo;
        this.resourceRepo = resourceRepo;
        this.patientRepository = patientRepository;
        this.projector = projector;
        this.objectMapper = objectMapper;
        this.selfProvider = selfProvider;
        this.http = http;
    }

    /**
     * Ingest BOTH Oracle Health and Medicare for one user, then mirror them.
     *
     * @return a per-source summary of raw payloads stored and mirror rows produced
     */
    public Map<String, Object> ingestAll(final Long userId) {
        final Patient patient = patientRepository.findByUserId(userId).orElseThrow(
                () -> new IllegalStateException("No patient record for user " + userId));
        final Long patientId = patient.getId();

        // Fetch OUTSIDE any transaction (the Oracle pull is slow/remote). The DB mutations then run
        // in persistAndMirror via the self-proxy so they get a real transaction (derived deletes need one).
        final List<JsonNode> oracle = oracleResources();
        final List<JsonNode> medicare = medicareResources();

        final Map<String, Object> summary = new LinkedHashMap<>();
        summary.put(OracleProperties.SOURCE_ORACLE, selfProvider.getObject()
                .persistAndMirror(userId, patientId, OracleProperties.SOURCE_ORACLE, oracle));
        summary.put(MedicareProperties.SOURCE_MEDICARE, selfProvider.getObject()
                .persistAndMirror(userId, patientId, MedicareProperties.SOURCE_MEDICARE, medicare));
        return summary;
    }

    /**
     * Clear this source's prior rows, store the fetched resources as raw payloads, and mirror them —
     * all in one transaction. Public + {@code @Transactional} and invoked via the self-proxy so the
     * derived deletes and the projector run with an active transaction.
     */
    @Transactional
    public Map<String, Object> persistAndMirror(final Long userId, final Long patientId,
                                                final String sourceCode, final List<JsonNode> resources) {
        final Map<String, Object> result = new LinkedHashMap<>();
        final Long sourceId = sourceRepo.findByCode(sourceCode).map(EhrSource::getId).orElse(null);
        if (sourceId == null) {
            result.put("error", "source " + sourceCode + " not seeded in ehr_source catalog");
            return result;
        }
        // Idempotent re-ingest: drop this source's prior raw payloads + mirror rows first.
        rawPayloadRepo.deleteByPatientIdAndSourceId(patientId, sourceId);
        resourceRepo.deleteByUserIdAndSource(userId, sourceCode);

        int stored = 0;
        for (final JsonNode resource : resources) {
            final String type = resource.hasNonNull("resourceType") ? resource.get("resourceType").asText() : null;
            final String fhirId = resource.hasNonNull("id") ? resource.get("id").asText() : null;
            if (type == null || fhirId == null) {
                continue;
            }
            try {
                rawPayloadRepo.save(EhrRawPayload.builder()
                        .patientId(patientId)
                        .sourceId(sourceId)
                        .resourceType(type)
                        .externalResourceId(fhirId)
                        .payload(objectMapper.writeValueAsString(resource))
                        .retrievedAt(OffsetDateTime.now())
                        .build());
                stored++;
            } catch (final Exception ex) {
                log.warn("Oracle ingest could not store a {} payload: {}", type, ex.getClass().getSimpleName());
            }
        }
        final int mirrored = projector.projectForSource(userId, patientId, sourceCode);
        result.put("rawPayloadsStored", stored);
        result.put("mirrorRows", mirrored);
        return result;
    }

    // --- Oracle Health: live open sandbox, synthetic fallback ---

    private List<JsonNode> oracleResources() {
        final List<JsonNode> live = new ArrayList<>();
        for (final String type : ORACLE_TYPES) {
            live.addAll(fetchOpenSandbox(type));
        }
        if (!live.isEmpty()) {
            log.info("Oracle ingest: pulled {} resource(s) from open sandbox {}", live.size(), oracle.tenantBaseUrl());
            return live;
        }
        log.warn("Oracle ingest: open sandbox returned nothing (offline?), using synthetic fallback set");
        return syntheticOracle();
    }

    /** GET {tenantBase}/{type}?patient={id} from the open (no-auth) sandbox; empty list on any failure. */
    private List<JsonNode> fetchOpenSandbox(final String resourceType) {
        final List<JsonNode> out = new ArrayList<>();
        try {
            final URI uri = URI.create(oracle.tenantBaseUrl() + "/" + resourceType
                    + "?patient=" + oracle.getSandboxPatientId() + "&_count=15");
            final HttpRequest req = HttpRequest.newBuilder(uri)
                    .header("Accept", "application/fhir+json")
                    .timeout(Duration.ofSeconds(10))
                    .GET().build();
            final HttpResponse<String> resp = http.send(req, HttpResponse.BodyHandlers.ofString());
            if (resp.statusCode() / 100 != 2) {
                log.info("Oracle open-sandbox {} returned HTTP {}", resourceType, resp.statusCode());
                return out;
            }
            final JsonNode bundle = objectMapper.readTree(resp.body());
            final JsonNode entries = bundle.get("entry");
            if (entries != null && entries.isArray()) {
                for (final JsonNode entry : entries) {
                    final JsonNode resource = entry.get("resource");
                    if (resource != null && resource.hasNonNull("resourceType")
                            && resourceType.equals(resource.get("resourceType").asText())
                            && resource.hasNonNull("id")) {
                        out.add(resource);
                    }
                }
            }
        } catch (final Exception ex) {
            log.info("Oracle open-sandbox fetch of {} failed: {}", resourceType, ex.getClass().getSimpleName());
        }
        return out;
    }

    private List<JsonNode> syntheticOracle() {
        final List<JsonNode> list = new ArrayList<>();
        list.add(condition("oracle-cond-1", "38341003", "Hypertension", "2025-03-11"));
        list.add(observation("oracle-obs-1", "Heart rate", "72", "/min", "2026-02-02T09:00:00Z"));
        list.add(observation("oracle-obs-2", "Body temperature", "37.0", "Cel", "2026-02-02T09:05:00Z"));
        list.add(allergy("oracle-alg-1", "Penicillin", "2024-08-20"));
        list.add(immunization("oracle-imm-1", "Influenza vaccine", "2025-10-15"));
        return list;
    }

    // --- Medicare: synthetic claim/clinical set (no open sandbox exists) ---

    private List<JsonNode> medicareResources() {
        final List<JsonNode> list = new ArrayList<>();
        list.add(coverage("mcr-cov-1", "Medicare Part B", "2015-06-01"));
        list.add(explanationOfBenefit("mcr-eob-1", "Office visit, established patient", "2026-01-18"));
        list.add(explanationOfBenefit("mcr-eob-2", "Comprehensive metabolic panel", "2026-01-18"));
        list.add(condition("mcr-cond-1", "44054006", "Type 2 diabetes mellitus", "2023-11-02"));
        return list;
    }

    // --- Minimal synthetic FHIR R4 builders (dev/demo data only) ---

    private ObjectNode base(final String type, final String id) {
        final ObjectNode n = objectMapper.createObjectNode();
        n.put("resourceType", type);
        n.put("id", id);
        return n;
    }

    private ObjectNode codeableText(final String text) {
        return objectMapper.createObjectNode().put("text", text);
    }

    private ObjectNode condition(final String id, final String code, final String display, final String onset) {
        final ObjectNode n = base("Condition", id);
        n.put("onsetDateTime", onset);
        final ObjectNode clinical = objectMapper.createObjectNode();
        final ArrayNode coding = clinical.putArray("coding");
        coding.add(objectMapper.createObjectNode().put("code", "active"));
        n.set("clinicalStatus", clinical);
        final ObjectNode codeNode = objectMapper.createObjectNode().put("text", display);
        final ArrayNode cc = codeNode.putArray("coding");
        cc.add(objectMapper.createObjectNode().put("system", "http://snomed.info/sct")
                .put("code", code).put("display", display));
        n.set("code", codeNode);
        return n;
    }

    private ObjectNode observation(final String id, final String label, final String value,
                                   final String unit, final String effective) {
        final ObjectNode n = base("Observation", id);
        n.put("status", "final");
        n.put("effectiveDateTime", effective);
        n.set("code", codeableText(label));
        final ObjectNode qty = objectMapper.createObjectNode();
        qty.put("value", value);
        qty.put("unit", unit);
        n.set("valueQuantity", qty);
        return n;
    }

    private ObjectNode allergy(final String id, final String substance, final String recorded) {
        final ObjectNode n = base("AllergyIntolerance", id);
        n.put("recordedDate", recorded);
        final ObjectNode clinical = objectMapper.createObjectNode();
        clinical.putArray("coding").add(objectMapper.createObjectNode().put("code", "active"));
        n.set("clinicalStatus", clinical);
        n.set("code", codeableText(substance));
        return n;
    }

    private ObjectNode immunization(final String id, final String vaccine, final String date) {
        final ObjectNode n = base("Immunization", id);
        n.put("status", "completed");
        n.put("occurrenceDateTime", date);
        n.put("date", date);
        n.set("vaccineCode", codeableText(vaccine));
        n.set("code", codeableText(vaccine));
        return n;
    }

    private ObjectNode coverage(final String id, final String plan, final String start) {
        final ObjectNode n = base("Coverage", id);
        n.put("status", "active");
        final ObjectNode period = objectMapper.createObjectNode();
        period.put("start", start);
        n.set("period", period);
        n.set("type", codeableText(plan));
        return n;
    }

    private ObjectNode explanationOfBenefit(final String id, final String service, final String created) {
        final ObjectNode n = base("ExplanationOfBenefit", id);
        n.put("status", "active");
        n.put("created", created);
        n.set("type", codeableText(service));
        return n;
    }
}
