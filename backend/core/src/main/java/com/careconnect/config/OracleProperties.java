package com.careconnect.config;

import lombok.Data;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

/**
 * Configuration for the standalone Oracle Health (Cerner) ingest (WBS 5.2.86, "Option B").
 *
 * <p>Points at Oracle Health's <b>open</b> FHIR R4 sandbox, which needs no credentials, so the
 * ingest + mirror pipeline can be exercised end-to-end on synthetic data without the authenticated,
 * patient-scoped path (SMART OAuth) that production/PHI would require. {@code SOURCE_ORACLE} is the
 * canonical catalog token every {@code ehr_*} row keys on.
 */
@Component
@ConfigurationProperties(prefix = "careconnect.oracle")
@Data
public class OracleProperties {

    /** Canonical catalog code for Oracle Health (Cerner). Matches the seeded {@code ehr_source} row. */
    public static final String SOURCE_ORACLE = "ORACLE_HEALTH";

    /** Master switch for the standalone Oracle ingest + its dev endpoint. Off by default. */
    private boolean enabled = false;

    /** Open sandbox FHIR R4 base, no auth. Tenant is appended as {@code <baseUrl>/<tenant>}. */
    private String baseUrl = "https://fhir-open.cerner.com/r4";

    /** Public Oracle Health open-sandbox tenant id. */
    private String tenant = "ec2458f2-1e24-41c8-b71b-0e701af7583d";

    /** A synthetic patient in the open sandbox whose records the ingest pulls. */
    private String sandboxPatientId = "12724066";

    /** FHIR base for the configured tenant, e.g. {@code https://fhir-open.cerner.com/r4/<tenant>}. */
    public String tenantBaseUrl() {
        final String base = baseUrl.endsWith("/") ? baseUrl.substring(0, baseUrl.length() - 1) : baseUrl;
        return base + "/" + tenant;
    }
}
