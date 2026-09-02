package com.careconnect.model.retrieval;

import com.careconnect.service.ai.retrieval.RetrievalRecordType;
import jakarta.persistence.Column;
import jakarta.persistence.Table;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.time.OffsetDateTime;

import static org.assertj.core.api.Assertions.assertThat;

class RetrievalIndexChunkTest {

    private static void assertColumn(Class<?> type, String fieldName, String expectedColumn) throws Exception {
        var field = type.getDeclaredField(fieldName);
        Column column = field.getAnnotation(Column.class);
        assertThat(column).as("@Column on %s", fieldName).isNotNull();
        assertThat(column.name()).isEqualTo(expectedColumn);
    }

    @Test
    @DisplayName("entity table name aligns with schema constant")
    void tableNameMapping() {
        Table table = RetrievalIndexChunk.class.getAnnotation(Table.class);
        assertThat(table).isNotNull();
        assertThat(table.name()).isEqualTo(RetrievalIndexSchema.TABLE_NAME);
    }

    @Test
    @DisplayName("entity column names align with Flyway migration")
    void columnNameMappings() throws Exception {
        assertColumn(RetrievalIndexChunk.class, "patientId", "patient_id");
        assertColumn(RetrievalIndexChunk.class, "recordType", "record_type");
        assertColumn(RetrievalIndexChunk.class, "sourceRecordId", "source_record_id");
        assertColumn(RetrievalIndexChunk.class, "sourceKind", "source_kind");
        assertColumn(RetrievalIndexChunk.class, "chunkText", "chunk_text");
        assertColumn(RetrievalIndexChunk.class, "chunkMetadata", "chunk_metadata");
        assertColumn(RetrievalIndexChunk.class, "indexedAt", "indexed_at");
        assertColumn(RetrievalIndexChunk.class, "consentScope", "consent_scope");
        assertColumn(
                RetrievalIndexChunk.class, "citationReplayAfter", "citation_replay_after");
        assertColumn(
                RetrievalIndexChunk.class, "citationReplayAttempts", "citation_replay_attempts");
        assertColumn(RetrievalIndexChunk.class, "migrationStatus", "migration_status");
    }

    @Test
    @DisplayName("record type enum round-trips through string storage")
    void recordTypeEnumRoundTrip() {
        RetrievalIndexChunk chunk = RetrievalIndexChunk.builder()
                .patientId(42L)
                .sourceRecordId("summary-99")
                .chunkText("Patient discussed medication adherence.")
                .build();

        chunk.setRecordTypeEnum(RetrievalRecordType.CALL_SUMMARY);

        assertThat(chunk.getRecordType()).isEqualTo("CALL_SUMMARY");
        assertThat(chunk.getRecordTypeEnum()).isEqualTo(RetrievalRecordType.CALL_SUMMARY);
    }

    @Test
    @DisplayName("resolveRecordTypeEnum returns empty for unknown stored values")
    void resolveRecordTypeEnumHandlesUnknownValues() {
        RetrievalIndexChunk chunk = RetrievalIndexChunk.builder()
                .patientId(1L)
                .recordType("NOT_A_REAL_TYPE")
                .sourceRecordId("x")
                .chunkText("text")
                .build();

        assertThat(chunk.resolveRecordTypeEnum()).isEmpty();
    }

    @Test
    @DisplayName("onCreate populates indexedAt when missing")
    void onCreateSetsIndexedAt() throws Exception {
        RetrievalIndexChunk chunk = RetrievalIndexChunk.builder()
                .patientId(1L)
                .recordType(RetrievalRecordType.TRANSCRIPT_SEGMENT.name())
                .sourceRecordId("call-abc")
                .chunkText("Hello from the visit.")
                .build();

        var method = RetrievalIndexChunk.class.getDeclaredMethod("onCreate");
        method.setAccessible(true);
        method.invoke(chunk);

        assertThat(chunk.getIndexedAt()).isNotNull();
        assertThat(chunk.getIndexedAt()).isBeforeOrEqualTo(OffsetDateTime.now());
        assertThat(chunk.getCitationReplayAttempts()).isZero();
        assertThat(chunk.getMigrationStatus()).isEqualTo("ACTIVE");
    }
}
