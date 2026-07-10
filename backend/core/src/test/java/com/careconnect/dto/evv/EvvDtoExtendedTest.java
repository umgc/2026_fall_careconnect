package com.careconnect.dto.evv;

// Tests for remaining EVV DTOs: EvvRecordRequestDto, EvvRecordResponse,
// EvvCorrectionRequestDto, EvvLocationResponse, ParticipantResponseDto.

import com.careconnect.model.evv.EvvLocationRole;
import com.careconnect.model.evv.EvvLocationType;
import com.careconnect.model.evv.NoGpsReason;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.Map;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.*;

@DisplayName("EVV DTOs — extended")
class EvvDtoExtendedTest {

    private static final OffsetDateTime NOW =
            OffsetDateTime.of(2026, 3, 17, 10, 0, 0, 0, ZoneOffset.UTC);

    @Nested
    @DisplayName("EvvRecordRequestDto")
    class EvvRecordRequestDtoTests {

        @Test
        @DisplayName("builder sets all required fields")
        void builderRequired() {
            EvvRecordRequestDto dto = EvvRecordRequestDto.builder()
                    .serviceType("Personal Care")
                    .individualName("Alice Smith")
                    .caregiverId(1L)
                    .patientId(10L)
                    .dateOfService(LocalDate.of(2026, 3, 17))
                    .timeIn(NOW)
                    .timeOut(NOW.plusHours(2))
                    .stateCode("MD")
                    .build();

            assertEquals("Personal Care", dto.getServiceType());
            assertEquals("Alice Smith", dto.getIndividualName());
            assertEquals(1L, dto.getCaregiverId());
            assertEquals(10L, dto.getPatientId());
            assertEquals("MD", dto.getStateCode());
            assertEquals(NOW, dto.getTimeIn());
        }

        @Test
        @DisplayName("builder sets check-in location fields")
        void builderCheckinLocation() {
            EvvRecordRequestDto dto = EvvRecordRequestDto.builder()
                    .serviceType("Care")
                    .individualName("Test")
                    .caregiverId(1L)
                    .patientId(10L)
                    .dateOfService(LocalDate.now())
                    .timeIn(NOW)
                    .timeOut(NOW.plusHours(1))
                    .stateCode("VA")
                    .checkinLocationLat(38.9)
                    .checkinLocationLng(-77.0)
                    .checkinLocationSource("GPS")
                    .checkinAccuracyM(5.0)
                    .build();

            assertEquals(38.9, dto.getCheckinLocationLat());
            assertEquals(-77.0, dto.getCheckinLocationLng());
            assertEquals("GPS", dto.getCheckinLocationSource());
            assertEquals(5.0, dto.getCheckinAccuracyM());
        }

        @Test
        @DisplayName("builder sets checkout location fields")
        void builderCheckoutLocation() {
            EvvRecordRequestDto dto = EvvRecordRequestDto.builder()
                    .serviceType("Care")
                    .individualName("Test")
                    .caregiverId(1L)
                    .patientId(10L)
                    .dateOfService(LocalDate.now())
                    .timeIn(NOW)
                    .timeOut(NOW.plusHours(1))
                    .stateCode("DC")
                    .checkoutLocationLat(38.91)
                    .checkoutLocationLng(-77.04)
                    .checkoutLocationSource("MANUAL")
                    .checkoutNoGpsReason("INDOOR_LOCATION")
                    .checkoutManualAddress("123 Main St")
                    .build();

            assertEquals("MANUAL", dto.getCheckoutLocationSource());
            assertEquals("INDOOR_LOCATION", dto.getCheckoutNoGpsReason());
            assertEquals("123 Main St", dto.getCheckoutManualAddress());
        }

        @Test
        @DisplayName("optional fields null by default")
        void optionalFieldsNull() {
            EvvRecordRequestDto dto = EvvRecordRequestDto.builder()
                    .serviceType("Care")
                    .individualName("Test")
                    .caregiverId(1L)
                    .patientId(10L)
                    .dateOfService(LocalDate.now())
                    .timeIn(NOW)
                    .timeOut(NOW.plusHours(1))
                    .stateCode("MD")
                    .build();

            assertNull(dto.getLocationLat());
            assertNull(dto.getCheckinLocationLat());
            assertNull(dto.getCheckoutLocationLat());
            assertNull(dto.getDeviceInfo());
            assertNull(dto.getScheduledVisitId());
        }

        @Test
        @DisplayName("scheduled visit ID links to shift scheduling")
        void scheduledVisitId() {
            EvvRecordRequestDto dto = EvvRecordRequestDto.builder()
                    .serviceType("Care")
                    .individualName("Test")
                    .caregiverId(1L)
                    .patientId(10L)
                    .dateOfService(LocalDate.now())
                    .timeIn(NOW)
                    .timeOut(NOW.plusHours(1))
                    .stateCode("MD")
                    .scheduledVisitId(42L)
                    .build();

            assertEquals(42L, dto.getScheduledVisitId());
        }
    }

    @Nested
    @DisplayName("EvvRecordResponse")
    class EvvRecordResponseTests {

