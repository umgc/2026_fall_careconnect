package com.careconnect.dto.ehr;

import java.util.List;

/**
 * One page of {@code GET /api/athena/resources}. There is no total count by design: computing one
 * costs a second query, and the client pages until {@code hasNext} is false.
 *
 * @param items   the records, newest first, in the same shape as the Unified Health Data list
 * @param page    zero-based page number actually served
 * @param size    page size actually served
 * @param hasNext whether another page follows
 */
public record AthenaResourcePage(List<EhrResourceListItem> items, int page, int size, boolean hasNext) {
}
