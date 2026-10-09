package com.careconnect.model.ehr;

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
 * Fixture-backed {@link MedicareSource} for {@code careconnect.medicare.mode=mock}: no network, no
 * OAuth, no CMS credentials and no Medicare link.
 *
 * <p>Exists so a demo, or the Health Data screen, does not depend on the CMS sandbox. The fixtures
 * are trimmed copies of Blue Button v2 {@code searchset} Bundles, and every {@code entry[].resource}
 * is returned as Blue Button would return it, including the cancelled Part D coverage and the
 * entered-in-error claim. The status gate is not applied here: {@code EhrController} applies the
 * same {@link MedicareStatusGate} to these resources as to live ones.
 *
 * <p>The data is fabricated, so every envelope built from it is labelled {@code synthetic}
 * ({@link MedicareProperties#isSynthetic()} is true in mock mode).
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
    public MockMedicareSource(final ObjectMapper objectMapper) {
        final List<JsonNode> patients = readResources(objectMapper, PATIENT_FIXTURE);
        this.patient = patients.isEmpty() ? null : patients.get(0);
        this.coverage = readResources(objectMapper, COVERAGE_FIXTURE);
        this.visits = readResources(objectMapper, EOB_FIXTURE);

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

    /** Reads one Bundle fixture and returns its resources in Bundle order. */
    private static List<JsonNode> readResources(final ObjectMapper objectMapper, final String path) {
        final JsonNode bundle = readFixture(objectMapper, path);
        final JsonNode entries = bundle.get("entry");
        if (entries == null || !entries.isArray()) {
            log.warn("[medicare] Fixture {} has no entry array; treating as empty", path);
            return List.of();
        }

        final List<JsonNode> resources = new ArrayList<>(entries.size());
        for (final JsonNode entry : entries) {
            final JsonNode resource = entry.get("resource");
            if (resource != null && !resource.isNull()) {
                resources.add(resource);
            }
        }
        return List.copyOf(resources);
    }

    private static JsonNode readFixture(final ObjectMapper objectMapper, final String path) {
        try (InputStream in = new ClassPathResource(path).getInputStream()) {
            return objectMapper.readTree(in);
        } catch (final IOException e) {
            throw new IllegalStateException("Unable to read Medicare fixture: " + path, e);
        }
    }
}