        @Test
        @DisplayName("builder sets all fields")
        void builderSetsAll() {
            EvvRecordResponse resp = EvvRecordResponse.builder()
                    .id(1L)
                    .patientId(10L)
                    .patientMaNumber("MA-12345")
                    .serviceType("Skilled Nursing")
                    .individualName("Jane Doe")
                    .caregiverId(5L)
                    .dateOfService(LocalDate.of(2026, 3, 17))
                    .timeIn(NOW)
                    .timeOut(NOW.plusHours(2))
                    .locationLat(38.9)
                    .locationLng(-77.0)
                    .locationSource("gps")
                    .stateCode("VA")
                    .status("CONFIRMED")
                    .createdAt(NOW)
                    .updatedAt(NOW)
                    .build();

            assertEquals(1L, resp.getId());
            assertEquals("MA-12345", resp.getPatientMaNumber());
            assertEquals("CONFIRMED", resp.getStatus());
            assertEquals(38.9, resp.getLocationLat());
        }

        @Test
        @DisplayName("no-arg constructor creates null fields")
        void noArgConstructor() {
            EvvRecordResponse resp = new EvvRecordResponse();
            assertNull(resp.getId());
            assertNull(resp.getStatus());
        }
    }

    @Nested
    @DisplayName("EvvCorrectionRequestDto")
    class EvvCorrectionRequestDtoTests {

        @Test
        @DisplayName("builder sets required fields")
        void builderRequired() {
            EvvCorrectionRequestDto dto = EvvCorrectionRequestDto.builder()
                    .originalRecordId(42L)
                    .reasonCode("TIME_ERROR")
                    .explanation("Wrong check-in time")
                    .build();

            assertEquals(42L, dto.getOriginalRecordId());
            assertEquals("TIME_ERROR", dto.getReasonCode());
            assertEquals("Wrong check-in time", dto.getExplanation());
        }

        @Test
        @DisplayName("builder sets optional corrected fields")
        void builderOptionalFields() {
            EvvCorrectionRequestDto dto = EvvCorrectionRequestDto.builder()
                    .originalRecordId(1L)
                    .reasonCode("LOCATION_ERROR")
                    .explanation("Wrong address")
                    .serviceType("Companion Care")
                    .locationLat(38.91)
                    .locationLng(-77.04)
                    .locationSource("manual")
                    .stateCode("DC")
                    .build();

            assertEquals("Companion Care", dto.getServiceType());
            assertEquals(38.91, dto.getLocationLat());
            assertEquals("DC", dto.getStateCode());
        }

        @Test
        @DisplayName("optional fields null when not set")
        void optionalFieldsNull() {
            EvvCorrectionRequestDto dto = EvvCorrectionRequestDto.builder()
                    .originalRecordId(1L)
                    .reasonCode("OTHER")
                    .explanation("Test")
                    .build();

            assertNull(dto.getServiceType());
            assertNull(dto.getTimeIn());
            assertNull(dto.getLocationLat());
        }
    }

    @Nested
    @DisplayName("EvvLocationResponse")
    class EvvLocationResponseTests {

        @Test
        @DisplayName("builder sets all fields including enums")
        void builderSetsAll() {
            UUID uuid = UUID.randomUUID();
            EvvLocationResponse resp = EvvLocationResponse.builder()
                    .id(uuid)
                    .evvRecordId(42L)
                    .role(EvvLocationRole.CHECK_IN)
                    .type(EvvLocationType.GPS)
                    .latitude(BigDecimal.valueOf(38.9072))
                    .longitude(BigDecimal.valueOf(-77.0369))
                    .accuracyM(BigDecimal.valueOf(5.0))
                    .noGpsReason(null)
                    .createdAt(NOW)
                    .build();

            assertEquals(uuid, resp.getId());
            assertEquals(42L, resp.getEvvRecordId());
            assertEquals(EvvLocationRole.CHECK_IN, resp.getRole());
            assertEquals(EvvLocationType.GPS, resp.getType());
            assertNull(resp.getNoGpsReason());
        }

        @Test
        @DisplayName("manual location includes noGpsReason and manualAddress")
        void manualLocation() {
            EvvLocationResponse resp = EvvLocationResponse.builder()
                    .role(EvvLocationRole.CHECK_OUT)
                    .type(EvvLocationType.MANUAL)
                    .noGpsReason(NoGpsReason.INDOOR_LOCATION)
                    .manualAddress("456 Oak Ave, Suite 200")
                    .build();

            assertEquals(EvvLocationType.MANUAL, resp.getType());
            assertEquals(NoGpsReason.INDOOR_LOCATION, resp.getNoGpsReason());
            assertEquals("456 Oak Ave, Suite 200", resp.getManualAddress());
        }
    }

    @Nested
    @DisplayName("ParticipantResponseDto")
    class ParticipantResponseDtoTests {

        @Test
        @DisplayName("builder sets all fields")
        void builderSetsAll() {
            ParticipantResponseDto dto = ParticipantResponseDto.builder()
                    .id(1L)
                    .patientName("Alice Smith")
                    .maNumber("MA-99999")
                    .createdAt(NOW)
                    .createdBy("admin@careconnect.com")
                    .build();

            assertEquals(1L, dto.getId());
            assertEquals("Alice Smith", dto.getPatientName());
            assertEquals("MA-99999", dto.getMaNumber());
            assertEquals("admin@careconnect.com", dto.getCreatedBy());
        }

        @Test
        @DisplayName("no-arg constructor creates null fields")
        void noArgConstructor() {
            ParticipantResponseDto dto = new ParticipantResponseDto();
            assertNull(dto.getId());
            assertNull(dto.getPatientName());
        }
    }
}
