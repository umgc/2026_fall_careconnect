package com.careconnect.service.evv;

import com.careconnect.dto.evv.EvvLocationRequest;
import com.careconnect.dto.evv.EvvLocationResponse;
import com.careconnect.exception.AppException;
import com.careconnect.model.Address;
import com.careconnect.model.Patient;
import com.careconnect.model.evv.EvvLocationRole;
import com.careconnect.model.evv.EvvLocationType;
import com.careconnect.model.evv.NoGpsReason;
import com.careconnect.model.evv.EvvRecord;
import com.careconnect.model.evv.EvvRecordLocation;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.evv.EvvRecordLocationRepository;
import com.careconnect.repository.evv.EvvRecordRepository;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.math.BigDecimal;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class EvvLocationServiceTest {

    @Mock
    private EvvRecordLocationRepository locationRepository;

    @Mock
    private EvvRecordRepository evvRecordRepository;

    @Mock
    private PatientRepository patientRepository;

    @InjectMocks
    private EvvLocationService evvLocationService;

    // =========== saveLocation tests ===========

    @Test
    void saveLocation_evvRecordNotFound_throwsAppException() throws Exception {
        final EvvLocationRequest request = EvvLocationRequest.builder()
                .evvRecordId(99L)
                .role(EvvLocationRole.CHECK_IN)
                .type(EvvLocationType.GPS)
                .coords(EvvLocationRequest.CoordinatesDto.builder()
                        .lat(BigDecimal.valueOf(38.9))
                        .lng(BigDecimal.valueOf(-77.0))
                        .build())
                .build();

        when(evvRecordRepository.findById(99L)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> evvLocationService.saveLocation(request))
                .isInstanceOf(AppException.class)
                .hasMessageContaining("EVV record not found");
    }

    @Test
    void saveLocation_GPS_withCoords_newLocation_savesAndReturnsResponse() throws Exception {
        final EvvRecord evvRecord = EvvRecord.builder()
                .id(1L)
                .serviceType("HOME_HEALTH")
                .individualName("John Doe")
                .caregiverId(10L)
                .status("UNDER_REVIEW")
                .stateCode("DC")
                .isOffline(false)
                .eorApprovalRequired(false)
                .isCorrected(false)
                .createdAt(OffsetDateTime.now())
                .updatedAt(OffsetDateTime.now())
                .build();

        final EvvLocationRequest request = EvvLocationRequest.builder()
                .evvRecordId(1L)
                .role(EvvLocationRole.CHECK_IN)
                .type(EvvLocationType.GPS)
                .coords(EvvLocationRequest.CoordinatesDto.builder()
                        .lat(BigDecimal.valueOf(38.9072))
                        .lng(BigDecimal.valueOf(-77.0369))
                        .accuracyM(BigDecimal.valueOf(5.0))
                        .build())
                .build();

        when(evvRecordRepository.findById(1L)).thenReturn(Optional.of(evvRecord));
        when(locationRepository.findByEvvRecordIdAndRole(1L, EvvLocationRole.CHECK_IN))
                .thenReturn(Optional.empty());

        final UUID locationId = UUID.randomUUID();
        final EvvRecordLocation savedLocation = EvvRecordLocation.builder()
                .id(locationId)
                .evvRecordId(1L)
                .role(EvvLocationRole.CHECK_IN)
                .type(EvvLocationType.GPS)
                .latitude(BigDecimal.valueOf(38.9072))
                .longitude(BigDecimal.valueOf(-77.0369))
                .accuracyM(BigDecimal.valueOf(5.0))
                .createdAt(OffsetDateTime.now())
                .build();

        when(locationRepository.save(any(EvvRecordLocation.class))).thenReturn(savedLocation);

        final EvvLocationResponse response = evvLocationService.saveLocation(request);

        assertThat(response).isNotNull();
        assertThat(response.getEvvRecordId()).isEqualTo(1L);
        assertThat(response.getRole()).isEqualTo(EvvLocationRole.CHECK_IN);
        assertThat(response.getType()).isEqualTo(EvvLocationType.GPS);
    }

    @Test
    void saveLocation_GPS_withCoords_existingLocation_updatesAndReturnsResponse() throws Exception {
        final EvvRecord evvRecord = EvvRecord.builder()
                .id(1L)
                .serviceType("HOME_HEALTH")
                .individualName("John Doe")
                .caregiverId(10L)
                .status("UNDER_REVIEW")
                .stateCode("DC")
                .isOffline(false)
                .eorApprovalRequired(false)
                .isCorrected(false)
                .createdAt(OffsetDateTime.now())
                .updatedAt(OffsetDateTime.now())
                .build();

        final EvvLocationRequest request = EvvLocationRequest.builder()
                .evvRecordId(1L)
                .role(EvvLocationRole.CHECK_IN)
                .type(EvvLocationType.GPS)
                .coords(EvvLocationRequest.CoordinatesDto.builder()
                        .lat(BigDecimal.valueOf(38.9072))
                        .lng(BigDecimal.valueOf(-77.0369))
                        .build())
                .build();

        final EvvRecordLocation existingLocation = EvvRecordLocation.builder()
                .id(UUID.randomUUID())
                .evvRecordId(1L)
                .role(EvvLocationRole.CHECK_IN)
                .type(EvvLocationType.GPS)
                .latitude(BigDecimal.valueOf(38.0))
                .longitude(BigDecimal.valueOf(-77.0))
                .createdAt(OffsetDateTime.now())
                .build();

        when(evvRecordRepository.findById(1L)).thenReturn(Optional.of(evvRecord));
        when(locationRepository.findByEvvRecordIdAndRole(1L, EvvLocationRole.CHECK_IN))
                .thenReturn(Optional.of(existingLocation));

        final EvvRecordLocation updatedLocation = EvvRecordLocation.builder()
                .id(existingLocation.getId())
                .evvRecordId(1L)
                .role(EvvLocationRole.CHECK_IN)
                .type(EvvLocationType.GPS)
                .latitude(BigDecimal.valueOf(38.9072))
                .longitude(BigDecimal.valueOf(-77.0369))
                .createdAt(OffsetDateTime.now())
                .build();

        when(locationRepository.save(any(EvvRecordLocation.class))).thenReturn(updatedLocation);

        final EvvLocationResponse response = evvLocationService.saveLocation(request);

        assertThat(response).isNotNull();
        verify(locationRepository).save(any(EvvRecordLocation.class));
    }

    @Test
    void saveLocation_PATIENT_ADDRESS_patientNull_throwsAppException() throws Exception {
        final EvvRecord evvRecord = EvvRecord.builder()
                .id(1L)
                .serviceType("HOME_HEALTH")
                .individualName("Jane Doe")
                .caregiverId(10L)
                .status("UNDER_REVIEW")
                .stateCode("DC")
                .isOffline(false)
                .eorApprovalRequired(false)
                .isCorrected(false)
                .patient(null)
                .createdAt(OffsetDateTime.now())
                .updatedAt(OffsetDateTime.now())
                .build();

        final EvvLocationRequest request = EvvLocationRequest.builder()
                .evvRecordId(1L)
                .role(EvvLocationRole.CHECK_IN)
                .type(EvvLocationType.PATIENT_ADDRESS)
                .noGpsReason(NoGpsReason.HOME_VISIT_ADDRESS_USED)
                .build();

        when(evvRecordRepository.findById(1L)).thenReturn(Optional.of(evvRecord));
        when(locationRepository.findByEvvRecordIdAndRole(1L, EvvLocationRole.CHECK_IN))
                .thenReturn(Optional.empty());

        assertThatThrownBy(() -> evvLocationService.saveLocation(request))
                .isInstanceOf(AppException.class)
                .hasMessageContaining("does not have an associated patient");
    }

    @Test
    void saveLocation_PATIENT_ADDRESS_patientAddressNull_throwsAppException() throws Exception {
        final Patient patient = Patient.builder()
                .id(5L)
                .firstName("Jane")
                .lastName("Doe")
                .address(null)
                .build();

        final EvvRecord evvRecord = EvvRecord.builder()
                .id(1L)
                .serviceType("HOME_HEALTH")
                .individualName("Jane Doe")
                .caregiverId(10L)
                .status("UNDER_REVIEW")
                .stateCode("DC")
                .isOffline(false)
                .eorApprovalRequired(false)
                .isCorrected(false)
                .patient(patient)
                .createdAt(OffsetDateTime.now())
                .updatedAt(OffsetDateTime.now())
                .build();

        final EvvLocationRequest request = EvvLocationRequest.builder()
                .evvRecordId(1L)
                .role(EvvLocationRole.CHECK_IN)
                .type(EvvLocationType.PATIENT_ADDRESS)
                .noGpsReason(NoGpsReason.HOME_VISIT_ADDRESS_USED)
                .build();

        when(evvRecordRepository.findById(1L)).thenReturn(Optional.of(evvRecord));
        when(locationRepository.findByEvvRecordIdAndRole(1L, EvvLocationRole.CHECK_IN))
                .thenReturn(Optional.empty());

        assertThatThrownBy(() -> evvLocationService.saveLocation(request))
                .isInstanceOf(AppException.class)
                .hasMessageContaining("does not have an address on file");
    }

    @Test
    void saveLocation_PATIENT_ADDRESS_withAddress_savesAndReturnsResponse() throws Exception {
        final Address address = Address.builder()
                .line1("123 Main St")
                .line2("Apt 4")
                .city("Washington")
                .state("DC")
                .zip("20001")
                .build();

        final Patient patient = Patient.builder()
                .id(5L)
                .firstName("Jane")
                .lastName("Doe")
                .address(address)
                .build();

        final EvvRecord evvRecord = EvvRecord.builder()
                .id(1L)
                .serviceType("HOME_HEALTH")
                .individualName("Jane Doe")
                .caregiverId(10L)
                .status("UNDER_REVIEW")
                .stateCode("DC")
                .isOffline(false)
                .eorApprovalRequired(false)
                .isCorrected(false)
                .patient(patient)
                .createdAt(OffsetDateTime.now())
                .updatedAt(OffsetDateTime.now())
                .build();

        final EvvLocationRequest request = EvvLocationRequest.builder()
                .evvRecordId(1L)
                .role(EvvLocationRole.CHECK_IN)
                .type(EvvLocationType.PATIENT_ADDRESS)
                .noGpsReason(NoGpsReason.HOME_VISIT_ADDRESS_USED)
                .build();

        when(evvRecordRepository.findById(1L)).thenReturn(Optional.of(evvRecord));
        when(locationRepository.findByEvvRecordIdAndRole(1L, EvvLocationRole.CHECK_IN))
                .thenReturn(Optional.empty());

        final EvvRecordLocation savedLocation = EvvRecordLocation.builder()
                .id(UUID.randomUUID())
                .evvRecordId(1L)
                .role(EvvLocationRole.CHECK_IN)
                .type(EvvLocationType.PATIENT_ADDRESS)
                .addressSnapshotJson(java.util.Map.of("line1", "123 Main St", "city", "Washington"))
                .noGpsReason(NoGpsReason.HOME_VISIT_ADDRESS_USED)
                .createdAt(OffsetDateTime.now())
                .build();

        when(locationRepository.save(any(EvvRecordLocation.class))).thenReturn(savedLocation);

        final EvvLocationResponse response = evvLocationService.saveLocation(request);

        assertThat(response).isNotNull();
        assertThat(response.getType()).isEqualTo(EvvLocationType.PATIENT_ADDRESS);
    }

    // NOTE: EvvLocationService's own GPS-missing-coords (lines 63-68) and
    // MANUAL-missing-address (lines 111-114) guard clauses are unreachable
    // through saveLocation()'s public API: request.validate() (line 37) is
    // called first and throws IllegalArgumentException for the identical
    // condition before these re-checks could ever run. That branch coverage
    // gap is a documented, accepted dead-code finding (see EvvLocationRequestTest
    // for direct coverage of request.validate()'s own GPS/MANUAL branches).

    @Test
    void saveLocation_MANUAL_withAddress_savesAndReturnsResponse() throws Exception {
        final EvvRecord evvRecord = EvvRecord.builder().id(1L).build();

        final EvvLocationRequest request = EvvLocationRequest.builder()
                .evvRecordId(1L)
                .role(EvvLocationRole.CHECK_IN)
                .type(EvvLocationType.MANUAL)
                .manualAddress("123 Community Center Dr")
                .noGpsReason(NoGpsReason.COMMUNITY_VISIT)
                .build();

        when(evvRecordRepository.findById(1L)).thenReturn(Optional.of(evvRecord));
        when(locationRepository.findByEvvRecordIdAndRole(1L, EvvLocationRole.CHECK_IN))
                .thenReturn(Optional.empty());

        final EvvRecordLocation savedLocation = EvvRecordLocation.builder()
                .id(UUID.randomUUID())
                .evvRecordId(1L)
                .role(EvvLocationRole.CHECK_IN)
                .type(EvvLocationType.MANUAL)
                .manualAddress("123 Community Center Dr")
                .noGpsReason(NoGpsReason.COMMUNITY_VISIT)
                .createdAt(OffsetDateTime.now())
                .build();

        when(locationRepository.save(any(EvvRecordLocation.class))).thenReturn(savedLocation);

        final EvvLocationResponse response = evvLocationService.saveLocation(request);

        assertThat(response).isNotNull();
        assertThat(response.getType()).isEqualTo(EvvLocationType.MANUAL);
        assertThat(response.getManualAddress()).isEqualTo("123 Community Center Dr");
    }

    @Test
    void saveLocation_nullType_skipsTypeSpecificHandlingAndSaves() throws Exception {
        // Arrange: request.validate() and location.validate() both no-op when
        // type is null, so the if/else-if chain in saveLocation falls through
        // entirely (reachable, since EvvLocationRequest permits a null type).
        final EvvRecord evvRecord = EvvRecord.builder().id(1L).build();

        final EvvLocationRequest request = EvvLocationRequest.builder()
                .evvRecordId(1L)
                .role(EvvLocationRole.CHECK_IN)
                .type(null)
                .build();

        when(evvRecordRepository.findById(1L)).thenReturn(Optional.of(evvRecord));
        when(locationRepository.findByEvvRecordIdAndRole(1L, EvvLocationRole.CHECK_IN))
                .thenReturn(Optional.empty());

        final EvvRecordLocation savedLocation = EvvRecordLocation.builder()
                .id(UUID.randomUUID())
                .evvRecordId(1L)
                .role(EvvLocationRole.CHECK_IN)
                .type(null)
                .createdAt(OffsetDateTime.now())
                .build();

        when(locationRepository.save(any(EvvRecordLocation.class))).thenReturn(savedLocation);

        final EvvLocationResponse response = evvLocationService.saveLocation(request);

        assertThat(response).isNotNull();
        assertThat(response.getType()).isNull();
    }

    // =========== getLocationsForRecord tests ===========

    @Test
    void getLocationsForRecord_recordNotFound_throwsAppException() throws Exception {
        when(evvRecordRepository.existsById(99L)).thenReturn(false);

        assertThatThrownBy(() -> evvLocationService.getLocationsForRecord(99L))
                .isInstanceOf(AppException.class)
                .hasMessageContaining("EVV record not found");
    }

    @Test
    void getLocationsForRecord_found_returnsMappedList() throws Exception {
        when(evvRecordRepository.existsById(1L)).thenReturn(true);

        final EvvRecordLocation location = EvvRecordLocation.builder()
                .id(UUID.randomUUID())
                .evvRecordId(1L)
                .role(EvvLocationRole.CHECK_IN)
                .type(EvvLocationType.GPS)
                .latitude(BigDecimal.valueOf(38.9072))
                .longitude(BigDecimal.valueOf(-77.0369))
                .createdAt(OffsetDateTime.now())
                .build();

        when(locationRepository.findByEvvRecordId(1L)).thenReturn(List.of(location));

        final List<EvvLocationResponse> responses = evvLocationService.getLocationsForRecord(1L);

        assertThat(responses).hasSize(1);
        assertThat(responses.get(0).getRole()).isEqualTo(EvvLocationRole.CHECK_IN);
    }

    // =========== getLocationByRole tests ===========

    @Test
    void getLocationByRole_notFound_throwsAppException() throws Exception {
        when(locationRepository.findByEvvRecordIdAndRole(1L, EvvLocationRole.CHECK_IN))
                .thenReturn(Optional.empty());

        assertThatThrownBy(() -> evvLocationService.getLocationByRole(1L, EvvLocationRole.CHECK_IN))
                .isInstanceOf(AppException.class)
                .hasMessageContaining("Location not found");
    }

    @Test
    void getLocationByRole_found_returnsResponse() throws Exception {
        final EvvRecordLocation location = EvvRecordLocation.builder()
                .id(UUID.randomUUID())
                .evvRecordId(1L)
                .role(EvvLocationRole.CHECK_IN)
                .type(EvvLocationType.GPS)
                .latitude(BigDecimal.valueOf(38.9))
                .longitude(BigDecimal.valueOf(-77.0))
                .createdAt(OffsetDateTime.now())
                .build();

        when(locationRepository.findByEvvRecordIdAndRole(1L, EvvLocationRole.CHECK_IN))
                .thenReturn(Optional.of(location));

        final EvvLocationResponse response = evvLocationService.getLocationByRole(1L, EvvLocationRole.CHECK_IN);

        assertThat(response).isNotNull();
        assertThat(response.getRole()).isEqualTo(EvvLocationRole.CHECK_IN);
        assertThat(response.getType()).isEqualTo(EvvLocationType.GPS);
    }

    // =========== deleteLocation tests ===========

    @Test
    void deleteLocation_notFound_throwsAppException() throws Exception {
        when(locationRepository.existsByEvvRecordIdAndRole(1L, EvvLocationRole.CHECK_OUT))
                .thenReturn(false);

        assertThatThrownBy(() -> evvLocationService.deleteLocation(1L, EvvLocationRole.CHECK_OUT))
                .isInstanceOf(AppException.class)
                .hasMessageContaining("Location not found");
    }

    @Test
    void deleteLocation_found_deletesSuccessfully() throws Exception {
        when(locationRepository.existsByEvvRecordIdAndRole(1L, EvvLocationRole.CHECK_OUT))
                .thenReturn(true);
        doNothing().when(locationRepository).deleteByEvvRecordIdAndRole(1L, EvvLocationRole.CHECK_OUT);

        evvLocationService.deleteLocation(1L, EvvLocationRole.CHECK_OUT);

        verify(locationRepository).deleteByEvvRecordIdAndRole(1L, EvvLocationRole.CHECK_OUT);
    }
}
