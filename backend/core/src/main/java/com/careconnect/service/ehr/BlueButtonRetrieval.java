package com.careconnect.service.ehr;

import java.util.List;

/**
 * The outcome of a paged Blue Button retrieval (WBS 6.2.35, DEF-MCR-01).
 * <p>
 * If a later page fails after its retries, the records from the pages that did arrive are kept
 * here instead of being thrown away, and the failure says how far retrieval got. A caller can then
 * store or show what it has and know the data is incomplete.
 *
 * @param records        every record retrieved, in page order
 * @param pagesRetrieved how many pages arrived successfully
 * @param failedPage     the 1-based page that failed, or {@code null} if retrieval completed
 * @param failureStatus  the HTTP status of that failure, or {@code null} if retrieval completed
 * @param failureMessage the failure's message, or {@code null} if retrieval completed
 */
public record BlueButtonRetrieval<T>(
        List<T> records,
        int pagesRetrieved,
        Integer failedPage,
        Integer failureStatus,
        String failureMessage) {

    public BlueButtonRetrieval {
        records = List.copyOf(records);
    }

    static <T> BlueButtonRetrieval<T> complete(final List<T> records, final int pages) {
        return new BlueButtonRetrieval<>(records, pages, null, null, null);
    }

    static <T> BlueButtonRetrieval<T> partial(final List<T> records, final int pages,
                                              final int failedPage, final int status, final String message) {
        return new BlueButtonRetrieval<>(records, pages, failedPage, status, message);
    }

    /** True when every page arrived. */
    public boolean isComplete() {
        return failedPage == null;
    }
}
