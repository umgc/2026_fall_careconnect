package com.careconnect.service;

import com.careconnect.model.TelemetryEvent;
import com.careconnect.repository.TelemetryEventRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

/**
 * Unit tests for {@link TelemetryService}, covering the server-side telemetry allowlist
 * introduced by PR #63 (WBS 1.5.2, branch {@code feature/e-telemetry-verification}).
 *
 * <p>Test IDs TC-TEL-01 .. TC-TEL-25 are permanent. Never renumber, never reuse.
 *
 * <p>Cases tagged EXPECTED-FAIL assert the <em>intended</em> behaviour of the feature and are
 * expected to fail against the implementation as submitted in PR #63. Each names the defect it
 * proves. They are not characterization tests; they must go green once the defect is fixed.
 *
 * <p>TC-TEL-22 .. TC-TEL-25 were added 2026-08-29 after commit {@code 6f38c103}. That commit closed
 * DEF-TEL-01, DEF-TEL-02, DEF-TEL-06 and DEF-TEL-09, and introduced DEF-TEL-18, DEF-TEL-19 and
 * DEF-TEL-20 in their place. TC-TEL-16 and TC-TEL-17 now pass and are retained as regression cover.
 *
 * <p>Executed by: Kristopher Bickmore (Testing Lead). PR author: MaximumVolts. Separation of duties per
 * CLAUDE.md is satisfied - the author is not the executor.
 */
@ExtendWith(MockitoExtension.class)
@DisplayName("TelemetryService - server-side telemetry allowlist (PR #63)")
class TelemetryServiceTest {

    @Mock
    private TelemetryEventRepository repository;

    /** Real toggle rather than a mock: the class is final and has no collaborators. */
    private TelemetryToggleService toggle;

    private TelemetryService service;

    /** Event name drawn from the allowlist, used wherever the name itself is not under test. */
    private static final String ALLOWED_EVENT = "screen_view";

    @BeforeEach
    void setUp() {
        toggle = new TelemetryToggleService(true);
        service = new TelemetryService(repository, toggle);
    }

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------

    private static TelemetryEvent event(final String name,
                                        final Map<String, Object> details,
                                        final Map<String, Object> deviceInfo) {
        final TelemetryEvent e = new TelemetryEvent();
        e.setEventName(name);
        if (details != null) {
            e.setDetails(details);
        }
        if (deviceInfo != null) {
            e.setDeviceInfo(deviceInfo);
        }
        return e;
    }

    /** A deviceInfo map matching exactly what the Flutter client sends (telemetry.dart:159-164). */
    private static Map<String, Object> validDeviceInfo() {
        final Map<String, Object> m = new LinkedHashMap<>();
        m.put("uiSurface", "web");
        m.put("platform", "android");
        m.put("isWeb", true);
        m.put("debug", false);
        return m;
    }

    private static Map<String, Object> validDetails() {
        final Map<String, Object> m = new LinkedHashMap<>();
        m.put("screen", "medications");
        return m;
    }

    private void echoSave() {
        when(repository.save(any(TelemetryEvent.class))).thenAnswer(i -> i.getArgument(0));
    }

    private TelemetryEvent captureSaved() {
        final ArgumentCaptor<TelemetryEvent> captor = ArgumentCaptor.forClass(TelemetryEvent.class);
        verify(repository).save(captor.capture());
        return captor.getValue();
    }

    // ==================================================================
    //  Feature toggle
    // ==================================================================

    @Nested
    @DisplayName("Feature toggle")
    class Toggle {

        @Test
        @DisplayName("TC-TEL-01: telemetry disabled returns the event unchanged and never persists")
        void tcTel01_disabledTogglePersistsNothing() {
            toggle.setEnabled(false);
            final TelemetryEvent input = event(ALLOWED_EVENT, validDetails(), validDeviceInfo());

            final TelemetryEvent result = service.record(input);

            assertThat(result).isSameAs(input);
            assertThat(result.getDetails()).containsEntry("screen", "medications");
            verifyNoInteractions(repository);
        }
    }

    // ==================================================================
    //  Allowlist - accept path
    // ==================================================================

    @Nested
    @DisplayName("Allowlist - accept path")
    class AcceptPath {

