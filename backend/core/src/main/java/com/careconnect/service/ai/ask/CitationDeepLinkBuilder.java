package com.careconnect.service.ai.ask;

import com.careconnect.service.ai.retrieval.RankedChunk;
import org.springframework.stereotype.Component;

import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;

/**
 * Builds citation destinations that are registered by the Flutter router.
 *
 * <p>Source-specific call, visit, file, and mail routes do not exist yet, so those
 * record types intentionally target their nearest supported feature page instead of
 * emitting a dead link. This registry should be updated alongside frontend route changes.
 */
@Component
final class CitationDeepLinkBuilder {

    String build(final RankedChunk chunk, final String sourceId) {
        if (chunk == null || chunk.recordType() == null) {
            return null;
        }
        return switch (chunk.recordType()) {
            case TRANSCRIPT_SEGMENT, CALL_SUMMARY, SUMMARY_ACTION_ITEM,
                    SUMMARY_APPOINTMENT, SUMMARY_CARE_INSTRUCTION, SUMMARY_CONDITION,
                    SUMMARY_SOAP, SUMMARY_CLINICAL_OBSERVATION -> "/chatandcalls";
            case VISIT_SUMMARY -> null;
            case UPLOADED_DOCUMENT -> "/file-management";
            case CLINICAL_NOTE -> "/notetaker/detail/" + encodePathSegment(sourceId);
            case USPS_MAIL -> "/informed-delivery";
            case MEDICATION -> "/medication";
            case TASK -> "/tasks";
            case EVV_RECORD -> "/evv/visit-history";
            case VITAL_SIGN -> "/wearables";
        };
    }

    private static String encodePathSegment(final String value) {
        return URLEncoder.encode(value, StandardCharsets.UTF_8).replace("+", "%20");
    }
}
