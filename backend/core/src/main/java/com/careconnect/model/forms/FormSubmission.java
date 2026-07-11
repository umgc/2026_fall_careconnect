package com.careconnect.model.forms;

import com.careconnect.model.UserFile;
import jakarta.persistence.*;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;

/**
 * A completed (or in-progress) instance of a {@link FormDefinition} for a
 * specific person.
 * <p>
 * Captured field values are stored as JSONB keyed by
 * {@code "<sectionId>.<fieldId>"}. Integration with the existing file system
 * is explicit:
 * <ul>
 *   <li>{@link #userFileId} references the {@code UserFile} row holding the
 *       generated, signed PDF of this submission;</li>
 *   <li>{@link #supportingUserFileIds} references additional {@code UserFile}
 *       rows for supporting evidence (e.g., I-9 List A/B/C documents, voided
 *       check, TB result);</li>
 *   <li>{@link #ownerId}/{@link #ownerType} mirror the {@code UserFile}
 *       ownership model so submissions and their files share the same subject.</li>
 * </ul>
 */
@Entity
@Table(
    name = "form_submissions",
    indexes = {
        @Index(name = "idx_form_submission_owner", columnList = "owner_id, owner_type"),
        @Index(name = "idx_form_submission_definition", columnList = "form_definition_id"),
        @Index(name = "idx_form_submission_user_file", columnList = "user_file_id")
    }
)
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class FormSubmission {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    /** The form definition version this submission was completed against. */
    @Column(name = "form_definition_id", nullable = false)
    private Long formDefinitionId;

    /** Denormalized snapshot of the form type for convenient querying. */
    @Column(name = "form_type", nullable = false)
    @Enumerated(EnumType.STRING)
    private FormType formType;

    /** Denormalized snapshot of the definition version. */
    @Column(name = "form_version", nullable = false)
    private String formVersion;

    /** Subject of the submission (mirrors UserFile.ownerId). */
    @Column(name = "owner_id", nullable = false)
    private Long ownerId;

    /** Subject type (mirrors UserFile.ownerType). */
    @Column(name = "owner_type", nullable = false)
    @Enumerated(EnumType.STRING)
    private UserFile.OwnerType ownerType;

    @Column(name = "patient_id")
    private Long patientId;

    @Column(name = "status", nullable = false)
    @Enumerated(EnumType.STRING)
    @Builder.Default
    private SubmissionStatus status = SubmissionStatus.DRAFT;

    /** Captured values keyed by "sectionId.fieldId". */
    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "field_values", columnDefinition = "jsonb")
    private Map<String, Object> fieldValues;

    /** UserFile holding the generated signed PDF of this submission. */
    @Column(name = "user_file_id")
    private Long userFileId;

    /** UserFile ids for supporting evidence uploaded with this submission. */
    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "supporting_user_file_ids", columnDefinition = "jsonb")
    private List<Long> supportingUserFileIds;

    @Column(name = "submitted_at")
    private LocalDateTime submittedAt;

    @Column(name = "reviewed_by")
    private Long reviewedBy;

    @Column(name = "reviewed_at")
    private LocalDateTime reviewedAt;

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
            this.status = SubmissionStatus.DRAFT;
        }
    }

    @PreUpdate
    protected void onUpdate() {
        this.updatedAt = LocalDateTime.now();
    }

    /** Review lifecycle of a submitted form. */
    public enum SubmissionStatus {
        DRAFT,
        SUBMITTED,
        APPROVED,
        REJECTED
    }
}