        @Test
        @DisplayName("TC-TEL-02: allowlisted event with fully allowlisted maps is persisted intact")
        void tcTel02_allowedEventPersistedIntact() {
            echoSave();

            final TelemetryEvent result =
                    service.record(event(ALLOWED_EVENT, validDetails(), validDeviceInfo()));

            final TelemetryEvent saved = captureSaved();
            assertThat(saved.getEventName()).isEqualTo(ALLOWED_EVENT);
            assertThat(saved.getDetails()).containsExactlyInAnyOrderEntriesOf(validDetails());
            assertThat(saved.getDeviceInfo()).containsExactlyInAnyOrderEntriesOf(validDeviceInfo());
            assertThat(result).isNotNull();
        }

        @Test
        @DisplayName("TC-TEL-03: non-allowlisted details keys are stripped, allowlisted keys retained")
        void tcTel03_stripsUnknownDetailKeys() {
            echoSave();
            final Map<String, Object> details = new LinkedHashMap<>();
            details.put("screen", "medications");
            details.put("route", "/medications");
            details.put("unexpected_key", "should-be-dropped");
            details.put("anotherJunkKey", 42);

            service.record(event(ALLOWED_EVENT, details, validDeviceInfo()));

            final TelemetryEvent saved = captureSaved();
            assertThat(saved.getDetails())
                    .containsOnlyKeys("screen", "route")
                    .containsEntry("screen", "medications")
                    .containsEntry("route", "/medications");
        }

        @Test
        @DisplayName("TC-TEL-04: non-allowlisted deviceInfo keys are stripped")
        void tcTel04_stripsUnknownDeviceInfoKeys() {
            echoSave();
            final Map<String, Object> deviceInfo = validDeviceInfo();
            deviceInfo.put("imei", "490154203237518");
            deviceInfo.put("advertisingId", "abc-123");

            service.record(event(ALLOWED_EVENT, validDetails(), deviceInfo));

            final TelemetryEvent saved = captureSaved();
            assertThat(saved.getDeviceInfo())
                    .containsOnlyKeys("uiSurface", "platform", "isWeb", "debug");
        }

        @ParameterizedTest(name = "TC-TEL-05[{0}]")
        @ValueSource(strings = {
                "privacy_telemetry_toggle",
                "screen_view",
                "button_tap",
                "error_network",
                "error_timeout",
                "offline_toggled",
                "feature_use",
                "sync_started",
                "sync_completed",
                "sync_failed",
                "session_start",
                "session_end",
                "feature.medications.view_all",
                "feature.medications.view_active",
                "feature.medications.view_pending",
                "feature.medications.add",
                "feature.medications.approve",
                "feature.medications.delete_soft",
                "feature.medications.delete_hard"
        })
        @DisplayName("TC-TEL-05: every allowlisted event name is persisted")
        void tcTel05_everyAllowlistedNamePersists(final String eventName) {
            echoSave();

            service.record(event(eventName, validDetails(), validDeviceInfo()));

            assertThat(captureSaved().getEventName()).isEqualTo(eventName);
        }
    }

    // ==================================================================
    //  Allowlist - reject path
    // ==================================================================

    @Nested
    @DisplayName("Allowlist - reject path")
    class RejectPath {

        @Test
        @DisplayName("TC-TEL-06: non-allowlisted event name is never persisted")
        void tcTel06_unknownEventNameRejected() {
            final TelemetryEvent input =
                    event("totally_not_an_allowed_event", validDetails(), validDeviceInfo());

            final TelemetryEvent result = service.record(input);

            verify(repository, never()).save(any());
            assertThat(result).isSameAs(input);
        }

        @Test
        @DisplayName("TC-TEL-07: PII-shaped detail keys never reach the repository")
        void tcTel07_piiKeysNeverPersisted() {
            echoSave();
            final Map<String, Object> details = new LinkedHashMap<>();
            details.put("screen", "medications");
            details.put("ssn", "123-45-6789");
            details.put("email", "patient@example.test");
            details.put("patientId", "PT-0001");
            details.put("diagnosis", "synthetic-condition");

            service.record(event(ALLOWED_EVENT, details, validDeviceInfo()));

            assertThat(captureSaved().getDetails())
                    .containsOnlyKeys("screen")
                    .doesNotContainKeys("ssn", "email", "patientId", "diagnosis");
        }

