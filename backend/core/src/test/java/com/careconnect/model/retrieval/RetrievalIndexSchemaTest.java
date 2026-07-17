package com.careconnect.model.retrieval;

import com.careconnect.service.ai.retrieval.RetrievalRecordType;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

class RetrievalIndexSchemaTest {

    @Test
    @DisplayName("embedding dimension matches backlog pgvector contract")
    void embeddingDimension() {
        assertThat(RetrievalIndexSchema.EMBEDDING_DIMENSION).isEqualTo(1536);
    }

    @Test
    @DisplayName("table name matches Flyway migration")
    void tableName() {
        assertThat(RetrievalIndexSchema.TABLE_NAME).isEqualTo("retrieval_index_chunk");
    }

    @Test
    @DisplayName("FTS text-search config matches trigger and query language")
    void ftsConfig() {
        assertThat(RetrievalIndexSchema.FTS_TEXT_SEARCH_CONFIG).isEqualTo("english");
        assertThat(RetrievalIndexSchema.FTS_QUERY_MAX_LENGTH).isPositive();
    }
}
