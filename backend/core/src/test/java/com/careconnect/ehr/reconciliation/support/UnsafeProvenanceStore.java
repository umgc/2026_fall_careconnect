package com.careconnect.ehr.reconciliation.support;

import com.careconnect.ehr.reconciliation.FieldProvenance;
import com.careconnect.ehr.reconciliation.IdentityFieldProvenanceStore;

import java.time.Instant;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Deliberately broken: a plain read and write with no lock at all.
 * <p>
 * It exists so the passing concurrency result against {@link InMemoryProvenanceStore} is not
 * vacuous. A concurrency test nobody has watched fail is not evidence of anything, and this is what
 * makes the failure reproducible on demand rather than a claim in a commit message.
 * <p>
 * Ported into {@code src/test} on 2026-09-30. It previously lived in {@code
 * ehr-identity-reconciliation/manual-verify/} at the repository root, outside every Maven module, so
 * nothing compiled it and no linter saw it. Raised in the PR #209 review — and by then already true:
 * the {@code Object}-to-{@code Long} id change had broken those files hours earlier and the build
 * could not have told us, because it never read them. Being compiled alongside the interfaces it
 * implements is the whole point of the move.
 */
public final class UnsafeProvenanceStore implements IdentityFieldProvenanceStore {

    private record Key(Long patientId, String fieldName) {
    }

    private final Map<Key, FieldProvenance> rows = new ConcurrentHashMap<>();

    @Override
    public Optional<FieldProvenance> lockOrCreate(Long patientId, String fieldName) {
        // No lock taken. This is the bug being demonstrated.
        return Optional.ofNullable(rows.get(new Key(patientId, fieldName)));
    }

    @Override
    public void recordAsFreshest(Long patientId, String fieldName, Long sourceId, Instant sourceUpdatedAt) {
        rows.put(new Key(patientId, fieldName), new FieldProvenance(sourceId, sourceUpdatedAt));
    }
}
