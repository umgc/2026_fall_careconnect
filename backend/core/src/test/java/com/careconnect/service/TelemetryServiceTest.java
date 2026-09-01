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
 * <p>Test IDs TC-TEL-01 .. TC-TEL-25, TC-TEL-28 and TC-TEL-29 are permanent. Never renumber,
 * never reuse - TC-TEL-14 is withdrawn and its identifier stays retired. TC-TEL-26 and
 * TC-TEL-27 live in {@code TelemetrySecurityDevChainTest}.
 *
 * <p>Cases whose Javadoc says EXPECTED-FAIL assert the <em>intended</em> behaviour and are red
 * against the branch as it stands. Each names the defect it proves. They are not
 * characterization tests; they must go green once that defect is fixed. The marker sits on the
 * individual case, not on the enclosing group - the groups now hold a mix of red and green, and
 * a blanket label on a group would let a real regression hide inside it.
 *
 * <p>TC-TEL-22 .. TC-TEL-25 were added 2026-08-29 after commit {@code 6f38c103}. That commit closed
 * DEF-TEL-01, DEF-TEL-02, DEF-TEL-06 and DEF-TEL-09, and introduced DEF-TEL-18, DEF-TEL-19 and
 * DEF-TEL-20 in their place. TC-TEL-16 and TC-TEL-17 now pass and are retained as regression cover.
 *
 * <p>At {@code d48358e6} the still-failing cases are TC-TEL-12, TC-TEL-22 and TC-TEL-28
 * (DEF-TEL-03), TC-TEL-15 (DEF-TEL-05) and TC-TEL-23 (DEF-TEL-18). TC-TEL-13 and TC-TEL-24
 * went green at {@code 0139bd84}.
 *
 * <p>Changes of 2026-09-01, none of which renumbered or reused an identifier. TC-TEL-15 now
 * asserts on the caller's own object rather than on a return value that is null on that path,
 * which had turned it into an Error. TC-TEL-28 was added for the one DEF-TEL-03 collector no
 * case reached. TC-TEL-14 is withdrawn: its premise held for details but not for deviceInfo,
 * which the client builds as a fixed four-key literal, so it asserted a preference rather than
 * a defect. TC-TEL-29 replaces it and pins the intended reject instead.
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

        /**
         * TC-TEL-29 - added 2026-09-01, replacing the withdrawn TC-TEL-14.
         *
         * <p>Pins the behaviour the service intends rather than the one TC-TEL-14 preferred: an
         * event whose deviceInfo carries no usable key is rejected rather than stored with empty
         * metadata. Two inputs reach that outcome by different routes - an empty map is refused at
         * {@code TelemetryService.java:72}, and a non-empty map with no allowlisted key is refused
         * at {@code :80} after filtering. Both must return null and persist nothing.
         *
         * <p>This is a decision, not a defect, so the case is expected to pass. It fails if anyone
         * relaxes either reject and starts storing events with no device metadata.
         */
        @Test
        @DisplayName("TC-TEL-29: an event with no usable deviceInfo is rejected, not stored")
        void tcTel29_unusableDeviceInfoRejected() {
            final Map<String, Object> noAllowedKeys = new LinkedHashMap<>();
            noAllowedKeys.put("nothingAllowedHere", "value");

            assertThat(service.record(event(ALLOWED_EVENT, validDetails(), Map.of())))
                    .as("an empty deviceInfo map is refused at TelemetryService.java:72")
                    .isNull();
            assertThat(service.record(event(ALLOWED_EVENT, validDetails(), noAllowedKeys)))
                    .as("a deviceInfo map with no allowlisted key is refused at :80")
                    .isNull();

            verify(repository, never()).save(any());
        }

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
    //  Malformed input - null names, null maps, null map values
    // ==================================================================

    @Nested
    @DisplayName("Malformed input")
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

        /**
         * TC-TEL-12 - EXPECTED-FAIL at {@code d48358e6}. {@code Collectors.toMap} delegates to
         * {@code HashMap.merge}, which rejects a null value. The
         * {@code removeIf(Objects::isNull)} added by {@code 0139bd84} sits after the collector
         * and is therefore unreachable for this input.
         */
        @Test
        @DisplayName("TC-TEL-12: allowlisted detail key with a null value does not throw [DEF-TEL-03]")
        void tcTel12_nullDetailValueDoesNotThrow() {
            final Map<String, Object> details = new HashMap<>();
            details.put("reason", null);
            details.put("screen", "medications");
            final TelemetryEvent input = event(ALLOWED_EVENT, details, validDeviceInfo());

            assertThatCode(() -> service.record(input)).doesNotThrowAnyException();
        }

        /**
         * TC-TEL-22 - EXPECTED-FAIL at {@code d48358e6}. DEF-TEL-03 on the deviceInfo collector in
         * {@code record()}. See {@link #tcTel28_anonymousNullDeviceInfoValueDoesNotThrow()} for the
         * same defect in {@code recordAnonymous}.
         */
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
    //  Silent-drop behaviour - what the caller and the controller observe on a reject
    // ==================================================================

    @Nested
    @DisplayName("Silent drops")
    class SilentDrops {

        @Test
        @DisplayName("TC-TEL-13: allowlisted event with empty details is still persisted [DEF-TEL-04]")
        void tcTel13_emptyDetailsStillPersisted() {
            echoSave();

            service.record(event(ALLOWED_EVENT, Map.of(), validDeviceInfo()));

            verify(repository).save(any(TelemetryEvent.class));
        }

        /*
         * TC-TEL-14 - WITHDRAWN 2026-09-01. The identifier is retired and must never be reused.
         *
         * The case asserted that an allowlisted event with an empty deviceInfo map is still
         * persisted, on the reasoning behind DEF-TEL-04: the client can produce an empty map, so
         * rejecting one drops legitimate events. That reasoning holds for details, where
         * TelemetryGuardrails.sanitize returns an empty map when every property is blocked or over
         * 64 characters - the details half of DEF-TEL-04 was a real defect and 0139bd84 closed it.
         *
         * It does not hold for deviceInfo. The client builds that map as a hardcoded four-key
         * literal (telemetry.dart:159-163) and all four keys are on allowedDeviceInfo, so no client
         * can send an empty or null deviceInfo. Rejecting one at TelemetryService.java:72 is
         * deliberate and harms nothing. The case asserted a preference, not a defect, and the
         * deviceInfo half of DEF-TEL-04 is withdrawn with it.
         *
         * TC-TEL-29 replaces it, asserting the behaviour the service actually intends.
         */

        /**
         * TC-TEL-15 - EXPECTED-FAIL. Amended 2026-09-01: asserts on the caller's own object rather
         * than on the return value. Since {@code 6f38c103} this reject path returns {@code null},
         * which turned the case into a NullPointerException Error and hid what it was written to
         * prove. {@code record()} calls {@code setDetails} on the caller's own event at
         * {@code TelemetryService.java:68}, unconditionally once the name is allowlisted and before
         * either deviceInfo reject at {@code :72} and {@code :80}. This case supplies a deviceInfo
         * map that is non-null and non-empty but carries no allowlisted key, so it clears
         * {@code :72} and is rejected at {@code :80} - by which point the caller is already holding
         * a stripped map for an event that was never stored.
         *
         * <p>Severity Low, corrected 2026-09-01 from Medium. The only caller in {@code src/main} is
         * {@code DevTelemetryController:52}, which reassigns the returned reference and discards it
         * on null, so nothing observes the mutation today. It is a latent hazard for the next
         * caller, not a live bug.
         */
        @Test
        @DisplayName("TC-TEL-15: a rejected event is returned to the caller unmutated [DEF-TEL-05]")
        void tcTel15_rejectedEventNotMutated() {
            final Map<String, Object> details = new LinkedHashMap<>();
            details.put("screen", "medications");
            details.put("unexpected_key", "value");
            final Map<String, Object> deviceInfo = new LinkedHashMap<>();
            deviceInfo.put("nothingAllowedHere", "value");

            final TelemetryEvent input = event(ALLOWED_EVENT, details, deviceInfo);
            service.record(input);

            verify(repository, never()).save(any());
            assertThat(input.getDetails())
                    .as("event was not persisted, so the caller's copy must be untouched")
                    .containsKey("unexpected_key");
        }

        /**
         * TC-TEL-23 - EXPECTED-FAIL at {@code d48358e6}. {@code TelemetryService.java:86} returns
         * the unsaved event, which {@code DevTelemetryController} serves as 200 OK with a null
         * id. Invalid details produce 400; an invalid event name produces 200.
         */
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
    //  recordAnonymous - the second ingest entry point
    // ==================================================================

    @Nested
    @DisplayName("recordAnonymous")
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

        /**
         * TC-TEL-28 - EXPECTED-FAIL. Added 2026-09-01. DEF-TEL-03 on the fourth and last
         * collector, {@code TelemetryService.java:153}.
         *
         * <p>{@code 0139bd84} added {@code removeIf(Objects::isNull)} after three of the four
         * {@code Collectors.toMap} calls and omitted it entirely on this one, so
         * {@code record()} and {@code recordAnonymous} disagree. The omission changes nothing
         * today - the collector throws before any of those guards can run - but it means a
         * correct fix applied only where the guards already are would leave this path broken
         * and untested. TC-TEL-22 is the same defect in {@code record()}.
         */
        @Test
        @DisplayName("TC-TEL-28: recordAnonymous with a null deviceInfo value does not throw [DEF-TEL-03]")
        void tcTel28_anonymousNullDeviceInfoValueDoesNotThrow() {
            final Map<String, Object> deviceInfo = new HashMap<>();
            deviceInfo.put("platform", null);
            deviceInfo.put("uiSurface", "web");

            assertThatCode(() -> service.recordAnonymous(
                    ALLOWED_EVENT, validDetails(), deviceInfo, "t", "s"))
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
