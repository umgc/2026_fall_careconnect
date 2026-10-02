package com.careconnect.model.ehr;

import com.careconnect.model.Auditable;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

/**
 * Registry of the external EHR sources the canonical {@code ehr_*} tables may reference,
 * seeded with ATHENAHEALTH, MEDICARE, EPIC and ORACLE_HEALTH.
 * <p>
 * Every canonical table keys its rows by {@code source_id} rather than repeating the source
 * name, so a mistyped source is rejected by the database instead of silently creating a
 * fifth source.
 * <p>
 * {@code ehr_audit_event} deliberately does <em>not</em> reference this table: it is an
 * append-only log whose rows must stay readable verbatim even if a source is renamed or
 * removed, so it stores the source name as text.
 * <p>
 * Extends {@link Auditable} for {@code created_at}/{@code updated_at} rather than declaring
 * its own timestamps, matching the rest of the model package.
 */
@Getter
@Setter
@Builder
@NoArgsConstructor
@AllArgsConstructor
@Entity
@Table(name = "ehr_source")
public class EhrSource extends Auditable {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    /** Stable machine-readable identifier, e.g. ATHENAHEALTH. Never displayed to users. */
    @Column(name = "code", nullable = false, unique = true, length = 64)
    private String code;

    /** Name shown to users, e.g. "athenahealth". */
    @Column(name = "display_name", nullable = false, length = 128)
    private String displayName;

    /**
     * FHIR version this source is integrated against. The design assumes R4 for every
     * source; persisting it makes that assumption auditable rather than tribal, and gives a
     * place to record any source that has to deviate.
     */
    @Column(name = "fhir_version", nullable = false, length = 16)
    @Builder.Default
    private String fhirVersion = "R4";

    /**
     * False suppresses retrieval from this source without deleting rows that reference it,
     * so an adapter can be taken out of service and the degraded-state path exercised
     * (FR-EHR-11) while its history stays intact.
     */
    @Column(name = "enabled", nullable = false)
    @Builder.Default
    private Boolean enabled = Boolean.TRUE;

    /**
     * Covers the no-arg-constructor path, where Lombok's builder defaults do not apply.
     * Named to avoid colliding with {@link Auditable}'s own {@code onCreate} callback, which
     * JPA invokes first.
     */
    @PrePersist
    void applyDefaults() {
        if (fhirVersion == null) {
            fhirVersion = "R4";
        }
        if (enabled == null) {
            enabled = Boolean.TRUE;
        }
    }
}
