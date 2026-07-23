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
}
