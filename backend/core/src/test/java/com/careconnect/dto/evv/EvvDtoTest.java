package com.careconnect.dto.evv;

// Tests for EVV DTOs and the NoGpsReason enum.
// Covers constructors, builders, field access, defaults.

import com.careconnect.model.evv.NoGpsReason;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import java.time.LocalDate;
import java.util.List;

import static org.junit.jupiter.api.Assertions.*;

@DisplayName("EVV DTOs")
class EvvDtoTest {

    @Nested
    @DisplayName("EorApprovalRequestDto")
    class EorApprovalRequestDtoTests {

        @Test
        @DisplayName("builder sets all fields")
        void builderSetsFields() {
            EorApprovalRequestDto dto = EorApprovalRequestDto.builder()
                    .recordId(42L)
                    .comment("Approved after review")
                    .build();
            assertEquals(42L, dto.getRecordId());
            assertEquals("Approved after review", dto.getComment());
        }

        @Test
        @DisplayName("no-arg constructor creates empty instance")
        void noArgConstructor() {
            EorApprovalRequestDto dto = new EorApprovalRequestDto();
            assertNull(dto.getRecordId());
            assertNull(dto.getComment());
        }

        @Test
        @DisplayName("comment is optional")
        void commentOptional() {
            EorApprovalRequestDto dto = EorApprovalRequestDto.builder()
                    .recordId(1L)
                    .build();
            assertNull(dto.getComment());
        }
    }

    @Nested
    @DisplayName("EvvReviewRequest")
    class EvvReviewRequestTests {

        @Test
        @DisplayName("builder sets approve and comment")
        void builderSetsFields() {
            EvvReviewRequest req = EvvReviewRequest.builder()
                    .approve(true)
                    .comment("Looks good")
                    .build();
            assertTrue(req.isApprove());
            assertEquals("Looks good", req.getComment());
        }

        @Test
        @DisplayName("approve defaults to false")
        void approveDefaultsFalse() {
            EvvReviewRequest req = new EvvReviewRequest();
            assertFalse(req.isApprove());
        }

        @Test
        @DisplayName("reject with no comment")
        void rejectNoComment() {
            EvvReviewRequest req = EvvReviewRequest.builder()
                    .approve(false)
                    .build();
            assertFalse(req.isApprove());
            assertNull(req.getComment());
        }
    }

    @Nested
    @DisplayName("EvvSearchRequestDto")
    class EvvSearchRequestDtoTests {

        @Test
        @DisplayName("builder defaults: page=0, size=20, sortBy=createdAt, sortDirection=DESC")
        void builderDefaults() {
            EvvSearchRequestDto req = EvvSearchRequestDto.builder().build();
            assertEquals(0, req.getPage());
            assertEquals(20, req.getSize());
            assertEquals("createdAt", req.getSortBy());
            assertEquals("DESC", req.getSortDirection());
        }

        @Test
        @DisplayName("builder overrides defaults")
        void builderOverrides() {
            EvvSearchRequestDto req = EvvSearchRequestDto.builder()
                    .patientName("Alice")
                    .status("APPROVED")
                    .stateCode("VA")
                    .page(2)
                    .size(50)
                    .sortBy("dateOfService")
                    .sortDirection("ASC")
                    .build();
            assertEquals("Alice", req.getPatientName());
            assertEquals("APPROVED", req.getStatus());
            assertEquals("VA", req.getStateCode());
            assertEquals(2, req.getPage());
            assertEquals(50, req.getSize());
            assertEquals("dateOfService", req.getSortBy());
            assertEquals("ASC", req.getSortDirection());
        }

        @Test
        @DisplayName("date range filters")
        void dateRange() {
            LocalDate start = LocalDate.of(2026, 1, 1);
            LocalDate end = LocalDate.of(2026, 3, 31);
            EvvSearchRequestDto req = EvvSearchRequestDto.builder()
                    .startDate(start)
                    .endDate(end)
                    .build();
            assertEquals(start, req.getStartDate());
            assertEquals(end, req.getEndDate());
        }

        @Test
        @DisplayName("all filter fields null by default")
        void filtersNullByDefault() {
            EvvSearchRequestDto req = EvvSearchRequestDto.builder().build();
            assertNull(req.getPatientName());
            assertNull(req.getServiceType());
            assertNull(req.getCaregiverId());
            assertNull(req.getPatientId());
            assertNull(req.getStartDate());
            assertNull(req.getEndDate());
            assertNull(req.getStateCode());
            assertNull(req.getStatus());
        }
    }

    @Nested
    @DisplayName("HhaExchangeBatchSubmitRequest")
    class HhaExchangeBatchSubmitRequestTests {

        @Test
        @DisplayName("builder sets record IDs list")
        void builderSetsRecordIds() {
            HhaExchangeBatchSubmitRequest req = HhaExchangeBatchSubmitRequest.builder()
                    .recordIds(List.of(1L, 2L, 3L))
                    .build();
            assertEquals(3, req.getRecordIds().size());
            assertEquals(1L, req.getRecordIds().get(0));
        }

        @Test
        @DisplayName("single record ID")
        void singleRecordId() {
            HhaExchangeBatchSubmitRequest req = HhaExchangeBatchSubmitRequest.builder()
                    .recordIds(List.of(42L))
                    .build();
            assertEquals(1, req.getRecordIds().size());
        }

        @Test
        @DisplayName("no-arg constructor creates null list")
        void noArgConstructor() {
            HhaExchangeBatchSubmitRequest req = new HhaExchangeBatchSubmitRequest();
            assertNull(req.getRecordIds());
        }
    }

    @Nested
    @DisplayName("NoGpsReason enum")
    class NoGpsReasonTests {

        @Test
        @DisplayName("has 7 values")
        void has7Values() {
            assertEquals(7, NoGpsReason.values().length);
        }

        @Test
        @DisplayName("contains GPS_SERVICE_DISABLED")
        void containsGpsDisabled() {
            assertNotNull(NoGpsReason.valueOf("GPS_SERVICE_DISABLED"));
        }

        @Test
        @DisplayName("contains PERMISSION_DENIED")
        void containsPermissionDenied() {
            assertNotNull(NoGpsReason.valueOf("PERMISSION_DENIED"));
        }

        @Test
        @DisplayName("contains GPS_TIMEOUT")
        void containsGpsTimeout() {
            assertNotNull(NoGpsReason.valueOf("GPS_TIMEOUT"));
        }

        @Test
        @DisplayName("contains INDOOR_LOCATION")
        void containsIndoor() {
            assertNotNull(NoGpsReason.valueOf("INDOOR_LOCATION"));
        }

        @Test
        @DisplayName("contains COMMUNITY_VISIT")
        void containsCommunityVisit() {
            assertNotNull(NoGpsReason.valueOf("COMMUNITY_VISIT"));
        }

        @Test
        @DisplayName("contains HOME_VISIT_ADDRESS_USED")
        void containsHomeVisit() {
            assertNotNull(NoGpsReason.valueOf("HOME_VISIT_ADDRESS_USED"));
        }

        @Test
        @DisplayName("contains OTHER")
        void containsOther() {
            assertNotNull(NoGpsReason.valueOf("OTHER"));
        }

        @Test
        @DisplayName("invalid value throws IllegalArgumentException")
        void invalidValueThrows() {
            assertThrows(IllegalArgumentException.class, () ->
                    NoGpsReason.valueOf("INVALID_REASON"));
        }
    }
}
