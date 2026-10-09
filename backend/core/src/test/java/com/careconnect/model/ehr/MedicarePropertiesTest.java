package com.careconnect.model.ehr;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

import static org.assertj.core.api.Assertions.assertThat;

/** The envelope's {@code synthetic} flag, which drives the app's synthetic-data banner. */
class MedicarePropertiesTest {

    private static MedicareProperties properties(final String mode, final boolean sandbox) {
        final MedicareProperties p = new MedicareProperties();
        ReflectionTestUtils.setField(p, "mode", mode);
        ReflectionTestUtils.setField(p, "sandbox", sandbox);
        return p;
    }

    @Test
    @DisplayName("TC-MCR-CACHE-017: live data from the CMS sandbox is synthetic: its beneficiaries are not real people")
    void sandboxIsSynthetic() {
        assertThat(properties("live", true).isSynthetic()).isTrue();
    }

    @Test
    @DisplayName("TC-MCR-CACHE-018: fixture (mock) data is synthetic whatever the sandbox setting")
    void mockIsSynthetic() {
        assertThat(properties("mock", false).isSynthetic()).isTrue();
    }

    @Test
    @DisplayName("TC-MCR-CACHE-019: only live production data is real")
    void liveProductionIsReal() {
        assertThat(properties("live", false).isSynthetic()).isFalse();
    }
}
