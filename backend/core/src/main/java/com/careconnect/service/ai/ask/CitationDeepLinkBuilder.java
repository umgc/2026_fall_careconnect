package com.careconnect.service.ai.ask;

import com.careconnect.service.ai.retrieval.RankedChunk;
import org.springframework.stereotype.Component;

/**
 * Builds citation destinations that are registered by the Flutter router.
 *
 * <p>Only source-specific routes belong in citation responses. Generic feature-page
 * routes are intentionally omitted until the Flutter router can open the cited record.
 */
@Component
final class CitationDeepLinkBuilder {

    String build(final RankedChunk chunk) {
        if (chunk == null || chunk.recordType() == null) {
            return null;
        }
        return null;
    }

}
