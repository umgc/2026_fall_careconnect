package com.careconnect.model;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.Table;

import java.time.LocalDateTime;

import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

/**
 * Persisted archive metadata for transcript content stored outside the primary segment table.
 */
@Entity
@Getter
@Setter
@NoArgsConstructor
@Table(
        name = "call_transcript_archives",
        indexes = {
                @Index(name = "idx_call_transcript_archive_call_id", columnList = "call_id"),
                @Index(name = "idx_call_transcript_archive_archived_at", columnList = "archived_at")
        })
public class CallTranscriptArchive extends Auditable {

    /**
     * Maximum length for call identifier columns.
     */
    private static final int CALL_ID_LENGTH = 120;

    /**
     * Maximum length for storage provider values.
     */
    private static final int STORAGE_PROVIDER_LENGTH = 24;

    /**
     * Maximum length for storage keys and participant lists.
     */
    private static final int LARGE_TEXT_KEY_LENGTH = 512;

    /**
     * Maximum length for checksum values.
     */
    private static final int CHECKSUM_LENGTH = 128;

    /**
     * Database identifier for the archive row.
     */
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    /**
     * Call identifier associated with the archive.
     */
    @Column(name = "call_id", nullable = false, length = CALL_ID_LENGTH)
    private String callId;

    /**
     * Storage provider that owns the archived transcript.
     */
    @Column(name = "storage_provider", nullable = false, length = STORAGE_PROVIDER_LENGTH)
    private String storageProvider;

    /**
     * Storage key used to locate the archived transcript object.
     */
    @Column(name = "storage_key", nullable = false, length = LARGE_TEXT_KEY_LENGTH)
    private String storageKey;

    /**
     * Number of transcript segments included in the archive.
     */
    @Column(name = "segment_count", nullable = false)
    private Integer segmentCount;

    /**
     * Total transcript character count captured in the archive.
     */
    @Column(name = "transcript_chars", nullable = false)
    private Integer transcriptChars;

    /**
     * Serialized list of participant user identifiers.
     */
    @Column(name = "participant_user_ids", length = LARGE_TEXT_KEY_LENGTH)
    private String participantUserIds;

    /**
     * SHA-256 checksum for archive integrity verification.
     */
    @Column(name = "sha256_checksum", length = CHECKSUM_LENGTH)
    private String sha256Checksum;

    /**
     * Timestamp when the transcript archive was created.
     */
    @Column(name = "archived_at", nullable = false)
    private LocalDateTime archivedAt;
}
