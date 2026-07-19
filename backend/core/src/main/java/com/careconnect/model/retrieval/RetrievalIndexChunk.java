package com.careconnect.model.retrieval;

import com.careconnect.service.ai.retrieval.RetrievalRecordType;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

import java.time.OffsetDateTime;
import java.util.Optional;
import java.util.UUID;

/**
 * JPA entity for a single Ask AI retrieval index chunk (Task 1.5).
 *
 * <p>Maps portable columns used by {@link com.careconnect.repository.retrieval.RetrievalIndexChunkRepository}.
 * PostgreSQL-specific columns {@code search_vector} and {@code embedding} are defined in Flyway
 * and maintained or written via native SQL. {@code search_vector} is auto-maintained by the
 * {@code trg_retrieval_index_chunk_search_vector} trigger on {@code chunk_text} writes (Task 4.2)
 * and queried through {@link com.careconnect.service.ai.retrieval.FullTextSearchService}.
 * Embeddings are written in Task 4.3.
 *
 * <p>{@link #patientId} is the patient entity id ({@code patient.id}) and is the mandatory
 * RBAC scope key for every retrieval query (FR-AI-1).
 */
@Entity
@Table(
        name = RetrievalIndexSchema.TABLE_NAME,
        indexes = {
                @Index(name = "idx_retrieval_chunk_patient_id", columnList = "patient_id"),
                @Index(name = "idx_retrieval_chunk_patient_record_type", columnList = "patient_id, record_type"),
                @Index(name = "idx_retrieval_chunk_source", columnList = "source_record_id, record_type")
                // GIN (search_vector) and ivfflat (embedding) indexes are created by Flyway only.
        }
)
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class RetrievalIndexChunk {

    @Id
    @GeneratedValue
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    @Column(name = "patient_id", nullable = false)
    private Long patientId;

    /**
     * Stored as {@link RetrievalRecordType#name()} for extensibility without enum migrations.
     */
    @Column(name = "record_type", nullable = false, length = RetrievalIndexSchema.RECORD_TYPE_MAX_LENGTH)
    private String recordType;

    @Column(name = "source_record_id", nullable = false, length = RetrievalIndexSchema.SOURCE_RECORD_ID_MAX_LENGTH)
    private String sourceRecordId;

    /** First-class ownership discriminator for sources whose table-local IDs can collide. */
    @Column(name = "source_kind", length = RetrievalIndexSchema.RECORD_TYPE_MAX_LENGTH)
    private String sourceKind;

    @Column(name = "chunk_text", nullable = false, columnDefinition = "TEXT")
    private String chunkText;

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "chunk_metadata", columnDefinition = "jsonb")
    private String chunkMetadata;

    @Column(name = "indexed_at", nullable = false)
    private OffsetDateTime indexedAt;

    @Column(name = "consent_scope", length = RetrievalIndexSchema.CONSENT_SCOPE_MAX_LENGTH)
    private String consentScope;

    /**
     * Compatibility-only replay state. New claims are owned by one
     * summary_citation_replay_source row per source identity.
     */
    @Column(name = "citation_replay_after")
    private OffsetDateTime citationReplayAfter;

    /** Compatibility-only; source-level attempts are authoritative. */
    @Column(name = "citation_replay_attempts", nullable = false)
    private Integer citationReplayAttempts;

    /** Compatibility-only; source-level leases are authoritative. */
    @Column(name = "citation_replay_claimed_until")
    private OffsetDateTime citationReplayClaimedUntil;

    /** Compatibility-only; the source table's UUID token is the active fence. */
    @Column(name = "citation_replay_claim_token")
    private UUID citationReplayClaimToken;

    @Column(name = "migration_status", nullable = false, length = 24)
    private String migrationStatus;

    public RetrievalRecordType getRecordTypeEnum() {
        return recordType == null ? null : RetrievalRecordType.valueOf(recordType);
    }

    /**
     * Returns the record type when valid; empty for null or unknown stored values.
     */
    public Optional<RetrievalRecordType> resolveRecordTypeEnum() {
        if (recordType == null) {
            return Optional.empty();
        }
        try {
            return Optional.of(RetrievalRecordType.valueOf(recordType));
        } catch (IllegalArgumentException ex) {
            return Optional.empty();
        }
    }

    public void setRecordTypeEnum(RetrievalRecordType type) {
        this.recordType = type == null ? null : type.name();
    }

    @PrePersist
    private void onCreate() {
        if (indexedAt == null) {
            indexedAt = OffsetDateTime.now();
        }
        if (citationReplayAttempts == null) {
            citationReplayAttempts = 0;
        }
        if (migrationStatus == null) {
            migrationStatus = "ACTIVE";
        }
    }
}
