package com.careconnect.util;

import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

class ContentHashUtilTest {

    @Test
    void sha256_usesPublisherCompatibleVersionedFormat() {
        assertThat(ContentHashUtil.sha256("careconnect"))
                .isEqualTo(
                        "sha256:ccedb0433c20263ce3bc83594e9e6cbf"
                                + "181392b90439cd4878e7bbe7731ddf29");
    }

    @Test
    void sha256_nullRemainsNull() {
        assertThat(ContentHashUtil.sha256(null)).isNull();
    }

    @Test
    void clinicalNoteContentHash_includesAiSummary() {
        final String bodyOnly = ContentHashUtil.sha256("note body\n");
        final String withSummary = ContentHashUtil.clinicalNoteContentHash("note body", "summary");
        assertThat(withSummary).isNotEqualTo(bodyOnly);
        assertThat(withSummary).isEqualTo(ContentHashUtil.sha256("note body\nsummary"));
    }

    @Test
    void clinicalNoteContentHash_nullPartsBecomeEmpty() {
        assertThat(ContentHashUtil.clinicalNoteContentHash(null, null))
                .isEqualTo(ContentHashUtil.sha256("\n"));
    }
}
