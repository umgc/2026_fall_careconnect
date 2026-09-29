package com.careconnect.repository.ehr;

import com.careconnect.model.ehr.EhrIdentity;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface EhrIdentityRepository extends JpaRepository<EhrIdentity, Long> {
    List<EhrIdentity> findByClientIdOrderByLastUpdatedDesc(Long patientId);

}
