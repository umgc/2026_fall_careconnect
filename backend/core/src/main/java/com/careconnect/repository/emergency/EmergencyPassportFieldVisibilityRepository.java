package com.careconnect.repository.emergency;

import com.careconnect.model.emergency.EmergencyPassportFieldVisibility;
import com.careconnect.model.emergency.PassportField;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.EnumSet;
import java.util.List;
import java.util.Optional;
import java.util.Set;

public interface EmergencyPassportFieldVisibilityRepository
        extends JpaRepository<EmergencyPassportFieldVisibility, Long> {

    /** Every stored choice for the patient, hidden ones included. Fields never set have no row. */
    List<EmergencyPassportFieldVisibility> findByPatientId(Long patientId);

    Optional<EmergencyPassportFieldVisibility> findByPatientIdAndFieldKey(Long patientId, PassportField fieldKey);

    List<EmergencyPassportFieldVisibility> findByPatientIdAndIsPublicTrue(Long patientId);

    /**
     * The fields this patient has made public. The answer to "what may the passport show": a field
     * with no row, or with {@code is_public = false}, is not in the set.
     */
    default Set<PassportField> findPublicFields(Long patientId) {
        Set<PassportField> fields = EnumSet.noneOf(PassportField.class);
        for (EmergencyPassportFieldVisibility row : findByPatientIdAndIsPublicTrue(patientId)) {
            fields.add(row.getFieldKey());
        }
        return fields;
    }
}
