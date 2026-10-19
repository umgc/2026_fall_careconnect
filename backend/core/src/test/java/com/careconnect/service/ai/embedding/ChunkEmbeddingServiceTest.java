package com.careconnect.service.ai.embedding;

import com.careconnect.model.retrieval.RetrievalIndexChunk;
import com.careconnect.model.retrieval.RetrievalIndexSchema;
import com.careconnect.repository.retrieval.RetrievalIndexChunkRepository;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import software.amazon.awssdk.core.SdkBytes;
import software.amazon.awssdk.services.bedrockruntime.BedrockRuntimeClient;
import software.amazon.awssdk.services.bedrockruntime.model.BedrockRuntimeException;
import software.amazon.awssdk.services.bedrockruntime.model.InvokeModelRequest;
import software.amazon.awssdk.services.bedrockruntime.model.InvokeModelResponse;

import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class ChunkEmbeddingServiceTest {

    @Mock
    private RetrievalIndexChunkRepository chunkRepository;
    @Mock
    private BedrockRuntimeClient bedrockRuntimeClient;

    private ObjectMapper objectMapper;

    private static RetrievalIndexChunk chunk(final String text) {
        return RetrievalIndexChunk.builder()
                .id(UUID.randomUUID())
                .patientId(1L)
                .recordType("CALL_SUMMARY")
                .sourceRecordId("99")
                .chunkText(text)
                .build();
    }

    private static float[] sampleVector(final float fill) {
        final float[] values = new float[RetrievalIndexSchema.EMBEDDING_DIMENSION];
        for (int i = 0; i < values.length; i++) {
            values[i] = fill;
        }
        return values;
    }

    @BeforeEach
    void setUp() {
        objectMapper = new ObjectMapper();
    }

    @Test
    @DisplayName("embedAndPersist no-ops when embedding disabled")
    void embedAndPersist_disabled_skipsBedrock() {
        final ChunkEmbeddingService service = newService(false, bedrockRuntimeClient);
        final RetrievalIndexChunk chunk = chunk("hello");

        assertThat(service.embedAndPersist(List.of(chunk))).isZero();
        verify(bedrockRuntimeClient, never()).invokeModel(any(InvokeModelRequest.class));
        verify(chunkRepository, never()).updateEmbedding(any(), any());
    }

    @Test
    @DisplayName("embedAndPersist no-ops when Bedrock client is absent")
    void embedAndPersist_noClient_skips() {
        final ChunkEmbeddingService service = newService(true, null);
        assertThat(service.embedAndPersist(List.of(chunk("hello")))).isZero();
        verify(chunkRepository, never()).updateEmbedding(any(), any());
    }

    @Test
    @DisplayName("embedAndPersist writes pgvector literal after Titan response")
    void embedAndPersist_writesVector() throws Exception {
        final float[] values = sampleVector(0.25f);
        when(bedrockRuntimeClient.invokeModel(any(InvokeModelRequest.class)))
                .thenReturn(InvokeModelResponse.builder()
                        .body(SdkBytes.fromUtf8String(embeddingJson(values)))
                        .build());

        final ChunkEmbeddingService service = newService(true, bedrockRuntimeClient);
        final RetrievalIndexChunk chunk = chunk("Patient started metformin.");

        assertThat(service.embedAndPersist(List.of(chunk))).isEqualTo(1);

        final ArgumentCaptor<String> literalCaptor = ArgumentCaptor.forClass(String.class);
        verify(chunkRepository).updateEmbedding(org.mockito.ArgumentMatchers.eq(chunk.getId()), literalCaptor.capture());
        assertThat(literalCaptor.getValue()).startsWith("[").endsWith("]");
        assertThat(literalCaptor.getValue().split(",")).hasSize(RetrievalIndexSchema.EMBEDDING_DIMENSION);
    }

    @Test
    @DisplayName("embedAndPersist continues when one chunk fails")
    void embedAndPersist_partialFailure_continues() throws Exception {
        when(bedrockRuntimeClient.invokeModel(any(InvokeModelRequest.class)))
                .thenThrow(new RuntimeException("throttled"))
                .thenReturn(InvokeModelResponse.builder()
                        .body(SdkBytes.fromUtf8String(embeddingJson(sampleVector(0.1f))))
                        .build());

        final ChunkEmbeddingService service = newService(true, bedrockRuntimeClient);
        final RetrievalIndexChunk first = chunk("fail me");
        final RetrievalIndexChunk second = chunk("succeed");

        assertThat(service.embedAndPersist(List.of(first, second))).isEqualTo(1);
        verify(chunkRepository, times(1)).updateEmbedding(any(), any());
    }

    @Test
    @DisplayName("invokeTitanEmbed rejects wrong-dimension responses")
    void invokeTitanEmbed_wrongDimension_throws() {
        when(bedrockRuntimeClient.invokeModel(any(InvokeModelRequest.class)))
                .thenReturn(InvokeModelResponse.builder()
                        .body(SdkBytes.fromUtf8String("{\"embedding\":[0.1,0.2]}"))
                        .build());
        final ChunkEmbeddingService service = newService(true, bedrockRuntimeClient);

        assertThatThrownBy(() -> service.invokeTitanEmbed("text"))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("expected");
    }

    @Test
    @DisplayName("constructor rejects Titan v2 while schema requires 1536-d")
    void constructor_rejectsTitanV2() {
        assertThatThrownBy(() -> new ChunkEmbeddingService(
                chunkRepository,
                objectMapper,
                bedrockRuntimeClient,
                true,
                "amazon.titan-embed-text-v2:0",
                25,
                8000))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("titan-embed-text-v1");
    }

    @Test
    @DisplayName("invokeTitanEmbed retries on ThrottlingException then succeeds")
    void invokeTitanEmbed_retriesThrottle() throws Exception {
        final BedrockRuntimeException throttled = (BedrockRuntimeException) BedrockRuntimeException
                .builder()
                .message("Rate exceeded")
                .awsErrorDetails(software.amazon.awssdk.awscore.exception.AwsErrorDetails.builder()
                        .errorCode("ThrottlingException")
                        .build())
                .build();
        when(bedrockRuntimeClient.invokeModel(any(InvokeModelRequest.class)))
                .thenThrow(throttled)
                .thenReturn(InvokeModelResponse.builder()
                        .body(SdkBytes.fromUtf8String(embeddingJson(sampleVector(0.2f))))
                        .build());

        final ChunkEmbeddingService service = newService(true, bedrockRuntimeClient);
        assertThat(service.invokeTitanEmbed("retry me")).hasSize(RetrievalIndexSchema.EMBEDDING_DIMENSION);
        verify(bedrockRuntimeClient, times(2)).invokeModel(any(InvokeModelRequest.class));
    }

    @Test
    @DisplayName("embedQuery returns empty when embedding disabled")
    void embedQuery_disabled_returnsEmpty() {
        final ChunkEmbeddingService service = newService(false, bedrockRuntimeClient);
        assertThat(service.embedQuery("metformin")).isEmpty();
        verify(bedrockRuntimeClient, never()).invokeModel(any(InvokeModelRequest.class));
    }

    @Test
    @DisplayName("embedQuery returns Titan vector for query text")
    void embedQuery_returnsVector() throws Exception {
        final float[] values = sampleVector(0.5f);
        when(bedrockRuntimeClient.invokeModel(any(InvokeModelRequest.class)))
                .thenReturn(InvokeModelResponse.builder()
                        .body(SdkBytes.fromUtf8String(embeddingJson(values)))
                        .build());
        final ChunkEmbeddingService service = newService(true, bedrockRuntimeClient);

        assertThat(service.embedQuery("blood pressure")).hasValueSatisfying(v ->
                assertThat(v).hasSize(RetrievalIndexSchema.EMBEDDING_DIMENSION));
    }

    private ChunkEmbeddingService newService(
            final boolean enabled, final BedrockRuntimeClient client) {
        return new ChunkEmbeddingService(
                chunkRepository,
                objectMapper,
                client,
                enabled,
                "amazon.titan-embed-text-v1",
                25,
                8000);
    }

    private String embeddingJson(final float[] values) throws Exception {
        final java.util.List<Float> list = new java.util.ArrayList<>(values.length);
        for (final float value : values) {
            list.add(value);
        }
        return objectMapper.writeValueAsString(java.util.Map.of("embedding", list));
    }
}
