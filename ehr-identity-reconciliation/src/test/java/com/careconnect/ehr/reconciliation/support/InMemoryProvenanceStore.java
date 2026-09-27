package com.careconnect.ehr.reconciliation.support;

import com.careconnect.ehr.reconciliation.FieldProvenance;
import com.careconnect.ehr.reconciliation.IdentityFieldProvenanceStore;

import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.locks.Lock;
import java.util.concurrent.locks.ReentrantLock;

public final class InMemoryProvenanceStore implements IdentityFieldProvenanceStore {

    private record Key(Object patientId, String fieldName) {
    }

    private final Map<Key, Lock> locks = new ConcurrentHashMap<>();
    private final Map<Key, FieldProvenance> rows = new ConcurrentHashMap<>();

    /** Every acquire-in-order attempted, for assertions in the concurrency test about interleaving. */
    public final List<Key> acquireOrder = new java.util.concurrent.CopyOnWriteArrayList<>();

    @Override
    public Optional<FieldProvenance> lockOrCreate(Object patientId, Object orgId, String fieldName) {
        Key key = new Key(patientId, fieldName);
        Lock lock = locks.computeIfAbsent(key, k -> new ReentrantLock());
        FakeTransactionSupport.acquireForTransaction(lock);
        acquireOrder.add(key);
        return Optional.ofNullable(rows.get(key));
    }

    @Override
    public void recordAsFreshest(Object patientId, Object orgId, String fieldName, Object sourceId, Instant sourceUpdatedAt) {
        rows.put(new Key(patientId, fieldName), new FieldProvenance(sourceId, sourceUpdatedAt));
    }

    public Optional<FieldProvenance> peek(Object patientId, String fieldName) {
        return Optional.ofNullable(rows.get(new Key(patientId, fieldName)));
    }
}
