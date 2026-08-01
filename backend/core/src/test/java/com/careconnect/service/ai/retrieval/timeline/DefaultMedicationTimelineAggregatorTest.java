package com.careconnect.service.ai.retrieval.timeline;

import static org.assertj.core.api.Assertions.assertThat;

import com.careconnect.dto.ai.MedicationTimelineDto;
import com.careconnect.dto.ai.MedicationTimelineEventDto;
import com.careconnect.service.ai.retrieval.RankedChunk;
import com.careconnect.service.ai.retrieval.RetrievalRecordType;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

@DisplayName("DefaultMedicationTimelineAggregator Tests")
class DefaultMedicationTimelineAggregatorTest {

    private final DefaultMedicationTimelineAggregator aggregator =
            new DefaultMedicationTimelineAggregator(new ObjectMapper());

    private static RankedChunk medicationChunk(
            final String citationRef,
            final String itemId,
            final String medicationName,
            final String medicationNameNormalized,
            final String eventType,
            final String effectiveDate) {
        final String metadata = "{"
                + "\"section\":\"medication_timeline\","
                + "\"itemId\":\"" + itemId + "\","
                + "\"type\":\"medication\","
                + "\"eventType\":\"" + eventType + "\","
                + "\"status\":\"" + eventType + "\","
                + "\"medicationName\":\"" + medicationName + "\","
                + "\"medicationNameNormalized\":\"" + medicationNameNormalized + "\","
                + "\"effectiveDate\":\"" + effectiveDate + "\""
                + "}";
        return new RankedChunk(
                UUID.randomUUID(),
                42L,
                RetrievalRecordType.MEDICATION_TIMELINE_EVENT,
                itemId,
                "Medication " + eventType + ": " + medicationName,
                metadata,
                "on_consent",
                0.05d,
                1,
                1,
                citationRef);
    }

    private static RankedChunk nonMedicationChunk(final String citationRef) {
        return new RankedChunk(
                UUID.randomUUID(),
                42L,
                RetrievalRecordType.CALL_SUMMARY,
                "99",
                "Some unrelated call summary text",
                "{\"contentHash\":\"abc\"}",
                "auto",
                0.03d,
                1,
                1,
                citationRef);
    }

    @Test
    @DisplayName("returns null when chunks is null or empty")
    void aggregate_returnsNullWhenNoChunks() {
        assertThat(aggregator.aggregate(null)).isNull();
        assertThat(aggregator.aggregate(List.of())).isNull();
    }

    @Test
    @DisplayName("returns null when no chunks are medication timeline events")
    void aggregate_returnsNullWhenNoMedicationEvents() {
        assertThat(aggregator.aggregate(List.of(nonMedicationChunk("C1")))).isNull();
    }

    @Test
    @DisplayName("builds a chronologically sorted timeline from medication timeline chunks")
    void aggregate_sortsEventsByEffectiveDate() {
        final RankedChunk stopped = medicationChunk(
                "C2", "item-2", "Metformin", "metformin", "stopped", "2026-03-01");
        final RankedChunk started = medicationChunk(
                "C1", "item-1", "Metformin", "metformin", "started", "2026-01-15");

        final MedicationTimelineDto timeline =
                aggregator.aggregate(List.of(stopped, started, nonMedicationChunk("C3")));

        assertThat(timeline).isNotNull();
        assertThat(timeline.events()).hasSize(2);
        assertThat(timeline.events().get(0).effectiveDate()).isEqualTo("2026-01-15");
        assertThat(timeline.events().get(0).eventType()).isEqualTo("started");
        assertThat(timeline.events().get(0).citationRef()).isEqualTo("C1");
        assertThat(timeline.events().get(1).effectiveDate()).isEqualTo("2026-03-01");
        assertThat(timeline.events().get(1).eventType()).isEqualTo("stopped");
    }

    @Test
    @DisplayName("dedupes events by itemId, keeping the first occurrence")
    void aggregate_dedupesByItemId() {
        final RankedChunk first = medicationChunk(
                "C1", "item-1", "Metformin", "metformin", "started", "2026-01-15");
        final RankedChunk duplicate = medicationChunk(
                "C4", "item-1", "Metformin", "metformin", "started", "2026-01-15");

        final MedicationTimelineDto timeline = aggregator.aggregate(List.of(first, duplicate));

        assertThat(timeline).isNotNull();
        assertThat(timeline.events()).hasSize(1);
        assertThat(timeline.events().get(0).citationRef()).isEqualTo("C1");
    }