        @Test
        @DisplayName("TC-TEL-08: the event-name allowlist is case sensitive")
        void tcTel08_allowlistIsCaseSensitive() {
            service.record(event("SCREEN_VIEW", validDetails(), validDeviceInfo()));

            verify(repository, never()).save(any());
        }
    }

    // ==================================================================
    //  Malformed input - EXPECTED-FAIL against PR #63 as submitted
    // ==================================================================

    @Nested
    @DisplayName("Malformed input (EXPECTED-FAIL against PR #63)")
    class MalformedInput {

        @Test
        @DisplayName("TC-TEL-09: null event name is rejected without throwing [DEF-TEL-09]")
        void tcTel09_nullEventNameDoesNotThrow() {
            final TelemetryEvent input = event(null, validDetails(), validDeviceInfo());

            assertThatCode(() -> service.record(input)).doesNotThrowAnyException();
            verify(repository, never()).save(any());
        }

        @Test
        @DisplayName("TC-TEL-10: null details is handled without throwing [DEF-TEL-01]")
        void tcTel10_nullDetailsDoesNotThrow() {
            final TelemetryEvent input = event(ALLOWED_EVENT, null, validDeviceInfo());

            assertThatCode(() -> service.record(input)).doesNotThrowAnyException();
        }

        @Test
        @DisplayName("TC-TEL-11: null deviceInfo is handled without throwing [DEF-TEL-02]")
        void tcTel11_nullDeviceInfoDoesNotThrow() {
            final TelemetryEvent input = event(ALLOWED_EVENT, validDetails(), null);

            assertThatCode(() -> service.record(input)).doesNotThrowAnyException();
        }

        @Test
        @DisplayName("TC-TEL-12: allowlisted detail key with a null value does not throw [DEF-TEL-03]")
        void tcTel12_nullDetailValueDoesNotThrow() {
            final Map<String, Object> details = new HashMap<>();
            details.put("reason", null);
            details.put("screen", "medications");
            final TelemetryEvent input = event(ALLOWED_EVENT, details, validDeviceInfo());

            assertThatCode(() -> service.record(input)).doesNotThrowAnyException();
        }

        @Test
        @DisplayName("TC-TEL-22: allowlisted deviceInfo key with a null value does not throw [DEF-TEL-03]")
        void tcTel22_nullDeviceInfoValueDoesNotThrow() {
            final Map<String, Object> deviceInfo = new HashMap<>();
            deviceInfo.put("platform", null);
            deviceInfo.put("uiSurface", "web");
            final TelemetryEvent input = event(ALLOWED_EVENT, validDetails(), deviceInfo);

            assertThatCode(() -> service.record(input)).doesNotThrowAnyException();
        }
    }

    // ==================================================================
    //  Silent-drop behaviour - EXPECTED-FAIL against PR #63 as submitted
    // ==================================================================

    @Nested
    @DisplayName("Silent drops (EXPECTED-FAIL against PR #63)")
    class SilentDrops {

        @Test
        @DisplayName("TC-TEL-13: allowlisted event with empty details is still persisted [DEF-TEL-04]")
        void tcTel13_emptyDetailsStillPersisted() {
            echoSave();

            service.record(event(ALLOWED_EVENT, Map.of(), validDeviceInfo()));

            verify(repository).save(any(TelemetryEvent.class));
        }

        @Test
        @DisplayName("TC-TEL-14: allowlisted event with empty deviceInfo is still persisted [DEF-TEL-04]")
        void tcTel14_emptyDeviceInfoStillPersisted() {
            echoSave();

            service.record(event(ALLOWED_EVENT, validDetails(), Map.of()));

            verify(repository).save(any(TelemetryEvent.class));
        }

        @Test
        @DisplayName("TC-TEL-15: a rejected event is returned to the caller unmutated [DEF-TEL-05]")
        void tcTel15_rejectedEventNotMutated() {
            final Map<String, Object> details = new LinkedHashMap<>();
            details.put("screen", "medications");
            details.put("unexpected_key", "value");
            final Map<String, Object> deviceInfo = new LinkedHashMap<>();
            deviceInfo.put("nothingAllowedHere", "value");

            final TelemetryEvent input = event(ALLOWED_EVENT, details, deviceInfo);
            final TelemetryEvent result = service.record(input);

            verify(repository, never()).save(any());
            assertThat(result.getDetails())
                    .as("event was not persisted, so the caller's copy must be untouched")
                    .containsKey("unexpected_key");
        }

