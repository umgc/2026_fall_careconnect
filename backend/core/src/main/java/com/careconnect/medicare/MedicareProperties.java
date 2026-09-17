package com.careconnect.medicare;

import java.util.Locale;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

/**
 * Medicare (Blue Button 2.0) configuration, WBS 1.4.1-1.4.2 / issue #132.
 *
 * <p>Mirrors the {@code careconnect.epic.*} block Team Delta uses, including its default:
 * <b>off</b>. Mock mode serves fabricated clinical and claims data, which must never reach a
 * real patient context, so enabling it is an explicit per-environment decision rather than
 * something that happens by omission. It is switched on in the dev and test profiles only.
 */
@Component
public class MedicareProperties {

    /** Discriminator stored on records and audit rows for this source. */
    public static final String SOURCE_MEDICARE = "MEDICARE";

    /** Fixture-backed mode: no network, no credentials, synthetic data. */
    public static final String MODE_MOCK = "mock";

    /** Live CMS sandbox/production retrieval. Not implemented on this branch. */
    public static final String MODE_LIVE = "live";

    @Value("${careconnect.medicare.enabled:false}")
    private boolean enabled;

    @Value("${careconnect.medicare.mode:mock}")
    private String mode;

    public boolean isEnabled() {
        return enabled;
    }

    public String getMode() {
        return mode == null ? MODE_MOCK : mode.toLowerCase(Locale.ROOT);
    }

    /** True when responses are fixture-backed and must be labelled synthetic to callers. */
    public boolean isMock() {
        return MODE_MOCK.equals(getMode());
    }
}
