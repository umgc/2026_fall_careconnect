import com.careconnect.ehr.reconciliation.FieldProvenance;
import com.careconnect.ehr.reconciliation.IdentityFieldProvenanceStore;

import java.time.Instant;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Deliberately broken: no row lock at all, just a plain read/write. Used ONLY to prove the
 * concurrency contract test actually fails without correct locking, so the passing result against
 * the real InMemoryProvenanceStore isn't vacuous. Not part of the shipped library.
 */
public class UnsafeProvenanceStore implements IdentityFieldProvenanceStore {
    private record Key(Object patientId, String fieldName) {}
    private final Map<Key, FieldProvenance> rows = new ConcurrentHashMap<>();

    @Override
    public Optional<FieldProvenance> lockOrCreate(Object patientId, String fieldName) {
        // No lock taken at all -- this is the bug.
        return Optional.ofNullable(rows.get(new Key(patientId, fieldName)));
    }

    @Override
    public void recordAsFreshest(Object patientId, String fieldName, Object sourceId, Instant sourceUpdatedAt) {
        rows.put(new Key(patientId, fieldName), new FieldProvenance(sourceId, sourceUpdatedAt));
    }
}
