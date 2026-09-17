package com.careconnect.repository.EHR;

import com.careconnect.model.EHR.EHRIdentity;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.OffsetDateTime;
import java.util.Optional;
import java.util.List;

public interface EHRIdentityRepository extends JpaRepository<EHRIdentity, Long> {
    List<EHRIdentity> findByClientIdOrderByLastUpdatedDesc(Long patientId);

}
