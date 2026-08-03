package com.careconnect.service.visibility;

import com.careconnect.dto.visibility.VisibilityDtos.VisibilityResponse;
import com.careconnect.exception.AppException;
import com.careconnect.model.confirmation.ConfirmationSourceType;
import com.careconnect.model.safety.AuditEventType;
import com.careconnect.model.safety.AuditSourceFeature;
import com.careconnect.model.User;
import com.careconnect.model.visibility.CaregiverSummaryVisibility;
import com.careconnect.model.visibility.VisibilityStatus;
import com.careconnect.repository.CaregiverPatientLinkRepository;
import com.careconnect.repository.UserRepository;
import com.careconnect.repository.visibility.CaregiverSummaryVisibilityRepository;
import com.careconnect.service.confirmation.ConfirmationService;
import com.careconnect.service.safety.AiAuditLedgerService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.dao.OptimisticLockingFailureException;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.Map;

/**
 * WBS 3.15.5: defaults to denial + grant + revoke + pre-share review gate
 *
 * {@link #canViewSummaries} is true only when a GRANTED row exists
 * State transitions go through {@link #submitForReview} then {@link #grant} or {@link #revoke}
 * Every transition writes a CAREGIVER_VISIBILITY event to the audit ledger
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class CaregiverVisibilityService {

    private final CaregiverSummaryVisibilityRepository repository;
    private final ConfirmationService confirmationService;
    private final AiAuditLedgerService auditLedgerService;
    private final UserRepository userRepository;
    private final CaregiverPatientLinkRepository caregiverPatientLinkRepository;

    /** Default-deny check used at summary-retrieval time. */
    @Transactional(readOnly = true)
    public boolean canViewSummaries(Long caregiverUserId, Long patientUserId) {
        return repository.existsByCaregiverUserIdAndPatientUserIdAndStatus(
                caregiverUserId, patientUserId, VisibilityStatus.GRANTED);
    }

    /**
     * Open the pre-share review gate: record the request as PENDING_REVIEW and queue a
     * confirmation item for a reviewer to approve before any summary is shared.
     */
    @Transactional
    public VisibilityResponse submitForReview(Long caregiverUserId, Long patientUserId, Long requestedBy) {
        requireCaregiverPatientLink(caregiverUserId, patientUserId);
        CaregiverSummaryVisibility record = repository
                .findByCaregiverUserIdAndPatientUserId(caregiverUserId, patientUserId)
                .orElseGet(() -> CaregiverSummaryVisibility.builder()
                        .caregiverUserId(caregiverUserId)
                        .patientUserId(patientUserId)
                        .build());
        record.setStatus(VisibilityStatus.PENDING_REVIEW);
        record.setRequestedBy(requestedBy);
        record.setReviewedBy(null);
        record.setReviewedAt(null);
        CaregiverSummaryVisibility saved = saveVisibility(record);

        confirmationService.createItem(
                ConfirmationSourceType.CAREGIVER_VISIBILITY,
                "Review caregiver access to patient summaries: caregiver=" + caregiverUserId
                        + ", patient=" + patientUserId,
                referenceId(caregiverUserId, patientUserId),
                requestedBy,
                patientUserId);

        audit(AuditEventType.CONFIRMATION, requestedBy, patientUserId,
                "PENDING_REVIEW", caregiverUserId);
        return toResponse(saved);
    }

    /** Approve the review gate: caregiver may now view the patient's summaries. */
    @Transactional
    public VisibilityResponse grant(Long caregiverUserId, Long patientUserId, Long reviewerUserId) {
        CaregiverSummaryVisibility record = repository
                .findByCaregiverUserIdAndPatientUserId(caregiverUserId, patientUserId)
                .orElseThrow(() -> new AppException(HttpStatus.BAD_REQUEST,
                        "No pending review to grant; submit for review first"));
        if (record.getStatus() != VisibilityStatus.PENDING_REVIEW) {
            throw new AppException(HttpStatus.BAD_REQUEST,
                    "Visibility is not pending review; current status: " + record.getStatus());
        }
        return toResponse(applyGrant(record, reviewerUserId));
    }

    /**
     * Approve a queued review from the confirmation flow. Tolerant by design: if the
     * record is no longer PENDING_REVIEW (already granted, revoked, or gone), this is a
     * no-op so a stale confirmation cannot roll back the reviewer's decision or wedge
     * the confirmation item in PENDING forever.
     */
    @Transactional
    public void approveFromReview(Long caregiverUserId, Long patientUserId, Long reviewerUserId) {
        CaregiverSummaryVisibility record = repository
                .findByCaregiverUserIdAndPatientUserId(caregiverUserId, patientUserId)
                .orElse(null);
        if (record == null || record.getStatus() != VisibilityStatus.PENDING_REVIEW) {
            log.info("Visibility review approval skipped; not pending for caregiver={} patient={}",
                    caregiverUserId, patientUserId);
            return;
        }
        applyGrant(record, reviewerUserId);
    }

    private CaregiverSummaryVisibility applyGrant(CaregiverSummaryVisibility record, Long reviewerUserId) {
        record.setStatus(VisibilityStatus.GRANTED);
        record.setReviewedBy(reviewerUserId);
        record.setReviewedAt(LocalDateTime.now());
        CaregiverSummaryVisibility saved = saveVisibility(record);
        audit(AuditEventType.CONFIRMATION, reviewerUserId, record.getPatientUserId(),
                "GRANTED", record.getCaregiverUserId());
        return saved;
    }

    /** Revoke access. Idempotent-ish: allowed from any current status. */
    @Transactional
    public VisibilityResponse revoke(Long caregiverUserId, Long patientUserId, Long reviewerUserId) {
        CaregiverSummaryVisibility saved = transition(
                caregiverUserId, patientUserId, reviewerUserId, VisibilityStatus.REVOKED);
        audit(AuditEventType.CONFIRMATION, reviewerUserId, patientUserId, "REVOKED", caregiverUserId);
        return toResponse(saved);
    }

    @Transactional(readOnly = true)
    public VisibilityResponse getStatus(Long caregiverUserId, Long patientUserId) {
        return repository.findByCaregiverUserIdAndPatientUserId(caregiverUserId, patientUserId)
                .map(this::toResponse)
                .orElseGet(() -> VisibilityResponse.builder()
                        .caregiverUserId(caregiverUserId)
                        .patientUserId(patientUserId)
                        .status("NONE")
                        .canViewSummaries(false)
                        .build());
    }

    private CaregiverSummaryVisibility transition(Long caregiverUserId, Long patientUserId,
                                                  Long reviewerUserId, VisibilityStatus target) {
        CaregiverSummaryVisibility record = repository
                .findByCaregiverUserIdAndPatientUserId(caregiverUserId, patientUserId)
                .orElseGet(() -> CaregiverSummaryVisibility.builder()
                        .caregiverUserId(caregiverUserId)
                        .patientUserId(patientUserId)
                        .requestedBy(reviewerUserId)
                        .build());
        record.setStatus(target);
        record.setReviewedBy(reviewerUserId);
        record.setReviewedAt(LocalDateTime.now());
        return saveVisibility(record);
    }

    /**
     * Persists a visibility row, translating a concurrent first-insert collision
     * on the unique (caregiver, patient) pair into a clean 409 instead of a 500.
     */
    private CaregiverSummaryVisibility saveVisibility(CaregiverSummaryVisibility record) {
        try {
            return repository.save(record);
        } catch (DataIntegrityViolationException | OptimisticLockingFailureException race) {
            throw new AppException(HttpStatus.CONFLICT,
                    "Visibility was concurrently modified; please retry");
        }
    }

    /** A pre-share review may only be opened for an existing active caregiver-patient link. */
    private void requireCaregiverPatientLink(Long caregiverUserId, Long patientUserId) {
        User caregiver = userRepository.findById(caregiverUserId)
                .orElseThrow(() -> new AppException(HttpStatus.BAD_REQUEST,
                        "Unknown caregiver: " + caregiverUserId));
        User patient = userRepository.findById(patientUserId)
                .orElseThrow(() -> new AppException(HttpStatus.BAD_REQUEST,
                        "Unknown patient: " + patientUserId));
        boolean linked = caregiverPatientLinkRepository.existsActiveNonExpiredLink(
                caregiver, patient, LocalDateTime.now());
        if (!linked) {
            throw new AppException(HttpStatus.BAD_REQUEST,
                    "No active caregiver relationship with this patient");
        }
    }

    private static final String REFERENCE_PREFIX = "visibility";

    private String referenceId(Long caregiverUserId, Long patientUserId) {
        return REFERENCE_PREFIX + ":" + caregiverUserId + ":" + patientUserId;
    }

    /**
     * Parses a confirmation referenceId of the form
     * {@code visibility:{caregiverUserId}:{patientUserId}} into
     * {@code [caregiverUserId, patientUserId]}, or null when it does not match.
     * Co-located with {@link #referenceId} so the encoding lives in one place.
     */
    public static Long[] parseVisibilityReference(String referenceId) {
        if (referenceId == null) {
            return null;
        }
        String[] parts = referenceId.split(":");
        if (parts.length != 3 || !REFERENCE_PREFIX.equals(parts[0])) {
            return null;
        }
        try {
            return new Long[] { Long.parseLong(parts[1]), Long.parseLong(parts[2]) };
        } catch (NumberFormatException ex) {
            return null;
        }
    }

    private void audit(AuditEventType eventType, Long actorUserId, Long patientId,
                       String newStatus, Long caregiverUserId) {
        try {
            auditLedgerService.log(eventType, AuditSourceFeature.CAREGIVER_VISIBILITY,
                    actorUserId, patientId, null,
                    Map.of("status", newStatus, "caregiverUserId", caregiverUserId));
        } catch (Exception e) {
            log.warn("Could not audit caregiver visibility change: {}", e.getMessage());
        }
    }

    private VisibilityResponse toResponse(CaregiverSummaryVisibility r) {
        return VisibilityResponse.builder()
                .id(r.getId())
                .caregiverUserId(r.getCaregiverUserId())
                .patientUserId(r.getPatientUserId())
                .status(r.getStatus().name())
                .canViewSummaries(r.isGranted())
                .requestedBy(r.getRequestedBy())
                .reviewedBy(r.getReviewedBy())
                .reviewedAt(r.getReviewedAt())
                .updatedAt(r.getUpdatedAt())
                .build();
    }
}
