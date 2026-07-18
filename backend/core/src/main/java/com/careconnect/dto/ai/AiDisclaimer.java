package com.careconnect.dto.ai;

/**
 * Mandatory records-based disclaimer (FR-AI-3 / REQ-SC-1).
 */
public record AiDisclaimer(
        String text,
        boolean aiNoticeRequired,
        boolean recordsBasedFraming,
        String locale
) {
}
