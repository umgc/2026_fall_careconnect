package com.careconnect.service.confirmation;

import com.careconnect.dto.confirmation.ConfirmationDtos.ConfirmationItemResponse;
import com.careconnect.dto.confirmation.ConfirmationDtos.CreateConfirmationRequest;
import com.careconnect.model.confirmation.ConfirmationItem;
import com.careconnect.model.confirmation.ConfirmationSourceType;
import com.careconnect.model.confirmation.ConfirmationStatus;
import com.careconnect.repository.confirmation.ConfirmationItemRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.stream.Collectors;

@Slf4j
@Service @RequiredArgsConstructor
public class ConfirmationService {

    private final ConfirmationItemRepository repository;

    @Transactional
    public ConfirmationItem createItem(
            ConfirmationSourceType sourceType,
            String payload,
            String referenceId,
            Long requestedBy) {
        var item = ConfirmationItem.builder()
                .sourceType(sourceType)
                .payload(payload)
                .referenceId(referenceId)
                .requestedBy(requestedBy)
                .build();
        var saved = repository.save(item);
        log.info("Confirmation item created: id={}, sourceType={}, referenceId={}, requestedBy={}",
                saved.getId(), sourceType, referenceId, requestedBy);
        return saved;
    }

    @Transactional
    public ConfirmationItem createItem(CreateConfirmationRequest req) {
        return createItem(
                ConfirmationSourceType.valueOf(req.getSourceType()),
                req.getPayload(),
                req.getReferenceId(),
                req.getRequestedBy());
    }

    @Transactional
    public ConfirmationItem confirm(Long itemId, Long resolverUserId, String note) {
        var item = repository.findById(itemId)
                .orElseThrow(() -> new IllegalArgumentException("Confirmation item not found: " + itemId));
        if (item.getStatus() != ConfirmationStatus.PENDING) {
            throw new IllegalStateException("Item is not PENDING; current status: " + item.getStatus());
        }
        item.confirm(resolverUserId, note);
        var saved = repository.save(item);
        log.info("Confirmation item confirmed: id={}, resolvedBy={}", itemId, resolverUserId);
        return saved;
    }

    @Transactional
    public ConfirmationItem dismiss(Long itemId, Long resolverUserId, String note) {
        var item = repository.findById(itemId)
                .orElseThrow(() -> new IllegalArgumentException("Confirmation item not found: " + itemId));
        if (item.getStatus() != ConfirmationStatus.PENDING) {
            throw new IllegalStateException("Item is not PENDING; current status: " + item.getStatus());
        }
        item.dismiss(resolverUserId, note);
        var saved = repository.save(item);
        log.info("Confirmation item dismissed: id={}, resolvedBy={}", itemId, resolverUserId);
        return saved;
    }

    public List<ConfirmationItemResponse> getPendingItems() {
        return repository.findByStatusOrderByCreatedAtDesc(ConfirmationStatus.PENDING)
                .stream().map(this::toResponse).collect(Collectors.toList());
    }

    public List<ConfirmationItemResponse> getPendingItemsByUser(Long userId) {
        return repository.findByRequestedByAndStatusOrderByCreatedAtDesc(userId, ConfirmationStatus.PENDING)
                .stream().map(this::toResponse).collect(Collectors.toList());
    }

    public List<ConfirmationItemResponse> getPendingItemsBySourceType(ConfirmationSourceType type) {
        return repository.findBySourceTypeAndStatusOrderByCreatedAtDesc(type, ConfirmationStatus.PENDING)
                .stream().map(this::toResponse).collect(Collectors.toList());
    }

    public ConfirmationItemResponse getItem(Long id) {
        return repository.findById(id)
                .map(this::toResponse)
                .orElseThrow(() -> new IllegalArgumentException("Confirmation item not found: " + id));
    }

    public List<ConfirmationItemResponse> getItemsByUser(Long userId) {
        return repository.findByRequestedByOrderByCreatedAtDesc(userId)
                .stream().map(this::toResponse).collect(Collectors.toList());
    }

    private ConfirmationItemResponse toResponse(ConfirmationItem item) {
        return ConfirmationItemResponse.builder()
                .id(item.getId())
                .sourceType(item.getSourceType().name())
                .status(item.getStatus().name())
                .payload(item.getPayload())
                .referenceId(item.getReferenceId())
                .requestedBy(item.getRequestedBy())
                .resolvedBy(item.getResolvedBy())
                .resolvedAt(item.getResolvedAt())
                .resolutionNote(item.getResolutionNote())
                .createdAt(item.getCreatedAt())
                .updatedAt(item.getUpdatedAt())
                .build();
    }
}
