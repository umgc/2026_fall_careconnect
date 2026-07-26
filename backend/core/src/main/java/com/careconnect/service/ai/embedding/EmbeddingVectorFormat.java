package com.careconnect.service.ai.embedding;

import com.careconnect.model.retrieval.RetrievalIndexSchema;

/**
 * Formats float embeddings as PostgreSQL {@code vector} literals for
 * {@link com.careconnect.repository.retrieval.RetrievalIndexChunkRepository#updateEmbedding}.
 */
public final class EmbeddingVectorFormat {

    private EmbeddingVectorFormat() {
    }

    /**
     * @param values embedding floats; must match {@link RetrievalIndexSchema#EMBEDDING_DIMENSION}
     * @return pgvector literal such as {@code [0.1,0.2,...]}
     */
    public static String toPgVectorLiteral(final float[] values) {
        if (values == null) {
            throw new IllegalArgumentException("embedding values are required");
        }
        if (values.length != RetrievalIndexSchema.EMBEDDING_DIMENSION) {
            throw new IllegalArgumentException(
                    "Expected embedding length "
                            + RetrievalIndexSchema.EMBEDDING_DIMENSION
                            + " but was "
                            + values.length);
        }
        final StringBuilder sb = new StringBuilder(values.length * 8);
        sb.append('[');
        for (int i = 0; i < values.length; i++) {
            if (i > 0) {
                sb.append(',');
            }
            sb.append(Float.toString(values[i]));
        }
        sb.append(']');
        return sb.toString();
    }
}
