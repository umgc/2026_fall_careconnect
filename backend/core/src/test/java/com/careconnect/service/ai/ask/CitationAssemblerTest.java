package com.careconnect.service.ai.ask;

import com.careconnect.dto.ai.AiCitation;
import com.careconnect.service.ai.retrieval.RankedChunk;
import com.careconnect.service.ai.retrieval.RetrievalRecordType;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

class CitationAssemblerTest {

    @Test
    @DisplayName("assemble keeps only valid citation refs in order")
    void assemble_filtersAndOrders() {
        final Map<String, RankedChunk> map = new LinkedHashMap<>();
        map.put("C1", chunk("C1", "src-1"));
        map.put("C2", chunk("C2", "src-2"));

        final CitationAssembler.CitationResult result =
                CitationAssembler.assemble(List.of("C2", "CX", "C1"), map);

        assertThat(result.modelCited()).isTrue();
        assertThat(result.citations()).extracting(AiCitation::citationId).containsExactly("C2", "C1");
        assertThat(result.citations().get(0).deepLink()).contains("CALL_SUMMARY");
        assertThat(result.citations().get(0).sourceRecordId()).isEqualTo("src-2");
    }

    @Test
    @DisplayName("assemble does not fabricate citations when LLM refs are empty")
    void assemble_emptyRefs_noFabrication() {
        final Map<String, RankedChunk> map = new LinkedHashMap<>();
        map.put("C1", chunk("C1", "a"));
        map.put("C2", chunk("C2", "b"));

        final CitationAssembler.CitationResult result =
                CitationAssembler.assemble(List.of(), map);

        assertThat(result.modelCited()).isFalse();
        assertThat(result.citations()).isEmpty();
    }

    @Test
    @DisplayName("assemble ignores unknown refs and stays uncited when none match")
    void assemble_unknownRefsOnly() {
        final Map<String, RankedChunk> map = new LinkedHashMap<>();
        map.put("C1", chunk("C1", "a"));

        final CitationAssembler.CitationResult result =
                CitationAssembler.assemble(List.of("CX", "CY"), map);

        assertThat(result.modelCited()).isFalse();
        assertThat(result.citations()).isEmpty();
    }

    private static RankedChunk chunk(final String ref, final String sourceId) {
        return new RankedChunk(
                UUID.randomUUID(),
                1L,
                RetrievalRecordType.CALL_SUMMARY,
                sourceId,
                "text for " + ref,
                null,
                "auto",
                0.05d,
                1,
                null,
                ref);
    }
}
