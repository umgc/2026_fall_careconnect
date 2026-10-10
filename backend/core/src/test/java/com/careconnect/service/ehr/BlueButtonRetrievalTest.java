package com.careconnect.service.ehr;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.util.ArrayList;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * The result of a paged Blue Button retrieval, complete or partial (DEF-MCR-01, FR-MCR-32).
 * <p>
 * Test IDs TC-MCR-FHIR-036..039 are permanent. Never renumber, never reuse.
 */
class BlueButtonRetrievalTest {

    @Test
    @DisplayName("TC-MCR-FHIR-036: a complete retrieval has every page and no failure")
    void complete() {
        final BlueButtonRetrieval<String> r = BlueButtonRetrieval.complete(List.of("a", "b"), 2);

        assertThat(r.isComplete()).isTrue();
        assertThat(r.records()).containsExactly("a", "b");
        assertThat(r.pagesRetrieved()).isEqualTo(2);
        assertThat(r.failedPage()).isNull();
        assertThat(r.failureStatus()).isNull();
        assertThat(r.failureMessage()).isNull();
    }

    @Test
    @DisplayName("TC-MCR-FHIR-037: a partial retrieval keeps the records it got and says which page failed and how")
    void partial() {
        final BlueButtonRetrieval<String> r = BlueButtonRetrieval.partial(List.of("a"), 1, 2, 503, "unavailable");

        assertThat(r.isComplete()).isFalse();
        assertThat(r.records()).containsExactly("a");
        assertThat(r.pagesRetrieved()).isEqualTo(1);
        assertThat(r.failedPage()).isEqualTo(2);
        assertThat(r.failureStatus()).isEqualTo(503);
        assertThat(r.failureMessage()).isEqualTo("unavailable");
    }

    @Test
    @DisplayName("TC-MCR-FHIR-038: records are copied: changing the caller's list afterwards does not change the result, and the result is read-only")
    void recordsAreDefensivelyCopied() {
        final List<String> source = new ArrayList<>(List.of("a"));
        final BlueButtonRetrieval<String> r = BlueButtonRetrieval.complete(source, 1);
        source.add("b");

        assertThat(r.records()).containsExactly("a");
        assertThatThrownBy(() -> r.records().add("c")).isInstanceOf(UnsupportedOperationException.class);
    }

    @Test
    @DisplayName("TC-MCR-FHIR-039: a null record list is refused rather than stored")
    void nullRecordsRefused() {
        assertThatThrownBy(() -> BlueButtonRetrieval.complete(null, 0)).isInstanceOf(NullPointerException.class);
    }
}
