package com.careconnect.model.evv;

import com.careconnect.model.evv.NoGpsReason;
import org.junit.jupiter.api.Test;

import java.lang.reflect.Method;
import java.math.BigDecimal;
import java.time.OffsetDateTime;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class EvvRecordLocationTest {

    // ─── No-arg constructor ───────────────────────────────────────────────────

    @Test
    void noArgConstructor_createsInstance() throws Exception {
        final EvvRecordLocation loc = new EvvRecordLocation();

        assertThat(loc).isNotNull();
        assertThat(loc.getId()).isNull();
        assertThat(loc.getEvvRecordId()).isNull();
        assertThat(loc.getRole()).isNull();
        assertThat(loc.getType()).isNull();
        assertThat(loc.getLatitude()).isNull();
        assertThat(loc.getLongitude()).isNull();
        assertThat(loc.getAccuracyM()).isNull();
        assertThat(loc.getAddressSnapshotJson()).isNull();
        assertThat(loc.getCreatedAt()).isNull();
    }

    // ─── Builder all fields ───────────────────────────────────────────────────

    @Test
    void builder_allFields() throws Exception {
        final UUID id = UUID.randomUUID();
        final OffsetDateTime now = OffsetDateTime.now();
        final Map<String, Object> addressSnapshot = new HashMap<>();
        addressSnapshot.put("street", "1 Main St");

        final EvvRecordLocation loc = EvvRecordLocation.builder()
                .id(id)
                .evvRecordId(1L)
                .role(EvvLocationRole.CHECK_IN)
                .type(EvvLocationType.GPS)
                .latitude(new BigDecimal("39.290385"))
                .longitude(new BigDecimal("-76.612189"))
                .accuracyM(new BigDecimal("5.50"))
                .addressSnapshotJson(addressSnapshot)
                .createdAt(now)
                .build();

        assertThat(loc.getId()).isEqualTo(id);
        assertThat(loc.getEvvRecordId()).isEqualTo(1L);
        assertThat(loc.getRole()).isEqualTo(EvvLocationRole.CHECK_IN);
        assertThat(loc.getType()).isEqualTo(EvvLocationType.GPS);
        assertThat(loc.getLatitude()).isEqualByComparingTo(new BigDecimal("39.290385"));
        assertThat(loc.getLongitude()).isEqualByComparingTo(new BigDecimal("-76.612189"));
        assertThat(loc.getAccuracyM()).isEqualByComparingTo(new BigDecimal("5.50"));
        assertThat(loc.getAddressSnapshotJson()).containsEntry("street", "1 Main St");
        assertThat(loc.getCreatedAt()).isEqualTo(now);
    }

    // ─── onCreate() ───────────────────────────────────────────────────────────

    @Test
    void onCreate_setsIdAndCreatedAtWhenNull() throws Exception {
        final EvvRecordLocation loc = new EvvRecordLocation();

        final Method m = EvvRecordLocation.class.getDeclaredMethod("onCreate");
        m.setAccessible(true);
        m.invoke(loc);

        assertThat(loc.getId()).isNotNull();
        assertThat(loc.getCreatedAt()).isNotNull();
    }

    @Test
    void onCreate_doesNotOverwriteExistingValues() throws Exception {
        final EvvRecordLocation loc = new EvvRecordLocation();
        final UUID existingId = UUID.randomUUID();
        final OffsetDateTime existingTime = OffsetDateTime.now().minusDays(1);
        loc.setId(existingId);
        loc.setCreatedAt(existingTime);

        final Method m = EvvRecordLocation.class.getDeclaredMethod("onCreate");
        m.setAccessible(true);
        m.invoke(loc);

        assertThat(loc.getId()).isEqualTo(existingId);
        assertThat(loc.getCreatedAt()).isEqualTo(existingTime);
    }

    // ─── validate() – GPS ────────────────────────────────────────────────────

    @Test
    void validate_gpsWithCoordinates_succeeds() throws Exception {
        final EvvRecordLocation loc = new EvvRecordLocation();
        loc.setType(EvvLocationType.GPS);
        loc.setLatitude(new BigDecimal("39.2904"));
        loc.setLongitude(new BigDecimal("-76.6122"));

        loc.validate(); // should not throw
    }

    @Test
    void validate_gpsMissingLatitude_throwsIllegalState() throws Exception {
        final EvvRecordLocation loc = new EvvRecordLocation();
        loc.setType(EvvLocationType.GPS);
        loc.setLongitude(new BigDecimal("-76.6122"));

        assertThatThrownBy(loc::validate)
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("latitude and longitude");
    }

    @Test
    void validate_gpsMissingLongitude_throwsIllegalState() throws Exception {
        final EvvRecordLocation loc = new EvvRecordLocation();
        loc.setType(EvvLocationType.GPS);
        loc.setLatitude(new BigDecimal("39.2904"));

        assertThatThrownBy(loc::validate)
                .isInstanceOf(IllegalStateException.class);
    }

    // ─── validate() – PATIENT_ADDRESS ────────────────────────────────────────

    @Test
    void validate_patientAddressWithSnapshot_succeeds() throws Exception {
        final EvvRecordLocation loc = new EvvRecordLocation();
        loc.setType(EvvLocationType.PATIENT_ADDRESS);
        final Map<String, Object> snapshot = new HashMap<>();
        snapshot.put("street", "1 Main St");
        loc.setAddressSnapshotJson(snapshot);
        loc.setNoGpsReason(NoGpsReason.HOME_VISIT_ADDRESS_USED);

        loc.validate(); // should not throw
    }

    @Test
    void validate_patientAddressNullSnapshot_throwsIllegalState() throws Exception {
        final EvvRecordLocation loc = new EvvRecordLocation();
        loc.setType(EvvLocationType.PATIENT_ADDRESS);
        loc.setAddressSnapshotJson(null);

        assertThatThrownBy(loc::validate)
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("address snapshot");
    }

    @Test
    void validate_patientAddressEmptySnapshot_throwsIllegalState() throws Exception {
        final EvvRecordLocation loc = new EvvRecordLocation();
        loc.setType(EvvLocationType.PATIENT_ADDRESS);
        loc.setAddressSnapshotJson(new HashMap<>());

        assertThatThrownBy(loc::validate)
                .isInstanceOf(IllegalStateException.class);
    }

    @Test
    void validate_patientAddressNullNoGpsReason_throwsIllegalState() throws Exception {
        final EvvRecordLocation loc = new EvvRecordLocation();
        loc.setType(EvvLocationType.PATIENT_ADDRESS);
        final Map<String, Object> snapshot = new HashMap<>();
        snapshot.put("street", "1 Main St");
        loc.setAddressSnapshotJson(snapshot);
        loc.setNoGpsReason(null);

        assertThatThrownBy(loc::validate)
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("noGpsReason");
    }

    // ─── validate() – MANUAL ──────────────────────────────────────────────────

    @Test
    void validate_manualWithAddressAndReason_succeeds() throws Exception {
        final EvvRecordLocation loc = new EvvRecordLocation();
        loc.setType(EvvLocationType.MANUAL);
        loc.setManualAddress("123 Main St");
        loc.setNoGpsReason(NoGpsReason.GPS_TIMEOUT);

        loc.validate(); // should not throw
    }

    @Test
    void validate_manualNullAddress_throwsIllegalState() throws Exception {
        final EvvRecordLocation loc = new EvvRecordLocation();
        loc.setType(EvvLocationType.MANUAL);
        loc.setManualAddress(null);

        assertThatThrownBy(loc::validate)
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("manual address");
    }

    @Test
    void validate_manualBlankAddress_throwsIllegalState() throws Exception {
        final EvvRecordLocation loc = new EvvRecordLocation();
        loc.setType(EvvLocationType.MANUAL);
        loc.setManualAddress("   ");

        assertThatThrownBy(loc::validate)
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("manual address");
    }

    @Test
    void validate_manualAddressNullNoGpsReason_throwsIllegalState() throws Exception {
        final EvvRecordLocation loc = new EvvRecordLocation();
        loc.setType(EvvLocationType.MANUAL);
        loc.setManualAddress("123 Main St");
        loc.setNoGpsReason(null);

        assertThatThrownBy(loc::validate)
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("noGpsReason");
    }

    // ─── validate() – null type ───────────────────────────────────────────────

    @Test
    void validate_nullType_doesNotThrow() throws Exception {
        final EvvRecordLocation loc = new EvvRecordLocation();
        // type is null – neither branch matches, method returns normally
        loc.validate();
    }
}
