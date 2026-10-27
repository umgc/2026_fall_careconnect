package com.careconnect.ehr;

import com.careconnect.config.AthenaProperties;
import com.careconnect.config.EpicProperties;
import com.careconnect.config.OracleProperties;
import com.careconnect.model.ehr.MedicareProperties;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Drift guard for the EHR source-code contract (WBS 5.2.82, All-EHRs Unified Health Step 1).
 *
 * <p>The value a connector writes to {@code ehr_resource.source} must equal the {@code ehr_source}
 * catalog {@code code} seeded in {@code SchemaPatchRunner}, because the frontend decides a record's
 * provenance by exact-matching that stored string. If a source constant and the catalog code drift
 * apart, records are silently dropped from the Unified Health screen (the live Athena-dropped defect
 * this step addresses). These assertions pin each connector's source constant to its canonical
 * catalog token so the two cannot diverge without a failing build.
 *
 * <p>Canonical catalog set (the single source of truth, seeded in {@code SchemaPatchRunner}):
 * {@code EPIC}, {@code ATHENAHEALTH}, {@code MEDICARE}, {@code ORACLE_HEALTH}. A plain unit
 * assertion is used rather than a Spring/JPA context because the contract is a compile-time constant
 * relationship, not a runtime one — the catalog rows are literals in the seed.
 */
@DisplayName("EHR source-code catalog contract (WBS 5.2.82)")
class SourceCodeCatalogContractTest {

    @Test
    @DisplayName("Epic writes the catalog code EPIC")
    void epicSourceMatchesCatalog() {
        assertThat(EpicProperties.SOURCE_EPIC).isEqualTo("EPIC");
    }

    @Test
    @DisplayName("Athena writes the catalog code ATHENAHEALTH (not ATHENA)")
    void athenaSourceMatchesCatalog() {
        // The historical mismatch: Athena stores ATHENAHEALTH while the frontend matched ATHENA.
        // The canonical token is the catalog code; the frontend adds ATHENAHEALTH (Team E half).
        assertThat(AthenaProperties.SOURCE_ATHENA).isEqualTo("ATHENAHEALTH");
    }

    @Test
    @DisplayName("Medicare's source constant is the catalog code MEDICARE")
    void medicareSourceMatchesCatalog() {
        assertThat(MedicareProperties.SOURCE_MEDICARE).isEqualTo("MEDICARE");
    }

    @Test
    @DisplayName("Oracle Health's source constant is the catalog code ORACLE_HEALTH")
    void oracleSourceMatchesCatalog() {
        // The standalone Oracle ingest (WBS 5.2.86) writes this to ehr_resource.source via the
        // ORACLE_HEALTH catalog row, so the producer constant is now pinned like the others.
        assertThat(OracleProperties.SOURCE_ORACLE).isEqualTo("ORACLE_HEALTH");
    }
}
