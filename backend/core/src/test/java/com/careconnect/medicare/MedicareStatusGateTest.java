package com.careconnect.medicare;

import static org.assertj.core.api.Assertions.assertThat;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.core.JsonProcessingException;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;

/** TC-MCR-GATE: the status gate drops resources a record should never surface. */
class MedicareStatusGateTest {

    private final ObjectMapper objectMapper = new ObjectMapper();
    private MedicareStatusGate gate;

    @BeforeEach
    void setUp() {
        gate = new MedicareStatusGate();
    }

    private JsonNode json(final String raw) {
        try {
            return objectMapper.readTree(raw);
        } catch (final JsonProcessingException e) {
            throw new AssertionError("test fixture is not valid JSON: " + raw, e);
        }
    }

    /** TC-MCR-GATE-010 */
    @Test
    void isAllowed_whenStatusActive_returnsTrue() {
        assertThat(gate.isAllowed(json("{\"resourceType\":\"Coverage\",\"status\":\"active\"}"))).isTrue();
    }

    /** TC-MCR-GATE-020 */
    @ParameterizedTest
    @ValueSource(strings = {"cancelled", "canceled", "draft", "entered-in-error", "nullified"})
    void isAllowed_whenStatusBlocked_returnsFalse(final String status) {
        assertThat(gate.isAllowed(json("{\"status\":\"" + status + "\"}"))).isFalse();
    }

    /** TC-MCR-GATE-021: the blocked set is matched case-insensitively. */
    @Test
    void isAllowed_whenStatusBlockedInMixedCase_returnsFalse() {
        assertThat(gate.isAllowed(json("{\"status\":\"Entered-In-Error\"}"))).isFalse();
    }

    /** TC-MCR-GATE-030 */
    @Test
    void isAllowed_whenResourceNull_returnsFalse() {
        assertThat(gate.isAllowed(null)).isFalse();
        assertThat(gate.isAllowed(objectMapper.nullNode())).isFalse();
    }

    /** TC-MCR-GATE-040: no status field at all is not grounds to drop a resource. */
    @Test
    void isAllowed_whenNoStatusPresent_returnsTrue() {
        assertThat(gate.isAllowed(json("{\"resourceType\":\"Patient\",\"id\":\"abc\"}"))).isTrue();
    }

    /** TC-MCR-GATE-050: verificationStatus invalidates a resource whose own status looks fine. */
    @Test
    void isAllowed_whenVerificationStatusEnteredInError_returnsFalse() {
        final String raw = "{\"status\":\"active\",\"verificationStatus\":{\"coding\":"
                + "[{\"code\":\"entered-in-error\"}]}}";
        assertThat(gate.isAllowed(json(raw))).isFalse();
    }

    /** TC-MCR-GATE-060 */
    @Test
    void statusOf_whenOnlyDocStatusPresent_readsDocStatus() {
        assertThat(gate.statusOf(json("{\"docStatus\":\"preliminary\"}"))).isEqualTo("preliminary");
    }

    /** TC-MCR-GATE-070 */
    @Test
    void statusOf_whenOnlyClinicalStatusPresent_readsCodingCode() {
        final String raw = "{\"clinicalStatus\":{\"coding\":[{\"code\":\"resolved\"}]}}";
        assertThat(gate.statusOf(json(raw))).isEqualTo("resolved");
    }

    /** TC-MCR-GATE-080: a malformed CodeableConcept is absent, not an error. */
    @Test
    void statusOf_whenClinicalStatusCodingEmpty_returnsNull() {
        assertThat(gate.statusOf(json("{\"clinicalStatus\":{\"coding\":[]}}"))).isNull();
        assertThat(gate.statusOf(json("{\"clinicalStatus\":{}}"))).isNull();
        assertThat(gate.statusOf(null)).isNull();
    }
}