    @Test
    @DisplayName("dedupes events without itemId by medicationNameNormalized+effectiveDate+eventType")
    void aggregate_dedupesByFingerprintWhenItemIdMissing() {
        final RankedChunk first = new RankedChunk(
                UUID.randomUUID(),
                42L,
                RetrievalRecordType.MEDICATION_TIMELINE_EVENT,
                "1",
                "Medication started: Metformin",
                "{\"medicationName\":\"Metformin\",\"medicationNameNormalized\":\"metformin\","
                        + "\"eventType\":\"started\",\"effectiveDate\":\"2026-01-15\"}",
                "on_consent",
                0.05d,
                1,
                1,
                "C1");
        final RankedChunk duplicateFingerprint = new RankedChunk(
                UUID.randomUUID(),
                42L,
                RetrievalRecordType.MEDICATION_TIMELINE_EVENT,
                "2",
                "Medication started: Metformin",
                "{\"medicationName\":\"Metformin\",\"medicationNameNormalized\":\"metformin\","
                        + "\"eventType\":\"started\",\"effectiveDate\":\"2026-01-15\"}",
                "on_consent",
                0.05d,
                1,
                1,
                "C2");

        final MedicationTimelineDto timeline =
                aggregator.aggregate(List.of(first, duplicateFingerprint));

        assertThat(timeline).isNotNull();
        assertThat(timeline.events()).hasSize(1);
        assertThat(timeline.events().get(0).citationRef()).isEqualTo("C1");
    }

    @Test
    @DisplayName("ignores chunks with unparseable or missing medication name metadata")
    void aggregate_ignoresChunksMissingMedicationName() {
        final RankedChunk malformedJson = new RankedChunk(
                UUID.randomUUID(),
                42L,
                RetrievalRecordType.MEDICATION_TIMELINE_EVENT,
                "1",
                "text",
                "not-json",
                "on_consent",
                0.05d,
                1,
                1,
                "C1");
        final RankedChunk missingName = new RankedChunk(
                UUID.randomUUID(),
                42L,
                RetrievalRecordType.MEDICATION_TIMELINE_EVENT,
                "2",
                "text",
                "{\"eventType\":\"started\"}",
                "on_consent",
                0.05d,
                1,
                1,
                "C2");

        assertThat(aggregator.aggregate(List.of(malformedJson, missingName))).isNull();
    }

    @Test
    @DisplayName("falls back to status field when eventType is absent")
    void aggregate_fallsBackToStatusField() {
        final RankedChunk chunk = new RankedChunk(
                UUID.randomUUID(),
                42L,
                RetrievalRecordType.MEDICATION_TIMELINE_EVENT,
                "1",
                "text",
                "{\"medicationName\":\"Metformin\",\"status\":\"active\","
                        + "\"effectiveDate\":\"2026-02-01\"}",
                "on_consent",
                0.05d,
                1,
                1,
                "C1");

        final MedicationTimelineEventDto event =
                aggregator.aggregate(List.of(chunk)).events().get(0);

        assertThat(event.eventType()).isEqualTo("active");
    }

    @Test
    @DisplayName("accepts non-textual JSON fields for dates and doses")
    void aggregate_acceptsNumericMetadataFields() {
        final RankedChunk chunk = new RankedChunk(
                UUID.randomUUID(),
                42L,
                RetrievalRecordType.MEDICATION_TIMELINE_EVENT,
                "1",
                "text",
                "{\"medicationName\":\"Metformin\",\"medicationNameNormalized\":\"metformin\","
                        + "\"eventType\":\"dose_changed\",\"effectiveDate\":20260115,"
                        + "\"doseFrom\":500,\"doseTo\":1000,\"itemId\":\"item-9\"}",
                "on_consent",
                0.05d,
                1,
                1,
                "C1");

        final MedicationTimelineEventDto event =
                aggregator.aggregate(List.of(chunk)).events().get(0);

        assertThat(event.itemId()).isEqualTo("item-9");
        assertThat(event.effectiveDate()).isEqualTo("20260115");
        assertThat(event.doseFrom()).isEqualTo("500");
        assertThat(event.doseTo()).isEqualTo("1000");
    }
}
