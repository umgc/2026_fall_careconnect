package com.careconnect.repository.visibility;

import com.careconnect.model.visibility.CaregiverSummaryVisibility;
import com.careconnect.model.visibility.VisibilityStatus;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

@Repository
public interface CaregiverSummaryVisibilityRepository
        extends JpaRepository<CaregiverSummaryVisibility, Long> {

    Optional<CaregiverSummaryVisibility> findByCaregiverUserIdAndPatientUserId(
            Long caregiverUserId, Long patientUserId);

    boolean existsByCaregiverUserIdAndPatientUserIdAndStatus(
            Long caregiverUserId, Long patientUserId, VisibilityStatus status);

    List<CaregiverSummaryVisibility> findByPatientUserIdAndStatus(
            Long patientUserId, VisibilityStatus status);
}
