package com.careconnect.medicare;

import java.util.Map;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * Read-only Medicare endpoints, WBS 1.4.1-1.4.2 / issue #132.
 *
 * <p>Three reads, one per resource type the Blue Button spike proved out:
 * {@code GET /v1/api/medicare/patient}, {@code /coverage} and {@code /visits}. All three answer
 * with a {@link MedicareEnvelope} so a client parses one shape regardless of endpoint or mode.
 *
 * <p>Nothing here writes. See {@link MedicareSource} for why persistence is out of scope on
 * this branch.
 */
@Slf4j
@RestController
@RequestMapping("/v1/api/medicare")
@RequiredArgsConstructor
public class MedicareController {

    private final MedicareProperties properties;
    private final MedicareResponseMapper mapper;

    /**
     * Resolved lazily rather than injected directly so that setting {@code mode=live} before a
     * live source exists yields a 503 on the route instead of a context that refuses to start.
     */
    private final ObjectProvider<MedicareSource> sources;

    /** The beneficiary's demographics. */
    @GetMapping("/patient")
    public ResponseEntity<Object> patient() {
        final MedicareSource source = resolveSource();
        if (source == null) {
            return unavailable();
        }
        return ResponseEntity.ok(
                MedicareEnvelope.ofSingle(
                        properties.getMode(),
                        properties.isMock(),
                        mapper.toPatientView(source.fetchPatient())));
    }

    /** The beneficiary's Medicare enrollment, one entry per part. */
    @GetMapping("/coverage")
    public ResponseEntity<Object> coverage() {
        final MedicareSource source = resolveSource();
        if (source == null) {
            return unavailable();
        }
        return ResponseEntity.ok(
                MedicareEnvelope.of(
                        properties.getMode(),
                        properties.isMock(),
                        mapper.toCoverageView(source.fetchCoverage())));
    }

    /** The beneficiary's claims history. */
    @GetMapping("/visits")
    public ResponseEntity<Object> visits() {
        final MedicareSource source = resolveSource();
        if (source == null) {
            return unavailable();
        }
        return ResponseEntity.ok(
                MedicareEnvelope.of(
                        properties.getMode(),
                        properties.isMock(),
                        mapper.toVisitView(source.fetchVisits())));
    }

    /**
     * @return the configured source, or {@code null} when Medicare is switched off for this
     *     environment or the configured mode has no implementation yet
     */
    private MedicareSource resolveSource() {
        if (!properties.isEnabled()) {
            return null;
        }
        return sources.getIfAvailable();
    }

    private ResponseEntity<Object> unavailable() {
        final String detail = properties.isEnabled()
                ? "No Medicare source is registered for mode '" + properties.getMode() + "'."
                : "Medicare retrieval is disabled for this environment.";
        log.debug("[medicare] Request rejected: {}", detail);
        return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE)
                .body(Map.of(
                        "source", MedicareProperties.SOURCE_MEDICARE,
                        "error", "medicare_unavailable",
                        "detail", detail));
    }
}
