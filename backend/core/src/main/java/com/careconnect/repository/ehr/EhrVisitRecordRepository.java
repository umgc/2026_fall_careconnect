package com.careconnect.repository.ehr;

import com.careconnect.model.ehr.EhrVisitRecord;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface EhrVisitRecordRepository extends JpaRepository<EhrVisitRecord, Long> {
    List<EhrVisitRecord> findByClientIdOrderByLastUpdatedDesc(Long patientId);

}
