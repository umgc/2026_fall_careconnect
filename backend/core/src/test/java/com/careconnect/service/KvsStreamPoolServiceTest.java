package com.careconnect.service;

import com.careconnect.exception.KvsStreamPoolExhaustedException;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

@DisplayName("KvsStreamPoolService Tests")
class KvsStreamPoolServiceTest {

    private static final String CALL_A = "call-kvs-a";
    private static final String CALL_B = "call-kvs-b";
    private static final String ARN_1 = "arn:aws:kinesisvideo:us-east-1:123456789012:stream/pool-01";
    private static final String ARN_2 = "arn:aws:kinesisvideo:us-east-1:123456789012:stream/pool-02";
    private static final String ARN_3 = "arn:aws:kinesisvideo:us-east-1:123456789012:stream/pool-03";

    @Nested
    @DisplayName("Disabled pool")
    class DisabledPoolTests {

        @Test
        @DisplayName("SPEAKER-020: checkout throws when KVS pool disabled")
        void checkout_disabled_throws() {
            final KvsStreamPoolService service = KvsStreamPoolService.forTest(false, ARN_1 + "," + ARN_2);

            assertThatThrownBy(() -> service.checkout(CALL_A, "att-1"))
                    .isInstanceOf(IllegalStateException.class)
                    .hasMessageContaining("disabled");
        }
    }

    @Nested
    @DisplayName("Enabled pool")
    class EnabledPoolTests {

        private final KvsStreamPoolService service =
                KvsStreamPoolService.forTest(true, ARN_1 + "," + ARN_2 + "," + ARN_3);

        @Test
        @DisplayName("SPEAKER-021: isEnabled true when pool has ARNs")
        void isEnabled_configuredPool() {
            assertThat(service.isEnabled()).isTrue();
            assertThat(service.getPoolSize()).isEqualTo(3);
            assertThat(service.getAvailableCount()).isEqualTo(3);
        }

        @Test
        @DisplayName("SPEAKER-022: checkout assigns first available stream ARN")
        void checkout_assignsStreamArn() {
            final String arn = service.checkout(CALL_A, "att-caregiver");

            assertThat(arn).isIn(ARN_1, ARN_2, ARN_3);
            assertThat(service.getAvailableCount()).isEqualTo(2);
        }

        @Test
        @DisplayName("SPEAKER-023: repeat checkout same holder is idempotent")
        void checkout_sameHolderIdempotent() {
            final String first = service.checkout(CALL_A, "att-caregiver");
            final String second = service.checkout(CALL_A, "att-caregiver");

            assertThat(second).isEqualTo(first);
            assertThat(service.getAvailableCount()).isEqualTo(2);
        }

        @Test
        @DisplayName("SPEAKER-024: two attendees on same call receive distinct streams")
        void checkout_twoAttendeesDistinctStreams() {
            final String caregiver = service.checkout(CALL_A, "att-caregiver");
            final String patient = service.checkout(CALL_A, "att-patient");

            assertThat(caregiver).isNotEqualTo(patient);
            assertThat(service.getAvailableCount()).isEqualTo(1);
        }

        @Test
        @DisplayName("SPEAKER-025: releaseCall frees streams for reuse")
        void releaseCall_freesStreams() {
            service.checkout(CALL_A, "att-1");
            service.checkout(CALL_A, "att-2");
            assertThat(service.getAvailableCount()).isEqualTo(1);

            service.releaseCall(CALL_A);

            assertThat(service.getAvailableCount()).isEqualTo(3);
            assertThat(service.checkout(CALL_B, "att-3")).isIn(ARN_1, ARN_2, ARN_3);
        }

        @Test
        @DisplayName("SPEAKER-026: pool exhausted throws when all streams checked out")
        void checkout_poolExhausted_throws() {
            service.checkout(CALL_A, "att-1");
            service.checkout(CALL_A, "att-2");
            service.checkout(CALL_A, "att-3");

            assertThatThrownBy(() -> service.checkout(CALL_A, "att-4"))
                    .isInstanceOf(KvsStreamPoolExhaustedException.class)
                    .hasMessageContaining("No KVS streams available");
        }

        @Test
        @DisplayName("SPEAKER-027: enabled with empty ARN list is not active")
        void enabledEmptyArns_notActive() {
            final KvsStreamPoolService empty = KvsStreamPoolService.forTest(true, "");

            assertThat(empty.isEnabled()).isFalse();
            assertThatThrownBy(() -> empty.checkout(CALL_A, "att-1"))
                    .isInstanceOf(KvsStreamPoolExhaustedException.class)
                    .hasMessageContaining("not configured");
        }

        @Test
        @DisplayName("SPEAKER-028: releaseCall on unknown call is no-op")
        void releaseCall_unknownCall_noOp() {
            service.releaseCall("never-checked-out");
            assertThat(service.getAvailableCount()).isEqualTo(3);
        }
    }
}
