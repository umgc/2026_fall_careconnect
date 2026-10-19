package com.careconnect.controller.ehr;
import com.careconnect.model.ehr.*;
import com.careconnect.service.ehr.EhrService;
import com.careconnect.service.ehr.MedicareRecordCache;
import com.careconnect.service.ehr.MedicareRecordCache.CachedRead;
import com.careconnect.service.ehr.MedicareService;
import com.fasterxml.jackson.databind.JsonNode;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.*;

/**
 * The Medicare reads. Each returns FHIR in a {@link MedicareEnvelope}, served from
 * {@link MedicareRecordCache}: Blue Button is asked again only when the cached data is a day old.
 * With {@code careconnect.medicare.mode=mock} they are served from {@link MockMedicareSource} instead.
 */
@RestController
@Slf4j
public class EhrController{

    @Autowired
    private MedicareService medicareService;

    @Autowired
    private EhrService ehrService;

    @Autowired
    private MedicareRecordCache cache;

    @Autowired
    private MedicareProperties properties;

    /** Cancelled, draft and entered-in-error resources are stored as retrieved but never served (DEF-MCR-19). */
    @Autowired
    private MedicareStatusGate statusGate;

    /** Registered only when {@code careconnect.medicare.mode=mock} ({@link MockMedicareSource}). */
    @Autowired
    private ObjectProvider<MedicareSource> sources;

    private final MedicareResponseMapper mapper = new MedicareResponseMapper();

    @GetMapping("/v1/api/{source}/patient")
    public ResponseEntity<Object> fetchIdentity(@PathVariable String source) {

        // To any other teams, just put your Ehr code in an if block like this.
        if(source.equalsIgnoreCase("medicare")){
            MedicareSource mock = mockSource();
            if (mock != null) {
                return ResponseEntity.ok(MedicareEnvelope.ofSingle(
                        properties.getMode(), properties.isSynthetic(), mapper.toPatientView(mock.fetchPatient()), null));
            }

            Optional<EhrPatientCrosswalk> crosswalkOpt = ehrService.getCrosswalk(medicareService.getId());
            if(crosswalkOpt.isEmpty()){
                // This person has somehow hit this page without actually being logged in and connected.
                // I probably should commend their cunning, but instead I'll just 404 them.
                return ResponseEntity.notFound().build();
            }

            CachedRead read = cache.patient(crosswalkOpt.orElseThrow(), ehrService.currentUserId().orElse(null));
            return ResponseEntity.ok(MedicareEnvelope.ofSingle(
                    properties.getMode(),
                    properties.isSynthetic(),
                    mapper.toPatientView(read.resources().isEmpty() ? null : read.resources().get(0)),
                    read.fetchedAt()));
        }

        // An invalid source was requested. 404 them.
        return ResponseEntity.notFound().build();
    }

    @GetMapping("/v1/api/{source}/coverage")
    public ResponseEntity<Object> fetchCoverage(@PathVariable String source) {

        // To any other teams, just put your Ehr code in an if block like this.
        if(source.equalsIgnoreCase("medicare")) {
            MedicareSource mock = mockSource();
            if (mock != null) {
                return ResponseEntity.ok(MedicareEnvelope.of(
                        properties.getMode(), properties.isSynthetic(), mapper.toCoverageView(allowed(mock.fetchCoverage())), null));
            }

            Optional<EhrPatientCrosswalk> crosswalkOpt = ehrService.getCrosswalk(medicareService.getId());
            if(crosswalkOpt.isEmpty()){
                // This person has somehow hit this page without actually being logged in and connected.
                // I probably should commend their cunning, but instead I'll just 404 them.
                return ResponseEntity.notFound().build();
            }

            CachedRead read = cache.coverage(crosswalkOpt.orElseThrow(), ehrService.currentUserId().orElse(null));
            return ResponseEntity.ok(MedicareEnvelope.of(
                    properties.getMode(), properties.isSynthetic(), mapper.toCoverageView(allowed(read.resources())), read.fetchedAt()));
        }
        return ResponseEntity.notFound().build();
    }

    @GetMapping("/v1/api/{source}/visits")
    public ResponseEntity<Object> fetchVisits(@PathVariable String source) {
        // To any other teams, just put your Ehr code in an if block like this.
        if(source.equalsIgnoreCase("medicare")){
            MedicareSource mock = mockSource();
            if (mock != null) {
                return ResponseEntity.ok(MedicareEnvelope.of(
                        properties.getMode(), properties.isSynthetic(), mapper.toVisitView(allowed(mock.fetchVisits())), null));
            }

            Optional<EhrPatientCrosswalk> crosswalkOpt = ehrService.getCrosswalk(medicareService.getId());
            if(crosswalkOpt.isEmpty()){
                // This person has somehow hit this page without actually being logged in and connected.
                // I probably should commend their cunning, but instead I'll just 404 them.
                return ResponseEntity.notFound().build();
            }

            CachedRead read = cache.visits(crosswalkOpt.orElseThrow(), ehrService.currentUserId().orElse(null));
            return ResponseEntity.ok(MedicareEnvelope.of(
                    properties.getMode(), properties.isSynthetic(), mapper.toVisitView(allowed(read.resources())), read.fetchedAt()));
        }
        return ResponseEntity.notFound().build();
    }

    /**
     * The fixture source in mock mode, which serves every signed-in caller with no Medicare link and no
     * call to Blue Button. Its envelopes carry {@code fetchedAt: null}, since fixtures are never
     * retrieved from Medicare.
     *
     * @return the mock source, or {@code null} in live mode, where the read goes to the cache and Blue Button
     */
    private MedicareSource mockSource() {
        return properties.isMock() ? sources.getIfAvailable() : null;
    }

    // TODO: figure out what to do with this.
    private ResponseEntity<Object> unavailable(String source) {
        final String detail = properties.isEnabled()
                ? "No " + source +  " source is registered for mode '" + properties.getMode() + "'."
                : source + " retrieval is disabled for this environment.";
        log.debug("[{}] Request rejected: {}", source, detail);
        return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE)
                .body(Map.of(
                        "source", MedicareProperties.SOURCE_MEDICARE,
                        "error", "medicare_unavailable",
                        "detail", detail));
    }

    /** The envelope's total is counted after this gate, as {@link MedicareEnvelope} documents. */
    private List<JsonNode> allowed(final List<JsonNode> resources) {
        return resources.stream().filter(statusGate::isAllowed).toList();
    }
}
