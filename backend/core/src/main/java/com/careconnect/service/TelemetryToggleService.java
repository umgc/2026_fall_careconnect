package com.careconnect.service;

import java.util.concurrent.atomic.AtomicBoolean;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

/**
 * Service that manages whether telemetry collection is currently enabled.
 */
@Service
public final class TelemetryToggleService {

    /**
     * Tracks whether telemetry capture is currently enabled.
     */
    private final AtomicBoolean enabled;

    /**
     * Creates a new telemetry toggle service.
     *
     * @param defaultEnabled initial telemetry enabled state
     */
    public TelemetryToggleService(@Value("${telemetry.enabled:true}") final boolean defaultEnabled) {
        this.enabled = new AtomicBoolean(defaultEnabled);
    }

    /**
     * Returns whether telemetry capture is currently enabled.
     *
     * @return {@code true} when telemetry capture is enabled
     */
    public boolean isEnabled() {
        return enabled.get();
    }

    /**
     * Updates telemetry capture state.
     *
     * @param value new telemetry enabled state
     * @return stored telemetry enabled state
     */
    public boolean setEnabled(final boolean value) {
        enabled.set(value);
        return enabled.get();
    }
}
