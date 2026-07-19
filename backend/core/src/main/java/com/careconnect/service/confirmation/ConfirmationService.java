package com.careconnect.service.confirmation;

import com.careconnect.dto.confirmation.ConfirmationDtos.ConfirmationItemResponse;
import com.careconnect.dto.confirmation.ConfirmationDtos.CreateConfirmationRequest;
import com.careconnect.exception.AppException;
import com.careconnect.model.confirmation.ConfirmationItem;
import com.careconnect.model.confirmation.ConfirmationSourceType;
import com.careconnect.model.confirmation.ConfirmationStatus;
import com.careconnect.model.safety.AuditSourceFeature;
import com.careconnect.repository.confirmation.ConfirmationItemRepository;
import com.careconnect.service.safety.AiAuditLedgerService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.dao.OptimisticLockingFailureException;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.Collection;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

@Slf4j
@Service @RequiredArgsConstructor
public class ConfirmationService {

    private final ConfirmationItemRepository repository;
    private final AiAuditLedgerService auditLedgerService;

    @Transactional
    public ConfirmationItem createItem(
            ConfirmationSourceType sourceType,
            String payload,
            String referenceId,
            Long requestedBy) {
        return createItem(sourceType, payload, referenceId, requestedBy, null);
    }

    @Transactional
    public ConfirmationItem createItem(
            ConfirmationSourceType sourceType,
            String payload,
            String referenceId,
            Long requestedBy,
            Long patientId) {
        var item = ConfirmationItem.builder()
                .sourceType(sourceType)
                .payload(payload)
                .referenceId(referenceId)
                .requestedBy(requestedBy)
                .patientId(patientId)
                .build();
        var saved = repository.save(item);
        log.info("Confirmation item created: id={}, sourceType={}, referenceId={}, requestedBy={}, patientId={}",
                saved.getId(), sourceType, referenceId, requestedBy, patientId);
        return saved;
    }

    /**
     * Record a human confirm/dismiss decision in the audit ledger. Best-effort: a ledger
     * failure is swallowed by the ledger service and never blocks the resolution.
     */
    private void auditResolution(ConfirmationItem item, Long resolverUserId,
                                 ConfirmationStatus resolution, String note) {
        AuditSourceFeature source;
        try {
            source = AuditSourceFeature.valueOf(item.getSourceType().name());
        } catch (IllegalArgumentException e) {
            source = AuditSourceFeature.CONFIRMATION_SERVICE;
        }
        auditLedgerService.logConfirmation(source, resolverUserId, null, item.getReferenceId(),
                Map.of("itemId", item.getId(),
                       "resolution", resolution.name(),
                       "note", note == null ? "" : note));
    }

    @Transactional
    public ConfirmationItem createItem(CreateConfirmationRequest req) {
        return createItem(
                parseSourceType(req.getSourceType()),
                req.getPayload(),
                req.getReferenceId(),
                req.getRequestedBy(),
                req.getPatientId());
    }

    public static ConfirmationSourceType parseSourceType(String raw) {
        try {
            return ConfirmationSourceType.valueOf(raw);
        } catch (IllegalArgumentException ex) {
            throw new AppException(HttpStatus.BAD_REQUEST, "Unknown sourceType: " + raw);
        }
    }

    @Transactional
    public ConfirmationItem confirm(Long itemId, Long resolverUserId, String note) {
        var item = repository.findById(itemId)
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Confirmation item not found: " + itemId));
        if (item.getStatus() != ConfirmationStatus.PENDING) {
            throw new AppException(HttpStatus.BAD_REQUEST, "Item is not PENDING; current status: " + item.getStatus());
        }
        item.confirm(resolverUserId, note);
        try {
            var saved = repository.save(item);
            repository.flush();
            auditResolution(saved, resolverUserId, ConfirmationStatus.CONFIRMED, note);
            log.info("Confirmation item confirmed: id={}, resolvedBy={}", itemId, resolverUserId);
            return saved;
        } catch (OptimisticLockingFailureException ex) {
            throw new AppException(HttpStatus.CONFLICT,
                    "Confirmation item was concurrently modified: " + itemId);
        }
    }

    @Transactional
    public ConfirmationItem dismiss(Long itemId, Long resolverUserId, String note) {
        var item = repository.findById(itemId)
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Confirmation item not found: " + itemId));
        if (item.getStatus() != ConfirmationStatus.PENDING) {
            throw new AppException(HttpStatus.BAD_REQUEST, "Item is not PENDING; current status: " + item.getStatus());
        }
        item.dismiss(resolverUserId, note);
        try {
            var saved = repository.save(item);
            repository.flush();
            auditResolution(saved, resolverUserId, ConfirmationStatus.DISMISSED, note);
            log.info("Confirmation item dismissed: id={}, resolvedBy={}", itemId, resolverUserId);
            return saved;
        } catch (OptimisticLockingFailureException ex) {
            throw new AppException(HttpStatus.CONFLICT,
                    "Confirmation item was concurrently modified: " + itemId);
        }
    }

    public List<ConfirmationItemResponse> getPendingItems() {
        return repository.findByStatusOrderByCreatedAtDesc(ConfirmationStatus.PENDING)
                .stream().map(this::toResponse).collect(Collectors.toList());
    }

    public List<ConfirmationItemResponse> getPendingItemsByUser(Long userId) {
        return repository.findByRequestedByAndStatusOrderByCreatedAtDesc(userId, ConfirmationStatus.PENDING)
                .stream().map(this::toResponse).collect(Collectors.toList());
    }

    public List<ConfirmationItemResponse> getPendingItemsForPatients(Collection<Long> patientIds) {
        if (patientIds == null || patientIds.isEmpty()) {
            return List.of();
        }
        return repository.findByStatusAndPatientIdInOrderByCreatedAtDesc(ConfirmationStatus.PENDING, patientIds)
                .stream().map(this::toResponse).collect(Collectors.toList());
    }

    public List<ConfirmationItemResponse> getPendingItemsBySourceType(ConfirmationSourceType type) {
        return repository.findBySourceTypeAndStatusOrderByCreatedAtDesc(type, ConfirmationStatus.PENDING)
                .stream().map(this::toResponse).collect(Collectors.toList());
    }

    public ConfirmationItemResponse getItem(Long id) {
        return repository.findById(id)
                .map(this::toResponse)
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Confirmation item not found: " + id));
    }

    public List<ConfirmationItemResponse> getItemsByUser(Long userId) {
        return repository.findByRequestedByOrderByCreatedAtDesc(userId)
                .stream().map(this::toResponse).collect(Collectors.toList());
    }

    public ConfirmationItemResponse toResponse(ConfirmationItem item) {
        return ConfirmationItemResponse.builder()
                .id(item.getId())
                .sourceType(item.getSourceType().name())
                .status(item.getStatus().name())
                .payload(item.getPayload())
                .referenceId(item.getReferenceId())
                .requestedBy(item.getRequestedBy())
                .patientId(item.getPatientId())
                .resolvedBy(item.getResolvedBy())
                .resolvedAt(item.getResolvedAt())
                .resolutionNote(item.getResolutionNote())
                .createdAt(item.getCreatedAt())
                .updatedAt(item.getUpdatedAt())
                .build();
    }
}
