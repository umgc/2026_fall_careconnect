package com.careconnect.dto.ai;

import java.util.List;

/**
 * Structured error payload when {@code deliveryStatus=WITHHELD}.
 */
public record AiErrorBlock(
        String code,
        String message,
        List<String> details
) {
}
