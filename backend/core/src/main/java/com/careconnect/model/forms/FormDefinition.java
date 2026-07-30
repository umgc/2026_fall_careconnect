package com.careconnect.model.forms;

import jakarta.persistence.*;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

import java.time.LocalDate;
import java.time.LocalDateTime;

/**
 * Persisted, versioned definition of a required hiring/onboarding form.
 * <p>
 * The complete structured schema (sections, fields, required status, and
 * validation rules) is stored as JSONB in {@link #schemaJson}, while the
 * version and effective-date metadata are first-class columns so the active
 * version for a given {@link FormType} can be resolved with a simple query.
 * <p>
 * A {@code (formType, version)} pair is unique; at most one row per form type
 * is {@link FormStatus#ACTIVE} at a time.
 */
@Entity
@Table(
    name = "form_definitions",
    uniqueConstraints = @UniqueConstraint(name = "uk_form_definition_type_version",
                                          columnNames = {"form_type", "version"})
)
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class FormDefinition {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "form_type", nullable = false)
    @Enumerated(EnumType.STRING)
    private FormType formType;

    @Column(name = "version", nullable = false)
    private String version;

    @Column(name = "title", nullable = false)
    private String title;

    @Column(name = "effective_date", nullable = false)
    private LocalDate effectiveDate;

    @Column(name = "expiration_date")
    private LocalDate expirationDate;

    @Column(name = "status", nullable = false)
    @Enumerated(EnumType.STRING)
    @Builder.Default
    private FormStatus status = FormStatus.DRAFT;

    /** Official source form number, e.g. "W-4", "I-9". */
    @Column(name = "source_form_number")
    private String sourceFormNumber;

    /** Official source edition label, e.g. "2026", "01/20/2025". */
    @Column(name = "source_edition")
    private String sourceEdition;

    /**
     * UserFile.FileCategory under which completed submissions of this form are
     * filed. Links the form schema to the existing file-attachment taxonomy.
     */
    @Column(name = "file_category", nullable = false)
    private String fileCategory;

    /** Full structured schema (sections/fields/validation/source mappings). */
    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "schema_json", nullable = false, columnDefinition = "jsonb")
    private FormSchema schemaJson;

    @Column(name = "created_at", nullable = false, updatable = false)
    private LocalDateTime createdAt;

    @Column(name = "updated_at")
    private LocalDateTime updatedAt;

    @PrePersist
    protected void onCreate() {
        LocalDateTime now = LocalDateTime.now();
        this.createdAt = now;
        this.updatedAt = now;
        if (this.status == null) {
            this.status = FormStatus.DRAFT;
        }
    }

    @PreUpdate
    protected void onUpdate() {
        this.updatedAt = LocalDateTime.now();
    }

    /** Lifecycle state of a form definition version. */
    public enum FormStatus {
        DRAFT,
        ACTIVE,
        RETIRED
    }
}
