package com.careconnect.ehr.reconciliation.support;

import com.careconnect.ehr.reconciliation.IdentityConflictAuditWriter;
import com.careconnect.ehr.reconciliation.RecordedDecision;

import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.concurrent.CopyOnWriteArrayList;

public final class InMemoryAuditWriter implements IdentityConflictAuditWriter {

    private enum Status { PENDING, ACCEPTED, REJECTED }

    private record Row(
            Long patientId, Long sourceId, String fieldName,
            String canonicalValueBefore, String incomingValue, Instant sourceUpdatedAt,
            Status status, ResolvedBy resolvedBy, Instant detectedAt, Instant resolvedAt) {
    }

    /** Mutable only via {@link CopyOnWriteArrayList#set}, so a resolve/supersede replaces in place. */
    private final List<Row> rows = new CopyOnWriteArrayList<>();

    @Override
    public void recordDecision(Long patientId, Long sourceId, String fieldName,
                                String canonicalValueBefore, String incomingValue, Instant sourceUpdatedAt,
                                Outcome outcome, ResolvedBy resolvedBy, Instant detectedAndResolvedAt) {
        // Stored, not null. This fake used to write null here, which cost nothing in memory and could
        // never have been written to ehr_identity_conflict.source_updated_at (NOT NULL) -- the gap that
        // building the JPA writer exposed on 2026-09-29.
        rows.add(new Row(patientId, sourceId, fieldName, canonicalValueBefore, incomingValue,
                sourceUpdatedAt, toStatus(outcome), resolvedBy, detectedAndResolvedAt, detectedAndResolvedAt));
    }

    @Override
    public void openPendingConflict(Long patientId, Long sourceId, String fieldName,
                                     String canonicalValueBefore, String incomingValue, Instant sourceUpdatedAt,
                                     Instant detectedAt) {
        boolean alreadyOpen = rows.stream().anyMatch(r -> r.status() == Status.PENDING
                && r.patientId().equals(patientId) && r.fieldName().equals(fieldName));
        if (alreadyOpen) {
            // Mirrors the real ehr_identity_conflict open-conflict uniqueness constraint: callers must
            // resolvePendingConflict the existing row before opening another for the same field.
            throw new IllegalStateException("A PENDING conflict is already open for " + patientId + "/" + fieldName
                    + " -- resolve it before opening another.");
        }
        rows.add(new Row(patientId, sourceId, fieldName, canonicalValueBefore, incomingValue,
                sourceUpdatedAt, Status.PENDING, null, detectedAt, null));
    }

    @Override
    public Optional<PendingConflict> currentPendingConflict(Long patientId, String fieldName) {
        return rows.stream()
                .filter(r -> r.status() == Status.PENDING && r.patientId().equals(patientId) && r.fieldName().equals(fieldName))
                .findFirst()
                .map(r -> new PendingConflict(r.sourceId(), r.canonicalValueBefore(), r.incomingValue(),
                        r.sourceUpdatedAt(), r.detectedAt()));
    }

    @Override
    public boolean patientHasDeclined(Long patientId, Long sourceId, String fieldName, String incomingValue) {
        return rows.stream().anyMatch(r -> r.status() == Status.REJECTED && r.resolvedBy() == ResolvedBy.PATIENT
                && r.patientId().equals(patientId) && r.sourceId().equals(sourceId) && r.fieldName().equals(fieldName)
                && r.incomingValue().equals(incomingValue));
    }

    @Override
    public void resolvePendingConflict(Long patientId, String fieldName, Outcome outcome, ResolvedBy resolvedBy,
                                        Instant resolvedAt) {
        for (int i = 0; i < rows.size(); i++) {
            Row r = rows.get(i);
            if (r.status() == Status.PENDING && r.patientId().equals(patientId) && r.fieldName().equals(fieldName)) {
                rows.set(i, new Row(r.patientId(), r.sourceId(), r.fieldName(), r.canonicalValueBefore(),
                        r.incomingValue(), r.sourceUpdatedAt(), toStatus(outcome), resolvedBy, r.detectedAt(), resolvedAt));
                return;
            }
        }
        throw new IllegalStateException("No open PENDING conflict for " + patientId + "/" + fieldName);
    }

    /** Finalized decisions only -- an open PENDING row is not a "decision" yet; see {@link #currentPendingConflict}. */
    public List<RecordedDecision> decisionsFor(Long patientId, String fieldName) {
        return rows.stream()
                .filter(r -> r.status() != Status.PENDING)
                .filter(r -> r.patientId().equals(patientId) && r.fieldName().equals(fieldName))
                .map(r -> new RecordedDecision(r.fieldName(), r.canonicalValueBefore(), r.incomingValue(),
                        r.status() == Status.ACCEPTED ? Outcome.ACCEPTED : Outcome.REJECTED, r.resolvedBy()))
                .toList();
    }

    private static Status toStatus(Outcome outcome) {
        return outcome == Outcome.ACCEPTED ? Status.ACCEPTED : Status.REJECTED;
    }
}
