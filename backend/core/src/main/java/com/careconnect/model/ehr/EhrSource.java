package com.careconnect.model.ehr;

import com.careconnect.model.Auditable;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

/**
 * Registry of external EHR systems that adapters pull from.
 *
 * <p>One row per integrated source (athenahealth, Epic, Medicare, Oracle Health). This table
 * holds identity and capability metadata only — connection endpoints, client ids, and secrets
 * stay in configuration, never in the database.
 */
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
@Entity
@Table(name = "ehr_source")
public class EhrSource extends Auditable {

    /** Maximum length of the stable source code. */
    private static final int CODE_LENGTH = 32;

    /** Maximum length of the human-readable source name. */
    private static final int DISPLAY_NAME_LENGTH = 128;

    /** Maximum length of the FHIR version marker. */
    private static final int FHIR_VERSION_LENGTH = 16;

    /** Database primary key. */
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    /**
     * Stable machine code for the source, for example {@code ATHENA} or {@code EPIC}.
     * Adapters key off this rather than the display name or the surrogate id.
     */
    @Column(name = "code", nullable = false, unique = true, length = CODE_LENGTH)
    private String code;

    /** Human-readable name shown to patients and staff, for example "athenahealth". */
    @Column(name = "display_name", nullable = false, length = DISPLAY_NAME_LENGTH)
    private String displayName;

    /**
     * FHIR version this source is integrated against. The reconciliation design assumes R4
     * for every source; persisting it makes that assumption auditable rather than tribal,
     * and gives a place to record any source that has to deviate.
     */
    @Builder.Default
    @Column(name = "fhir_version", nullable = false, length = FHIR_VERSION_LENGTH)
    private String fhirVersion = "R4";

    /** Whether adapters should currently sync from this source. */
    @Builder.Default
    @Column(name = "active", nullable = false)
    private boolean active = true;
}
