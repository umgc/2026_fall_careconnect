package com.careconnect.dto.ehr;

/**
 * One row of the EHR source catalog returned by {@code GET /api/ehr/sources} (WBS 5.2.82).
 *
 * <p>Projection of {@link com.careconnect.model.ehr.EhrSource} that exposes only the
 * non-sensitive registry fields the frontend needs to map a stored {@code ehr_resource.source}
 * code to a display label and know whether the source is live. Lets the Flutter client drive its
 * source handling from the DB catalog (the single source of truth) instead of hardcoding tokens,
 * so backend {@code ehr_source} and frontend {@code RecordSource} cannot silently drift.
 *
 * @param code        stable machine-readable identifier (e.g. {@code EPIC}, {@code ATHENAHEALTH})
 * @param displayName user-facing name (e.g. {@code "athenahealth"})
 * @param enabled     whether retrieval from this source is currently active
 */
public record EhrSourceView(String code, String displayName, boolean enabled) {
}
