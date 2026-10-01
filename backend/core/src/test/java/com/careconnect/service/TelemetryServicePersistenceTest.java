package com.careconnect.service;

import com.careconnect.model.TelemetryEvent;
import com.careconnect.repository.TelemetryEventRepository;
import java.util.Map;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.context.annotation.Import;
import org.springframework.test.context.ActiveProfiles;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;

/** Persistence-boundary integration tests for telemetry collection and its global toggle. */
@DataJpaTest
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@ActiveProfiles("test")
@Import({TelemetryService.class, TelemetryToggleService.class})
class TelemetryServicePersistenceTest {

    @Autowired
    private TelemetryService telemetryService;

    @Autowired
    private TelemetryToggleService toggleService;

    @Autowired
    private TelemetryEventRepository repository;

    @BeforeEach
    void setUp() {
        repository.deleteAll();
        toggleService.setEnabled(true);
    }

    /**
     * Builds an event TelemetryService will actually persist: an allowlisted
     * event name, at least one allowlisted detail key, and at least one
     * allowlisted deviceInfo key. Anything short of this makes record() return
     * null before it reaches the repository.
     *
     * @return a minimal event that survives the allowlist
     */
    private static TelemetryEvent allowlistedEvent() {
        final TelemetryEvent event = new TelemetryEvent();
        event.setEventName("screen_view");
        event.setDetails(Map.of("screen", "home"));
        event.setDeviceInfo(Map.of("platform", "android"));
        return event;
    }

    /**
     * TC-TEL-ING-006 — enabled telemetry persists exactly one event.
     *
     * <p>Amended 2026-09-09: the fixture was "synthetic_persistence_probe" with
     * no details or deviceInfo. That predates the TelemetryService allowlist,
     * which merged into team-e-develop with PR #63 (b680e45a) and now returns
     * null for a non-allowlisted name, so the original fixture stopped
     * reaching the save path. Assertion and intent are unchanged.
     */
    @Test
    void enabledTelemetryPersistsExactlyOneEvent() {
        final TelemetryEvent event = allowlistedEvent();

        final TelemetryEvent saved = telemetryService.record(event);

        assertThat(saved).isNotNull();
        assertThat(saved.getId()).isNotNull();
        assertThat(repository.count()).isEqualTo(1);
        assertThat(repository.findAll())
                .extracting(TelemetryEvent::getEventName)
                .containsExactly("screen_view");
    }

    /** TC-TEL-ING-007 — negative: disabled telemetry persists nothing. */
    @Test
    void disabledTelemetryPersistsNothing() {
        toggleService.setEnabled(false);
        final TelemetryEvent event = new TelemetryEvent();
        event.setEventName("synthetic_disabled_probe");

        final TelemetryEvent returned = telemetryService.record(event);

        assertThat(returned).isSameAs(event);
        assertThat(returned.getId()).isNull();
        assertThat(repository.count()).isZero();
    }

    /**
     * TC-TEL-ING-015 — boundary, regression cover for DEF-TEL-11.
     *
     * <p>The invariant: a value TelemetryController accepts must be
     * persistable. Each parameter below sits exactly on its column width —
     * session_id VARCHAR(64), trace_id VARCHAR(64), span_id VARCHAR(32) — which
     * is the largest value the controller now passes through, so persistence
     * must not reject it.
     *
     * <p>Amended 2026-09-09, three changes.
     *
     * <p>One. The eventName parameter is withdrawn. The TelemetryService
     * allowlist (merged with PR #63, b680e45a) rejects any name outside a fixed
     * list, all of which are under 40 characters, so event_name can no longer
     * be overflowed from the wire.
     *
     * <p>Two. The fixture now carries an allowlisted event name, details and
     * deviceInfo. Without them record() returns null before repository.save and
     * this case passed vacuously — nothing was inserted, so "no exception
     * thrown" proved nothing.
     *
     * <p>Three. The parameters moved from one character past each column width
     * to exactly on it. While DEF-TEL-11 was open the controller accepted
     * 65/65/33 and this case was the expected-fail that proved persistence
     * would not take them. With the per-field caps in place the controller
     * rejects those before the service is called, so the over-width form no
     * longer describes anything reachable; the at-width form pins the new
     * boundary and fails again if a cap is raised above its column.
     *
     * <p>Harness note: the test profile runs H2 with
     * spring.jpa.hibernate.ddl-auto=create-drop and spring.flyway.enabled=false
     * (application-test.properties:10,17), so the widths exercised here are the
     * ones declared on the TelemetryEvent entity. They match the Flyway DDL
     * today; this case proves the entity-declared width, not the deployed one.
     */
    @ParameterizedTest(name = "TC-TEL-ING-015 [{index}] {0} at {1} chars")
    @CsvSource({
        "sessionId, 64",
        "traceId, 64",
        "spanId, 32"
    })
    void controllerAcceptedValuesMustBePersistable(final String field, final int length) {
        final String atColumnWidth = "x".repeat(length);
        final TelemetryEvent event = allowlistedEvent();

        switch (field) {
            case "sessionId" -> event.setSessionId(atColumnWidth);
            case "traceId" -> event.setTraceId(atColumnWidth);
            case "spanId" -> event.setSpanId(atColumnWidth);
            default -> throw new IllegalArgumentException("unknown field " + field);
        }

        assertThatCode(() -> telemetryService.record(event))
                .as("DEF-TEL-11: TelemetryController accepts %s at %d chars, "
                        + "so persistence must accept it too", field, length)
                .doesNotThrowAnyException();
    }

    /**
     * TC-TEL-ING-016 — privacy, regression cover for DEF-TEL-10.
     *
     * <p>SecurityConfig justifies leaving POST /v1/api/dev/telemetry
     * unauthenticated on the grounds that "TelemetryService rejects any event
     * outside its allowlist and strips non-allowlisted detail keys". When this
     * case was written that allowlist did not exist on the branch and the case
     * was an expected-fail proving DEF-TEL-10.
     *
     * <p>Amended 2026-09-09: PR #63 merged into team-e-develop (b680e45a) and
     * TelemetryService.record now filters details against allowedDetails. The
     * fixture gained the deviceInfo map that record() requires. DEF-TEL-10 is
     * closed; this case is retained as regression cover and fails again if the
     * strip is removed while SecurityConfig still cites it.
     */
    @Test
    void piiShapedDetailKeysAreStrippedBeforePersistence() {
        final TelemetryEvent event = allowlistedEvent();
        event.setDetails(Map.of("screen", "home", "email", "synthetic@test.invalid"));

        telemetryService.record(event);

        assertThat(repository.findAll())
                .singleElement()
                .satisfies(stored -> assertThat(stored.getDetails())
                        .as("DEF-TEL-10: SecurityConfig claims TelemetryService strips "
                                + "non-allowlisted detail keys; no allowlist exists here")
                        .doesNotContainKey("email")
                        .containsKey("screen"));
    }
}
