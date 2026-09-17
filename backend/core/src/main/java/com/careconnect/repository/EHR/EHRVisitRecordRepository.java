package com.careconnect.repository.EHR;

import com.careconnect.model.EHR.EHRVisitRecord;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.OffsetDateTime;
import java.util.Optional;
import java.util.List;

public interface EHRVisitRecordRepository extends JpaRepository<EHRVisitRecord, Long> {
    List<EHRVisitRecord> findByClientIdOrderByLastUpdatedDesc(Long patientId);

}
