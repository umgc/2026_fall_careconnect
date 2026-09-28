package com.careconnect.ehr.reconciliation;

import java.time.Instant;

/**
 * The currently-known freshest source for one {@code (patientId, fieldName)} pair — i.e. one row of
 * the {@code ehr_identity_field_provenance} table this library requires (see README.md for the DDL).
 * This is the piece the original reconciliation design deferred ("Deferred, not built now: a
 * field_provenance JSONB summary column on patient... don't pre-build it"). It stopped being safely
 * deferrable the moment reconciliation ownership decentralized to four independently-built adapters
 * (2026-09-26 decision) — a single coordinating service could reconstruct "what's the current
 * freshest value for this field" from context or an in-memory cache; four uncoordinated ones racing
 * against the same patient's row cannot, without a durable, lockable place to compare against.
 *
 * @param sourceId        which {@code ehr_source} this provenance currently reflects.
 * @param sourceUpdatedAt that source's {@code source_updated_at} at the time it last won (or tied)
 *                        the comparison for this field.
 */
public record FieldProvenance(Object sourceId, Instant sourceUpdatedAt) {
}
