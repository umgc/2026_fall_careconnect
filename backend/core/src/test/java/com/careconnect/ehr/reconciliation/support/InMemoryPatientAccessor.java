package com.careconnect.ehr.reconciliation.support;

import com.careconnect.ehr.reconciliation.PatientFieldAccessor;

import java.time.Instant;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;

public final class InMemoryPatientAccessor implements PatientFieldAccessor {

    private final Map<String, String> fieldsByCompositeKey = new ConcurrentHashMap<>();
    private final Map<Object, Instant> patientUpdatedAt = new ConcurrentHashMap<>();

    private static String key(Long patientId, String fieldName) {
        return patientId + "::" + fieldName;
    }

    public void seedCurrentValue(Long patientId, String fieldName, String value) {
        fieldsByCompositeKey.put(key(patientId, fieldName), value);
    }

    public void seedPatientUpdatedAt(Long patientId, Instant instant) {
        patientUpdatedAt.put(patientId, instant);
    }

    @Override
    public Optional<String> getCurrentValue(Long patientId, String fieldName) {
        String v = fieldsByCompositeKey.get(key(patientId, fieldName));
        return (v == null || v.isBlank()) ? Optional.empty() : Optional.of(v);
    }

    @Override
    public Instant getPatientUpdatedAt(Long patientId) {
        return patientUpdatedAt.getOrDefault(patientId, Instant.EPOCH);
    }

    @Override
    public void applyValue(Long patientId, String fieldName, String newValue) {
        fieldsByCompositeKey.put(key(patientId, fieldName), newValue);
    }
}
