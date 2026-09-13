package com.careconnect.service.ehr;

import com.fasterxml.jackson.databind.JsonNode;

import java.util.List;
import java.util.Map;

/**
 * Shared EHR connector contract (Findings R1) — the ONLY component that parses a source's
 * wire format. Epic is the first adapter ({@link EpicFhirClient}, WBS 2.2.2); Medicare/Aetna/
 * Oracle become sibling adapters later. Read-only.
 *
 * <p>Resources are returned as Jackson {@link JsonNode} (no HAPI dependency) and flattened
 * downstream by mappers/chunkers.
 */
public interface EhrApiClient {

    /** Source discriminator, e.g. "EPIC". */
    String sourceCode();

    /**
     * Fetch one FHIR resource type for the connected patient, following Bundle paging.
     *
     * @param userId       CareConnect user id (owns the stored credential)
     * @param resourceType FHIR resource type, e.g. "Condition"
     * @param params       extra query params (category, status, ...); {@code patient} is added by the adapter
     * @return the {@code Bundle.entry[].resource} nodes across all pages
     */
    List<JsonNode> fetch(Long userId, String resourceType, Map<String, String> params);

    /** {@code Patient/$everything} bundle for the fastest first-connect RAG backfill. */
    JsonNode everything(Long userId);
}
