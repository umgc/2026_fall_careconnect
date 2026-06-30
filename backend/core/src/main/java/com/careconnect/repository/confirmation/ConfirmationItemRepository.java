package com.careconnect.repository.confirmation;

import com.careconnect.model.confirmation.ConfirmationItem;
import com.careconnect.model.confirmation.ConfirmationSourceType;
import com.careconnect.model.confirmation.ConfirmationStatus;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;

@Repository
public interface ConfirmationItemRepository extends JpaRepository<ConfirmationItem, Long> {

    List<ConfirmationItem> findByStatusOrderByCreatedAtDesc(ConfirmationStatus status);

    List<ConfirmationItem> findByRequestedByAndStatusOrderByCreatedAtDesc(
            Long requestedBy, ConfirmationStatus status);

    List<ConfirmationItem> findBySourceTypeAndStatusOrderByCreatedAtDesc(
            ConfirmationSourceType sourceType, ConfirmationStatus status);

    List<ConfirmationItem> findByReferenceId(String referenceId);

    List<ConfirmationItem> findByRequestedByOrderByCreatedAtDesc(Long requestedBy);
}
