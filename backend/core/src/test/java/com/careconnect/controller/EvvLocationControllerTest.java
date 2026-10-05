package com.careconnect.controller;

import com.careconnect.dto.evv.EvvLocationRequest;
import com.careconnect.dto.evv.EvvLocationResponse;
import com.careconnect.model.evv.EvvLocationRole;
import com.careconnect.model.evv.EvvLocationType;
import com.careconnect.model.evv.NoGpsReason;
import com.careconnect.security.AuthorizationService;
import com.careconnect.service.evv.EvvLocationService;
import com.careconnect.util.SecurityUtil;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;

import java.math.BigDecimal;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class EvvLocationControllerTest {

    private static final Long EVV_RECORD_ID = 10L;
    @Mock
    private EvvLocationService locationService;
    @Mock
    private SecurityUtil securityUtil;
    @Mock
    private AuthorizationService authorizationService;

    // ── shared constants ──────────────────────────────────────────────────────
    @InjectMocks
    private EvvLocationController controller;

    // ── shared helpers ────────────────────────────────────────────────────────

    /**
     * PATIENT_ADDRESS type — validate() passes without coords but needs noGpsReason.
     */
    private EvvLocationRequest patientAddressRequest() throws Exception {
        return EvvLocationRequest.builder()
                .evvRecordId(EVV_RECORD_ID)
                .role(EvvLocationRole.CHECK_IN)
                .type(EvvLocationType.PATIENT_ADDRESS)
                .noGpsReason(NoGpsReason.HOME_VISIT_ADDRESS_USED)
                .build();
    }

    /**
     * GPS type with fully-populated coords — validate() passes.
     */
    private EvvLocationRequest gpsRequestWithValidCoords() throws Exception {
        final EvvLocationRequest.CoordinatesDto coords = EvvLocationRequest.CoordinatesDto.builder()
                .lat(new BigDecimal("38.9072"))
                .lng(new BigDecimal("-77.0369"))
                .accuracyM(new BigDecimal("5.0"))
                .build();
        return EvvLocationRequest.builder()
                .evvRecordId(EVV_RECORD_ID)
                .role(EvvLocationRole.CHECK_OUT)
                .type(EvvLocationType.GPS)
                .coords(coords)
                .build();
    }

    // ── POST /v1/api/evv/locations ────────────────────────────────────────────

    @Nested
    class SaveLocation {

        // ── happy path: PATIENT_ADDRESS (no coords required) ─────────────────

        @Test
        void returns200_whenPatientAddressType() throws Exception {
            final EvvLocationRequest request = patientAddressRequest();
            when(locationService.saveLocation(request)).thenReturn(new EvvLocationResponse());

            final ResponseEntity<EvvLocationResponse> result = controller.saveLocation(request);

            assertThat(result.getStatusCode()).isEqualTo(HttpStatus.OK);
        }

        @Test
        void returnsServiceResult_whenPatientAddressType() throws Exception {
            final EvvLocationRequest request = patientAddressRequest();
            final EvvLocationResponse locationResponse = EvvLocationResponse.builder()
                    .evvRecordId(EVV_RECORD_ID)
                    .role(EvvLocationRole.CHECK_IN)
                    .build();
            when(locationService.saveLocation(request)).thenReturn(locationResponse);

            final ResponseEntity<EvvLocationResponse> result = controller.saveLocation(request);

            assertThat(result.getBody()).isSameAs(locationResponse);
        }

        @Test
        void callsServiceWithRequest_whenPatientAddressType() throws Exception {
            final EvvLocationRequest request = patientAddressRequest();
            when(locationService.saveLocation(request)).thenReturn(new EvvLocationResponse());

            controller.saveLocation(request);

            verify(locationService).saveLocation(request);
        }

        // ── happy path: GPS with valid coords ────────────────────────────────

        @Test
        void returns200_whenGpsTypeWithValidCoords() throws Exception {
            final EvvLocationRequest request = gpsRequestWithValidCoords();
            when(locationService.saveLocation(request)).thenReturn(new EvvLocationResponse());

            final ResponseEntity<EvvLocationResponse> result = controller.saveLocation(request);

            assertThat(result.getStatusCode()).isEqualTo(HttpStatus.OK);
        }

        @Test
        void callsServiceWithRequest_whenGpsTypeWithValidCoords() throws Exception {
            final EvvLocationRequest request = gpsRequestWithValidCoords();
            when(locationService.saveLocation(request)).thenReturn(new EvvLocationResponse());

            controller.saveLocation(request);

            verify(locationService).saveLocation(request);
        }

        // ── validation failures: GPS type without sufficient coords ───────────
        // validate() is called directly on the request before the service;
        // there is no try-catch in the controller, so the exception propagates.

        @Test
        void throwsIllegalArgumentException_whenGpsTypeAndCoordsIsNull() throws Exception {
            final EvvLocationRequest request = EvvLocationRequest.builder()
                    .evvRecordId(EVV_RECORD_ID)
                    .role(EvvLocationRole.CHECK_IN)
                    .type(EvvLocationType.GPS)
                    .coords(null)
                    .build();

            assertThatThrownBy(() -> controller.saveLocation(request))
                    .isInstanceOf(IllegalArgumentException.class)
                    .hasMessage("GPS location requires coordinates");
        }

        @Test
        void throwsIllegalArgumentException_whenGpsTypeAndLatIsNull() throws Exception {
            final EvvLocationRequest.CoordinatesDto noLat = EvvLocationRequest.CoordinatesDto.builder()
                    .lat(null)
                    .lng(new BigDecimal("-77.0369"))
                    .build();
            final EvvLocationRequest request = EvvLocationRequest.builder()
                    .evvRecordId(EVV_RECORD_ID)
                    .role(EvvLocationRole.CHECK_IN)
                    .type(EvvLocationType.GPS)
                    .coords(noLat)
                    .build();

            assertThatThrownBy(() -> controller.saveLocation(request))
                    .isInstanceOf(IllegalArgumentException.class)
                    .hasMessage("GPS location requires coordinates");
        }

        @Test
        void throwsIllegalArgumentException_whenGpsTypeAndLngIsNull() throws Exception {
            final EvvLocationRequest.CoordinatesDto noLng = EvvLocationRequest.CoordinatesDto.builder()
                    .lat(new BigDecimal("38.9072"))
                    .lng(null)
                    .build();
            final EvvLocationRequest request = EvvLocationRequest.builder()
                    .evvRecordId(EVV_RECORD_ID)
                    .role(EvvLocationRole.CHECK_IN)
                    .type(EvvLocationType.GPS)
                    .coords(noLng)
                    .build();

            assertThatThrownBy(() -> controller.saveLocation(request))
                    .isInstanceOf(IllegalArgumentException.class)
                    .hasMessage("GPS location requires coordinates");
        }

        @Test
        void doesNotCallService_whenValidationFails() throws Exception {
            final EvvLocationRequest request = EvvLocationRequest.builder()
                    .evvRecordId(EVV_RECORD_ID)
                    .role(EvvLocationRole.CHECK_IN)
                    .type(EvvLocationType.GPS)
                    .coords(null)
                    .build();

            try {
                controller.saveLocation(request);
            } catch (IllegalArgumentException ignored) {
            }

            verifyNoInteractions(locationService);
        }
    }

    // ── GET /v1/api/evv/locations/records/{evvRecordId} ───────────────────────

    @Nested
    class GetLocationsForRecord {

        @Test
        void returns200() throws Exception {
            when(locationService.getLocationsForRecord(EVV_RECORD_ID)).thenReturn(List.of());

            final ResponseEntity<List<EvvLocationResponse>> response =
                    controller.getLocationsForRecord(EVV_RECORD_ID);

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        }

        @Test
        void returnsListFromService() throws Exception {
            final EvvLocationResponse loc = new EvvLocationResponse();
            when(locationService.getLocationsForRecord(EVV_RECORD_ID)).thenReturn(List.of(loc));

            final ResponseEntity<List<EvvLocationResponse>> response =
                    controller.getLocationsForRecord(EVV_RECORD_ID);

            assertThat(response.getBody()).containsExactly(loc);
        }

        @Test
        void returnsEmptyList_whenNoLocationsExist() throws Exception {
            when(locationService.getLocationsForRecord(EVV_RECORD_ID)).thenReturn(List.of());

            final ResponseEntity<List<EvvLocationResponse>> response =
                    controller.getLocationsForRecord(EVV_RECORD_ID);

            assertThat(response.getBody()).isEmpty();
        }

        @Test
        void callsServiceWithEvvRecordId() throws Exception {
            when(locationService.getLocationsForRecord(EVV_RECORD_ID)).thenReturn(List.of());

            controller.getLocationsForRecord(EVV_RECORD_ID);

            verify(locationService).getLocationsForRecord(EVV_RECORD_ID);
        }
    }

    // ── GET /v1/api/evv/locations/records/{evvRecordId}/{role} ────────────────

    @Nested
    class GetLocationByRole {

        @Test
        void returns200_forCheckIn() throws Exception {
            when(locationService.getLocationByRole(EVV_RECORD_ID, EvvLocationRole.CHECK_IN))
                    .thenReturn(new EvvLocationResponse());

            final ResponseEntity<EvvLocationResponse> response =
                    controller.getLocationByRole(EVV_RECORD_ID, EvvLocationRole.CHECK_IN);

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        }

        @Test
        void returns200_forCheckOut() throws Exception {
            when(locationService.getLocationByRole(EVV_RECORD_ID, EvvLocationRole.CHECK_OUT))
                    .thenReturn(new EvvLocationResponse());

            final ResponseEntity<EvvLocationResponse> response =
                    controller.getLocationByRole(EVV_RECORD_ID, EvvLocationRole.CHECK_OUT);

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        }

        @Test
        void returnsServiceResult_forCheckIn() throws Exception {
            final EvvLocationResponse locationResponse = EvvLocationResponse.builder()
                    .evvRecordId(EVV_RECORD_ID)
                    .role(EvvLocationRole.CHECK_IN)
                    .build();
            when(locationService.getLocationByRole(EVV_RECORD_ID, EvvLocationRole.CHECK_IN))
                    .thenReturn(locationResponse);

            final ResponseEntity<EvvLocationResponse> response =
                    controller.getLocationByRole(EVV_RECORD_ID, EvvLocationRole.CHECK_IN);

            assertThat(response.getBody()).isSameAs(locationResponse);
        }

        @Test
        void returnsServiceResult_forCheckOut() throws Exception {
            final EvvLocationResponse locationResponse = EvvLocationResponse.builder()
                    .evvRecordId(EVV_RECORD_ID)
                    .role(EvvLocationRole.CHECK_OUT)
                    .build();
            when(locationService.getLocationByRole(EVV_RECORD_ID, EvvLocationRole.CHECK_OUT))
                    .thenReturn(locationResponse);

            final ResponseEntity<EvvLocationResponse> response =
                    controller.getLocationByRole(EVV_RECORD_ID, EvvLocationRole.CHECK_OUT);

            assertThat(response.getBody()).isSameAs(locationResponse);
        }

        @Test
        void callsServiceWithCorrectArguments_forCheckIn() throws Exception {
            when(locationService.getLocationByRole(EVV_RECORD_ID, EvvLocationRole.CHECK_IN))
                    .thenReturn(new EvvLocationResponse());

            controller.getLocationByRole(EVV_RECORD_ID, EvvLocationRole.CHECK_IN);

            verify(locationService).getLocationByRole(EVV_RECORD_ID, EvvLocationRole.CHECK_IN);
        }

        @Test
        void callsServiceWithCorrectArguments_forCheckOut() throws Exception {
            when(locationService.getLocationByRole(EVV_RECORD_ID, EvvLocationRole.CHECK_OUT))
                    .thenReturn(new EvvLocationResponse());

            controller.getLocationByRole(EVV_RECORD_ID, EvvLocationRole.CHECK_OUT);

            verify(locationService).getLocationByRole(EVV_RECORD_ID, EvvLocationRole.CHECK_OUT);
        }
    }

    // ── DELETE /v1/api/evv/locations/records/{evvRecordId}/{role} ─────────────

    @Nested
    class DeleteLocation {

        @Test
        void returns204NoContent_forCheckIn() throws Exception {
            final ResponseEntity<Void> response =
                    controller.deleteLocation(EVV_RECORD_ID, EvvLocationRole.CHECK_IN);

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.NO_CONTENT);
        }

        @Test
        void returns204NoContent_forCheckOut() throws Exception {
            final ResponseEntity<Void> response =
                    controller.deleteLocation(EVV_RECORD_ID, EvvLocationRole.CHECK_OUT);

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.NO_CONTENT);
        }

        @Test
        void bodyIsNull() throws Exception {
            final ResponseEntity<Void> response =
                    controller.deleteLocation(EVV_RECORD_ID, EvvLocationRole.CHECK_IN);

            assertThat(response.getBody()).isNull();
        }

        @Test
        void callsServiceWithCorrectArguments_forCheckIn() throws Exception {
            controller.deleteLocation(EVV_RECORD_ID, EvvLocationRole.CHECK_IN);

            verify(locationService).deleteLocation(EVV_RECORD_ID, EvvLocationRole.CHECK_IN);
        }

        @Test
        void callsServiceWithCorrectArguments_forCheckOut() throws Exception {
            controller.deleteLocation(EVV_RECORD_ID, EvvLocationRole.CHECK_OUT);

            verify(locationService).deleteLocation(EVV_RECORD_ID, EvvLocationRole.CHECK_OUT);
        }

        @Test
        void callsServiceExactlyOnce() throws Exception {
            controller.deleteLocation(EVV_RECORD_ID, EvvLocationRole.CHECK_IN);

            verify(locationService, times(1)).deleteLocation(any(), any());
        }
    }
}
