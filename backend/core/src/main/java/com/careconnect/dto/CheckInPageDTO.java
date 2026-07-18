package com.careconnect.dto;

import java.util.List;

public record CheckInPageDTO(
        List<CheckInSummaryDTO> items,
        int page,
        int size,
        long totalElements,
        int totalPages
) {
}
