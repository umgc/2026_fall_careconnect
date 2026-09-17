package com.careconnect.medicare;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.io.IOException;
import java.io.InputStream;
import java.util.ArrayList;
import java.util.List;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.core.io.ClassPathResource;
import org.springframework.stereotype.Component;

/**
 * Fixture-backed {@link MedicareSource}: no network, no OAuth, no CMS credentials.
 *
 * <p>Exists so the frontend can build against a real endpoint while the live client
 * (issue #132) is still in progress, and so a demo does not depend on CMS sandbox availability.
 * The fixtures are trimmed copies of Blue Button v2 {@code searchset} Bundles, so this reads
 * them the same way the live client will: walk {@code entry[].resource}, run the status gate,
 * return what survives.
 *
 * <p>The data is fabricated. Every response is labelled {@code synthetic} in
 * {@link MedicareEnvelope} for that reason.
 */
@Slf4j
@Component
@ConditionalOnProperty(
        name = "careconnect.medicare.mode",
        havingValue = MedicareProperties.MODE_MOCK,
        matchIfMissing = true)
public class MockMedicareSource implements MedicareSource {

    private static final String FIXTURE_BASE = "fixtures/medicare/";
    private static final String PATIENT_FIXTURE = FIXTURE_BASE + "patient-bundle.json";
    private static final String COVERAGE_FIXTURE = FIXTURE_BASE + "coverage-bundle.json";
    private static final String EOB_FIXTURE = FIXTURE_BASE + "eob-bundle.json";

    private final JsonNode patient;
    private final List<JsonNode> coverage;
    private final List<JsonNode> visits;

    /**
     * Fixtures are read once at startup rather than per request: they are immutable packaged
     * resources, and a missing or malformed one is a packaging fault that should surface as a
     * startup failure, not as an intermittent 500.
     */
    public MockMedicareSource(final ObjectMapper objectMapper, final MedicareStatusGate statusGate) {
        final List<JsonNode> patients = readAllowedResources(objectMapper, statusGate, PATIENT_FIXTURE);
        this.patient = patients.isEmpty() ? null : patients.get(0);
        this.coverage = readAllowedResources(objectMapper, statusGate, COVERAGE_FIXTURE);
        this.visits = readAllowedResources(objectMapper, statusGate, EOB_FIXTURE);

        log.info(
                "[medicare] Mock source ready: patient={}, coverage={}, visits={} (synthetic fixtures)",
                this.patient != null, this.coverage.size(), this.visits.size());
    }

    @Override
    public String sourceCode() {
        return MedicareProperties.SOURCE_MEDICARE;
    }

    @Override
    public JsonNode fetchPatient() {
        return patient;
    }

    @Override
    public List<JsonNode> fetchCoverage() {
        return coverage;
    }

    @Override
    public List<JsonNode> fetchVisits() {
        return visits;
    }

    /** Reads one Bundle fixture and returns the resources the status gate allows. */
    private static List<JsonNode> readAllowedResources(
            final ObjectMapper objectMapper, final MedicareStatusGate statusGate, final String path) {
        final JsonNode bundle = readFixture(objectMapper, path);
        final JsonNode entries = bundle.get("entry");
        if (entries == null || !entries.isArray()) {
            log.warn("[medicare] Fixture {} has no entry array; treating as empty", path);
            return List.of();
        }

        final List<JsonNode> allowed = new ArrayList<>(entries.size());
        int dropped = 0;
        for (final JsonNode entry : entries) {
            final JsonNode resource = entry.get("resource");
            if (statusGate.isAllowed(resource)) {
                allowed.add(resource);
            } else {
                dropped++;
            }
        }
        if (dropped > 0) {
            log.debug("[medicare] Status gate dropped {} resource(s) from {}", dropped, path);
        }
        return List.copyOf(allowed);
    }

    private static JsonNode readFixture(final ObjectMapper objectMapper, final String path) {
        try (InputStream in = new ClassPathResource(path).getInputStream()) {
            return objectMapper.readTree(in);
        } catch (final IOException e) {
            throw new IllegalStateException("Unable to read Medicare fixture: " + path, e);
        }
    }
}
