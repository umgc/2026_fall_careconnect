package com.careconnect.service.ai.embedding;

import com.careconnect.model.retrieval.RetrievalIndexSchema;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class EmbeddingVectorFormatTest {

    @Test
    @DisplayName("formats exact-dimension float array as pgvector literal")
    void toPgVectorLiteral_formats() {
        final float[] values = new float[RetrievalIndexSchema.EMBEDDING_DIMENSION];
        values[0] = 0.5f;
        values[1] = -0.25f;
        final String literal = EmbeddingVectorFormat.toPgVectorLiteral(values);
        assertThat(literal).startsWith("[0.5,").endsWith("]");
        assertThat(literal.split(",")).hasSize(RetrievalIndexSchema.EMBEDDING_DIMENSION);
    }

    @Test
    @DisplayName("rejects wrong-length vectors")
    void toPgVectorLiteral_wrongLength_throws() {
        assertThatThrownBy(() -> EmbeddingVectorFormat.toPgVectorLiteral(new float[]{1f, 2f}))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining(String.valueOf(RetrievalIndexSchema.EMBEDDING_DIMENSION));
    }
}
