package com.careconnect.service.ai.ask;

import com.careconnect.service.ai.indexing.SummarySourceKey;
import com.careconnect.service.ai.retrieval.RankedChunk;
import org.springframework.stereotype.Component;

/**
 * Builds citation destinations that are registered by the Flutter router.
 *
 * <p>Source-specific call, visit, file, and mail routes do not exist yet, so those
 * record types intentionally target their nearest supported feature page instead of
 * emitting a dead link. This registry should be updated alongside frontend route changes.
 */
@Component
final class CitationDeepLinkBuilder {

    String build(final RankedChunk chunk) {
        if (chunk == null || chunk.recordType() == null) {
            return null;
        }
        return switch (chunk.recordType()) {
            case TRANSCRIPT_SEGMENT, CALL_SUMMARY -> "/chatandcalls";
            case SUMMARY_ACTION_ITEM, SUMMARY_APPOINTMENT, SUMMARY_CARE_INSTRUCTION,
                    SUMMARY_CONDITION, SUMMARY_SOAP, SUMMARY_CLINICAL_OBSERVATION ->
                    SummarySourceKey.CALL_KIND.equals(chunk.sourceKind())
                            ? "/chatandcalls"
                            : null;
            case VISIT_SUMMARY -> null;
            case UPLOADED_DOCUMENT -> "/file-management";
            case CLINICAL_NOTE -> null;
            case USPS_MAIL -> "/informed-delivery";
            case MEDICATION -> "/medication";
            case TASK -> "/tasks";
            case EVV_RECORD -> "/evv/visit-history";
            case VITAL_SIGN -> "/wearables";
        };
    }

}
