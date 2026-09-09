package com.careconnect.repository.ehr;

import com.careconnect.model.ehr.EHRIdentity;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.OffsetDateTime;
import java.util.Optional;
import java.util.List;

public interface EHRIdentityRepository extends JpaRepository<EHRIdentity, Long> {

    List<EHRIdentity> findByClientIdAndSourceIdOrderByLastUpdatedDesc(Long patientId, Long sourceId);

    void deleteByClientIdandSourceId(Long patientId, Long sourceId);

}
