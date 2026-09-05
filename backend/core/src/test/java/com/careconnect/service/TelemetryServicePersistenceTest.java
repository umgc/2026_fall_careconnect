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

    /** TC-TEL-ING-006 — enabled telemetry persists exactly one event. */
    @Test
    void enabledTelemetryPersistsExactlyOneEvent() {
        final TelemetryEvent event = new TelemetryEvent();
        event.setEventName("synthetic_persistence_probe");

        final TelemetryEvent saved = telemetryService.record(event);

        assertThat(saved.getId()).isNotNull();
        assertThat(repository.count()).isEqualTo(1);
        assertThat(repository.findAll())
                .extracting(TelemetryEvent::getEventName)
                .containsExactly("synthetic_persistence_probe");
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
     * TC-TEL-ING-015 — negative, EXPECTED-FAIL, proves DEF-TEL-11.
     *
     * <p>TelemetryController accepts any stringified value up to
     * MAX_VALUE_LENGTH = 256 characters, but every string column on
     * telemetry_events is narrower than that: event_name VARCHAR(128),
     * session_id VARCHAR(64), trace_id VARCHAR(64), span_id VARCHAR(32).
     * A value the controller accepts must therefore be persistable. Each
     * parameter below sits one character past its column width and is
     * accepted by the controller, so persistence must not reject it.
     *
     * <p>Harness note: the test profile runs H2 with
     * spring.jpa.hibernate.ddl-auto=create-drop and spring.flyway.enabled=false
     * (application-test.properties:10,17), so the widths exercised here are the
     * ones declared on the TelemetryEvent entity. They match the Flyway DDL
     * today; this case proves the entity-declared width, not the deployed one.
     *
     * <p>Must go green when DEF-TEL-11 is fixed. Not a characterization test.
     */
    @ParameterizedTest(name = "TC-TEL-ING-015 [{index}] {0} at {1} chars")
    @CsvSource({
        "eventName, 129",
        "sessionId, 65",
        "traceId, 65",
        "spanId, 33"
    })
    void controllerAcceptedValuesMustBePersistable(final String field, final int length) {
        final String oversized = "x".repeat(length);
        final TelemetryEvent event = new TelemetryEvent();
        event.setEventName("synthetic_width_probe");

        switch (field) {
            case "eventName" -> event.setEventName(oversized);
            case "sessionId" -> event.setSessionId(oversized);
            case "traceId" -> event.setTraceId(oversized);
            case "spanId" -> event.setSpanId(oversized);
            default -> throw new IllegalArgumentException("unknown field " + field);
        }

        assertThatCode(() -> telemetryService.record(event))
                .as("DEF-TEL-11: TelemetryController accepts %s at %d chars "
                        + "(MAX_VALUE_LENGTH = 256), so persistence must accept it too",
                        field, length)
                .doesNotThrowAnyException();
    }

    /**
     * TC-TEL-ING-016 — privacy, EXPECTED-FAIL, proves DEF-TEL-10.
     *
     * <p>SecurityConfig justifies leaving POST /v1/api/dev/telemetry
     * unauthenticated on the grounds that "TelemetryService rejects any event
     * outside its allowlist and strips non-allowlisted detail keys". No such
     * allowlist exists on this branch: TelemetryService.record saves whatever
     * it is handed. This case asserts the documented behaviour and currently
     * fails, which is the proof that the stated compensating control is absent.
     *
     * <p>Must go green when DEF-TEL-10 is fixed. Not a characterization test.
     */
    @Test
    void piiShapedDetailKeysAreStrippedBeforePersistence() {
        final TelemetryEvent event = new TelemetryEvent();
        event.setEventName("screen_view");
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
