package com.careconnect.service.evv;

import com.careconnect.dto.evv.EvvLocationRequest;
import com.careconnect.dto.evv.EvvLocationResponse;
import com.careconnect.exception.AppException;
import com.careconnect.model.Patient;
import com.careconnect.model.evv.EvvRecord;
import com.careconnect.model.evv.EvvRecordLocation;
import com.careconnect.model.evv.EvvLocationRole;
import com.careconnect.model.evv.EvvLocationType;
import com.careconnect.repository.evv.EvvRecordLocationRepository;
import com.careconnect.repository.evv.EvvRecordRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
public class EvvLocationService {

    private final EvvRecordLocationRepository locationRepository;
    private final EvvRecordRepository evvRecordRepository;

    /**
     * Save or update an EVV location (upsert logic)
     * If a location already exists for the given (evvRecordId, role), it will be updated
     */
    @Transactional
    public EvvLocationResponse saveLocation(EvvLocationRequest request) {
        // Validate request
        request.validate();

        // Verify EVV record exists
        EvvRecord evvRecord = evvRecordRepository.findById(request.getEvvRecordId())
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND,
                        "EVV record not found with ID: " + request.getEvvRecordId()));

        // Check if location already exists (upsert logic)
        EvvRecordLocation location = locationRepository
                .findByEvvRecordIdAndRole(request.getEvvRecordId(), request.getRole())
                .orElse(null);

        if (location == null) {
            // Create new location
            location = EvvRecordLocation.builder()
                    .evvRecordId(request.getEvvRecordId())
                    .role(request.getRole())
                    .build();
        }

        // Set location type
        location.setType(request.getType());

        // Handle based on location type
        if (request.getType() == EvvLocationType.GPS) {
            // Validate GPS coordinates are provided
            if (request.getCoords() == null ||
                    request.getCoords().getLat() == null ||
                    request.getCoords().getLng() == null) {
                throw new AppException(HttpStatus.BAD_REQUEST,
                        "GPS location requires latitude and longitude coordinates");
            }

            // Set GPS coordinates
            location.setLatitude(request.getCoords().getLat());
            location.setLongitude(request.getCoords().getLng());
            location.setAccuracyM(request.getCoords().getAccuracyM());
            location.setAddressSnapshotJson(null);
            location.setNoGpsReason(null);
            location.setManualAddress(null);

        } else if (request.getType() == EvvLocationType.PATIENT_ADDRESS) {
            // Get patient from EVV record
            Patient patient = evvRecord.getPatient();
            if (patient == null) {
                throw new AppException(HttpStatus.BAD_REQUEST,
                        "EVV record does not have an associated patient");
            }

            // Create address snapshot
            Map<String, Object> addressSnapshot = new HashMap<>();
            if (patient.getAddress() != null) {
                addressSnapshot.put("line1", patient.getAddress().getLine1());
                addressSnapshot.put("line2", patient.getAddress().getLine2());
                addressSnapshot.put("city", patient.getAddress().getCity());
                addressSnapshot.put("state", patient.getAddress().getState());
                addressSnapshot.put("postalCode", patient.getAddress().getZip());
                addressSnapshot.put("country", "US");
            } else {
                throw new AppException(HttpStatus.BAD_REQUEST,
                        "Patient does not have an address on file");
            }

            // Set address snapshot and clear GPS/manual fields
            location.setAddressSnapshotJson(addressSnapshot);
            location.setLatitude(null);
            location.setLongitude(null);
            location.setAccuracyM(null);
            location.setManualAddress(null);
            // Federal EVV: store reason GPS was not used
            location.setNoGpsReason(request.getNoGpsReason());

        } else if (request.getType() == EvvLocationType.MANUAL) {
            // MANUAL type: caregiver-entered address (e.g. community or facility visit)
            if (request.getManualAddress() == null || request.getManualAddress().isBlank()) {
                throw new AppException(HttpStatus.BAD_REQUEST,
                        "MANUAL location requires a manualAddress");
            }
            location.setManualAddress(request.getManualAddress());
            location.setAddressSnapshotJson(null);
            location.setLatitude(null);
            location.setLongitude(null);
            location.setAccuracyM(null);
            // Federal EVV: store reason GPS was not used
            location.setNoGpsReason(request.getNoGpsReason());
        }

        // Validate before saving
        location.validate();

        // Save and return
        EvvRecordLocation saved = locationRepository.save(location);
        return toResponse(saved);
    }

    /**
     * Get all locations for an EVV record
     */
    @Transactional(readOnly = true)
    public List<EvvLocationResponse> getLocationsForRecord(Long evvRecordId) {
        // Verify EVV record exists
        if (!evvRecordRepository.existsById(evvRecordId)) {
            throw new AppException(HttpStatus.NOT_FOUND,
                    "EVV record not found with ID: " + evvRecordId);
        }

        List<EvvRecordLocation> locations = locationRepository.findByEvvRecordId(evvRecordId);
        return locations.stream()
                .map(this::toResponse)
                .collect(Collectors.toList());
    }

    /**
     * Get a specific location by role
     */
    @Transactional(readOnly = true)
    public EvvLocationResponse getLocationByRole(Long evvRecordId, EvvLocationRole role) {
        return locationRepository.findByEvvRecordIdAndRole(evvRecordId, role)
                .map(this::toResponse)
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND,
                        "Location not found for EVV record " + evvRecordId + " with role " + role));
    }

    /**
     * Delete a location
     */
    @Transactional
    public void deleteLocation(Long evvRecordId, EvvLocationRole role) {
        if (!locationRepository.existsByEvvRecordIdAndRole(evvRecordId, role)) {
            throw new AppException(HttpStatus.NOT_FOUND,
                    "Location not found for EVV record " + evvRecordId + " with role " + role);
        }
        locationRepository.deleteByEvvRecordIdAndRole(evvRecordId, role);
    }

    /**
     * Convert entity to response DTO
     */
    private EvvLocationResponse toResponse(EvvRecordLocation location) {
        return EvvLocationResponse.builder()
                .id(location.getId())
                .evvRecordId(location.getEvvRecordId())
                .role(location.getRole())
                .type(location.getType())
                .latitude(location.getLatitude())
                .longitude(location.getLongitude())
                .accuracyM(location.getAccuracyM())
                .addressSnapshot(location.getAddressSnapshotJson())
                .noGpsReason(location.getNoGpsReason())
                .manualAddress(location.getManualAddress())
                .createdAt(location.getCreatedAt())
                .build();
    }
}