        @Test
        @DisplayName("TC-TEL-23: a non-allowlisted event name is not handed back as a 200-able body [DEF-TEL-18]")
        void tcTel23_unknownEventNameIsNotReturnedAsAccepted() {
            final TelemetryEvent input = event("totally_not_an_allowed_event",
                    validDetails(), validDeviceInfo());

            final TelemetryEvent result = service.record(input);

            verify(repository, never()).save(any());
            assertThat(result)
                    .as("DevTelemetryController serves a non-null return as 200 OK with a null id, "
                            + "so a rejected event name must not come back as an object")
                    .isNull();
        }

        @Test
        @DisplayName("TC-TEL-25: an allowlisted event never yields a null return [DEF-TEL-20]")
        void tcTel25_allowlistedEventNeverReturnsNull() {
            echoSave();

            final TelemetryEvent result =
                    service.record(event(ALLOWED_EVENT, validDetails(), validDeviceInfo()));

            assertThat(result)
                    .as("record() is documented to return the stored event; a null return on an "
                            + "accepted event breaks that contract for every caller")
                    .isNotNull();
        }
    }

    // ==================================================================
    //  recordAnonymous - EXPECTED-FAIL against PR #63 as submitted
    // ==================================================================

    @Nested
    @DisplayName("recordAnonymous (EXPECTED-FAIL against PR #63)")
    class RecordAnonymous {

        @Test
        @DisplayName("TC-TEL-16: recordAnonymous rejects a non-allowlisted event name [DEF-TEL-06]")
        void tcTel16_anonymousRejectsUnknownEvent() {
            service.recordAnonymous(
                    "totally_not_an_allowed_event", validDetails(), validDeviceInfo(), "t", "s");

            verify(repository, never()).save(any());
        }

        @Test
        @DisplayName("TC-TEL-17: recordAnonymous strips non-allowlisted detail keys [DEF-TEL-06]")
        void tcTel17_anonymousStripsUnknownDetailKeys() {
            echoSave();
            final Map<String, Object> details = new LinkedHashMap<>();
            details.put("screen", "medications");
            details.put("ssn", "123-45-6789");

            service.recordAnonymous(ALLOWED_EVENT, details, validDeviceInfo(), "t", "s");

            assertThat(captureSaved().getDetails()).containsOnlyKeys("screen");
        }

        @Test
        @DisplayName("TC-TEL-24: recordAnonymous with null details does not throw [DEF-TEL-19]")
        void tcTel24_anonymousNullDetailsDoesNotThrow() {
            assertThatCode(() -> service.recordAnonymous(
                    ALLOWED_EVENT, null, validDeviceInfo(), "t", "s"))
                    .doesNotThrowAnyException();
        }
    }

    // ==================================================================
    //  Inherited behaviour - recent() is untouched by PR #63 and must not regress
    // ==================================================================

    @Nested
    @DisplayName("recent() - inherited behaviour regression")
    class Recent {

        @Test
        @DisplayName("TC-TEL-18: empty repository yields an empty list")
        void tcTel18_emptyRepositoryYieldsEmptyList() {
            when(repository.findTop50ByOrderByEventTimeDesc()).thenReturn(List.of());

            assertThat(service.recent(50)).isEmpty();
        }

        @Test
        @DisplayName("TC-TEL-19: the requested limit is clamped to the range [1, 200]")
        void tcTel19_limitIsClamped() {
            final List<TelemetryEvent> stored = List.of(
                    event(ALLOWED_EVENT, validDetails(), validDeviceInfo()),
                    event(ALLOWED_EVENT, validDetails(), validDeviceInfo()),
                    event(ALLOWED_EVENT, validDetails(), validDeviceInfo()));
            when(repository.findTop50ByOrderByEventTimeDesc()).thenReturn(stored);

            assertThat(service.recent(0)).hasSize(1);
            assertThat(service.recent(-5)).hasSize(1);
            assertThat(service.recent(2)).hasSize(2);
            assertThat(service.recent(9999)).hasSize(3);
        }

        @Test
        @DisplayName("TC-TEL-20: a null repository result yields an empty list")
        void tcTel20_nullRepositoryResultYieldsEmptyList() {
            when(repository.findTop50ByOrderByEventTimeDesc()).thenReturn(null);

            assertThat(service.recent(50)).isEmpty();
        }
    }
}
