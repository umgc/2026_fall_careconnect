package com.careconnect.service;

import com.careconnect.model.TelemetryEvent;
import com.careconnect.repository.TelemetryEventRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.context.annotation.Import;
import org.springframework.test.context.ActiveProfiles;

import static org.assertj.core.api.Assertions.assertThat;

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
}
