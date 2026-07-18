package com.careconnect.service.ai.ask;

import com.careconnect.dto.ai.AiCitation;
import com.careconnect.service.ai.retrieval.RankedChunk;
import com.careconnect.service.ai.retrieval.RetrievalRecordType;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

class CitationAssemblerTest {

    private final CitationAssembler assembler =
            new CitationAssembler(
                    new CitationDeepLinkBuilder(),
                    new CitationMetadataMapper(new ObjectMapper()));

    @Test
    @DisplayName("assemble validates metadata and keeps retrieval relevance order")
    void assemble_validatesMetadataAndOrdersByRetrievalRank() {
        final Map<String, RankedChunk> map = new LinkedHashMap<>();
        map.put("C1", chunk(
                "C1",
                "summary-1",
                RetrievalRecordType.CALL_SUMMARY,
                "First source",
                """
                        {
                          "callId":"call/42",
                          "title":"Medication check",
                          "occurredAt":"2026-07-17T14:30:00Z",
                          "summaryConfidence":0.82,
                          "contentHash":"must-not-leak"
                        }
                        """,
                0.03d));
        map.put("C2", chunk(
                "C2",
                "summary-2",
                RetrievalRecordType.CALL_SUMMARY,
                "Second source",
                "{\"callId\":\"call-2\"}",
                0.02d));

        final CitationAssembler.CitationResult result =
                assembler.assemble(List.of("C2", "C1"), map);

        assertThat(result.grounded()).isTrue();
        assertThat(result.invalidRefs()).isEmpty();
        assertThat(result.citations())
                .extracting(AiCitation::citationId)
                .containsExactly("C1", "C2");
        final AiCitation first = result.citations().get(0);
        assertThat(first.deepLink()).isEqualTo("/chatandcalls");
        assertThat(first.title()).isEqualTo("Medication check");
        assertThat(first.occurredAt()).hasToString("2026-07-17T14:30:00Z");
        assertThat(first.confidence()).isEqualTo(0.82d);
        assertThat(first.metadata())
                .containsEntry("callId", "call/42")
                .doesNotContainKey("contentHash");
    }

    @Test
    @DisplayName("assemble does not fabricate citations when LLM refs are empty")
    void assemble_emptyRefs_noFabrication() {
        final Map<String, RankedChunk> map = new LinkedHashMap<>();
        map.put("C1", chunk("C1", "a"));
        map.put("C2", chunk("C2", "b"));

        final CitationAssembler.CitationResult result =
                assembler.assemble(List.of(), map);

        assertThat(result.grounded()).isFalse();
        assertThat(result.citations()).isEmpty();
    }

    @Test
    @DisplayName("assemble fails validation when any model ref is unknown")
    void assemble_mixedUnknownRef_notGrounded() {
        final Map<String, RankedChunk> map = new LinkedHashMap<>();
        map.put("C1", chunk("C1", "a"));

        final CitationAssembler.CitationResult result =
                assembler.assemble(List.of("C1", "CX"), map);

        assertThat(result.grounded()).isFalse();
        assertThat(result.invalidRefs()).containsExactly("CX");
        assertThat(result.citations()).hasSize(1);
    }

    @Test
    @DisplayName("confidence is null when metadata is invalid and never uses RRF score")
    void assemble_invalidConfidence_doesNotUseRrfScore() {
        final RankedChunk chunk = chunk(
                "C1",
                "doc/1",
                RetrievalRecordType.UPLOADED_DOCUMENT,
                "  First line\nsecond\tline  ",
                "{\"confidence\":1.2,\"private\":\"hidden\"}",
                0.99d);

        final CitationAssembler.CitationResult result =
                assembler.assemble(List.of("C1"), Map.of("C1", chunk));

        assertThat(result.grounded()).isTrue();
        assertThat(result.citations().get(0).confidence()).isNull();
        assertThat(result.citations().get(0).excerpt()).isEqualTo("First line second line");
        assertThat(result.citations().get(0).deepLink()).isEqualTo("/file-management");
        assertThat(result.citations().get(0).metadata()).isEmpty();
    }

    @Test
    @DisplayName("blank source text cannot become a grounded citation")
    void assemble_blankExcerpt_invalidatesCitation() {
        final RankedChunk chunk = chunk(
                "C1",
                "source",
                RetrievalRecordType.CALL_SUMMARY,
                " \n\t ",
                "{\"callId\":\"call-1\"}",
                0.1d);

        final CitationAssembler.CitationResult result =
                assembler.assemble(List.of("C1"), Map.of("C1", chunk));

        assertThat(result.grounded()).isFalse();
        assertThat(result.invalidRefs()).containsExactly("C1");
        assertThat(result.citations()).isEmpty();
    }

    @Test
    @DisplayName("source identifiers are validated rather than normalized")
    void assemble_sourceIdentifierWithWhitespace_invalidatesCitation() {
        final RankedChunk chunk = chunk(
                "C1",
                " doc-1 ",
                RetrievalRecordType.UPLOADED_DOCUMENT,
                "Document text",
                null,
                0.1d);

        final CitationAssembler.CitationResult result =
                assembler.assemble(List.of("C1"), Map.of("C1", chunk));

        assertThat(result.grounded()).isFalse();
        assertThat(result.invalidRefs()).containsExactly("C1");
    }

    @Test
    @DisplayName("excerpt truncation respects Unicode code points and the 240-character contract")
    void assemble_longUnicodeExcerpt_truncatesSafely() {
        final RankedChunk chunk = chunk(
                "C1",
                "doc-1",
                RetrievalRecordType.UPLOADED_DOCUMENT,
                "😀".repeat(300),
                null,
                0.1d);

        final AiCitation citation =
                assembler.assemble(List.of("C1"), Map.of("C1", chunk)).citations().get(0);

        assertThat(citation.excerpt()).endsWith("…");
        assertThat(citation.excerpt().codePointCount(0, citation.excerpt().length()))
                .isEqualTo(240);
    }

    private static RankedChunk chunk(final String ref, final String sourceId) {
        return chunk(
                ref,
                sourceId,
                RetrievalRecordType.CALL_SUMMARY,
                "text for " + ref,
                "{\"callId\":\"call-1\"}",
                0.05d);
    }

    private static RankedChunk chunk(
            final String ref,
            final String sourceId,
            final RetrievalRecordType recordType,
            final String text,
            final String metadata,
            final double rrfScore) {
        return new RankedChunk(
                UUID.randomUUID(),
                1L,
                recordType,
                sourceId,
                text,
                metadata,
                "auto",
                rrfScore,
                1,
                null,
                ref);
    }
}
