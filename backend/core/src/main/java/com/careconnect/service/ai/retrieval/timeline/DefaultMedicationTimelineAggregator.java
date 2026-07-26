package com.careconnect.service.ai.retrieval.timeline;

import com.careconnect.dto.ai.MedicationTimelineDto;
import com.careconnect.dto.ai.MedicationTimelineEventDto;
import com.careconnect.service.ai.retrieval.RankedChunk;
import com.careconnect.service.ai.retrieval.RetrievalRecordType;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;

/**
 * Default {@link MedicationTimelineAggregator}: parses
 * {@link RankedChunk#chunkMetadata()} JSON for {@code MEDICATION_TIMELINE_EVENT} chunks,
 * deduplicates by {@code itemId} (falling back to
 * {@code medicationNameNormalized+effectiveDate+eventType}), and sorts the result
 * chronologically by {@code effectiveDate} (Task 5).
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class DefaultMedicationTimelineAggregator implements MedicationTimelineAggregator {

    private final ObjectMapper objectMapper;

    @Override
    public MedicationTimelineDto aggregate(final List<RankedChunk> chunks) {
        if (chunks == null || chunks.isEmpty()) {
            return null;
        }

        final Map<String, MedicationTimelineEventDto> deduped = new LinkedHashMap<>();
        for (final RankedChunk chunk : chunks) {
            if (chunk == null || chunk.recordType() != RetrievalRecordType.MEDICATION_TIMELINE_EVENT) {
                continue;
            }
            final MedicationTimelineEventDto event = toEvent(chunk);
            if (event == null) {
                continue;
            }
            final String key = dedupeKey(event);
            deduped.putIfAbsent(key, event);
        }

        if (deduped.isEmpty()) {
            return null;
        }

        final List<MedicationTimelineEventDto> events = new ArrayList<>(deduped.values());
        events.sort(Comparator.comparing(
                MedicationTimelineEventDto::effectiveDate,
                Comparator.nullsLast(Comparator.naturalOrder())));
        return new MedicationTimelineDto(List.copyOf(events));
    }

    private MedicationTimelineEventDto toEvent(final RankedChunk chunk) {
        final JsonNode metadata = parseMetadata(chunk.chunkMetadata());
        if (metadata == null) {
            return null;
        }
        final String medicationName = textOrNull(metadata, "medicationName");
        if (medicationName == null) {
            return null;
        }
        return new MedicationTimelineEventDto(
                textOrNull(metadata, "itemId"),
                medicationName,
                textOrNull(metadata, "medicationNameNormalized"),
                firstNonBlank(textOrNull(metadata, "eventType"), textOrNull(metadata, "status")),
                textOrNull(metadata, "effectiveDate"),
                textOrNull(metadata, "doseFrom"),
                textOrNull(metadata, "doseTo"),
                chunk.citationRef());
    }

    private static String dedupeKey(final MedicationTimelineEventDto event) {
        if (event.itemId() != null && !event.itemId().isBlank()) {
            return "id:" + event.itemId();
        }
        return "fp:" + nullToEmpty(event.medicationNameNormalized())
                + '|' + nullToEmpty(event.effectiveDate())
                + '|' + nullToEmpty(event.eventType());
    }

    private JsonNode parseMetadata(final String chunkMetadataJson) {
        if (chunkMetadataJson == null || chunkMetadataJson.isBlank()) {
            return null;
        }
        try {
            return objectMapper.readTree(chunkMetadataJson);
        } catch (final Exception ex) {
            if (log.isWarnEnabled()) {
                log.warn("Failed to parse medication timeline chunk metadata: {}", ex.getMessage());
            }
            return null;
        }
    }

    private static String textOrNull(final JsonNode node, final String field) {
        if (node == null) {
            return null;
        }
        final JsonNode value = node.get(field);
        if (value == null || value.isNull()) {
            return null;
        }
        // Accept textual and non-textual JSON (numbers/bools) so dose/date metadata
        // typed as numbers is not dropped.
        final String text = value.asText();
        return text == null || text.isBlank() ? null : text;
    }

    private static String firstNonBlank(final String a, final String b) {
        return a != null && !a.isBlank() ? a : b;
    }

    private static String nullToEmpty(final String value) {
        return value == null ? "" : value;
    }
}
