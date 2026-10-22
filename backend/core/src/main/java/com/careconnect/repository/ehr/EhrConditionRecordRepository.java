package com.careconnect.repository.ehr;

import com.careconnect.model.ehr.EhrConditionRecord;
import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;

/** Access to source-separated normalized Condition records. */
public interface EhrConditionRecordRepository extends JpaRepository<EhrConditionRecord, Long> {

    Optional<EhrConditionRecord> findByPatientIdAndSourceIdAndExternalConditionId(
            Long patientId, Long sourceId, String externalConditionId);

    List<EhrConditionRecord> findByPatientIdAndSourceId(Long patientId, Long sourceId);
}
