package com.careconnect.controller;

import com.careconnect.dto.*;
import com.careconnect.exception.AppException;
import com.careconnect.model.Caregiver;
import com.careconnect.model.Patient;
import com.careconnect.model.User;
import com.careconnect.repository.UserRepository;
import com.careconnect.security.Role;
import com.careconnect.service.*;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.data.domain.Page;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.bind.annotation.*;
import org.springframework.format.annotation.DateTimeFormat;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import io.swagger.v3.oas.annotations.media.Content;
import io.swagger.v3.oas.annotations.media.Schema;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.security.SecurityRequirement;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;

import java.time.Instant;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;
import java.util.Optional;

@RestController
@RequestMapping("/v1/api/patients")
@Tag(name = "Patient Management", description = "Patient management endpoints including mood & pain logging")
@SecurityRequirement(name = "Bearer Authentication")
public class PatientController {

    private static final Logger LOG = LoggerFactory.getLogger(PatientController.class);

    @Autowired
    private PatientService patientService;

    @Autowired
    private FamilyMemberService familyMemberService;

    @Autowired
    private CaregiverPatientLinkService caregiverPatientLinkService;

    @Autowired
    private UserRepository userRepository;

    @Autowired
    private MoodPainLogService moodPainLogService;

    @Autowired
    private MedicationService medicationService;

    @Autowired
    private PatientRiskService patientRiskService;

    // Helper method to get current user
    private User getCurrentUser() {
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        String userEmail = authentication.getName(); // JWT contains email as subject
        return userRepository.findByEmail(userEmail)
                .orElseThrow(() -> new AppException(HttpStatus.UNAUTHORIZED, "User not authenticated"));
    }

    // Helper method to check if user has access to patient
    private void validatePatientAccess(Long patientUserId, User currentUser) {
        LOG.debug("validatePatientAccess - patientUserId={}, currentUser: id={}, role={}",
                patientUserId, currentUser.getId(), currentUser.getRole());

        switch (currentUser.getRole()) {
            case PATIENT:
                // Patients can only access their own data
                LOG.debug("PATIENT role validation - checking if currentUser.id {} equals patientUserId {}",
                        currentUser.getId(), patientUserId);
                if (!currentUser.getId().equals(patientUserId)) {
                    LOG.warn("Access denied - Patient {} tried to access patient {}",
                            currentUser.getId(), patientUserId);
                    throw new AppException(HttpStatus.FORBIDDEN, "Access denied");
                }
                LOG.debug("Access granted - Patient accessing their own data");
                break;
            case CAREGIVER:
                // Caregivers can access patients they're linked to (ACTIVE and not expired)
                boolean caregiverHasAccess = caregiverPatientLinkService.hasAccessToPatient(currentUser.getId(), patientUserId);
                LOG.debug("CAREGIVER role validation - hasAccess={}", caregiverHasAccess);
                if (!caregiverHasAccess) {
                    LOG.warn("Access denied - Caregiver {} has no active link to patient {}",
                            currentUser.getId(), patientUserId);
                    throw new AppException(HttpStatus.FORBIDDEN, "Access denied");
                }
                LOG.debug("Access granted - Caregiver has active link to patient");
                break;
            case FAMILY_MEMBER:
                // Family members can access patients they're linked to (ACTIVE and not expired)
                boolean familyMemberHasAccess = familyMemberService.hasAccessToPatient(currentUser.getId(), patientUserId);
                LOG.debug("FAMILY_MEMBER role validation - hasAccess={}", familyMemberHasAccess);
                if (!familyMemberHasAccess) {
                    LOG.warn("Access denied - Family member {} has no active link to patient {}",
                            currentUser.getId(), patientUserId);
                    throw new AppException(HttpStatus.FORBIDDEN, "Access denied");
                }
                LOG.debug("Access granted - Family member has active link to patient");
                break;
            case ADMIN:
                // Admins can access all patients
                LOG.debug("ADMIN role - access granted");
                break;
            default:
                LOG.warn("Access denied - Invalid role: {}", currentUser.getRole());
                throw new AppException(HttpStatus.FORBIDDEN, "Access denied");
        }
    }

    // 1. List caregivers associated with a patient
    @GetMapping("/{patientId}/caregivers")
    public ResponseEntity<List<Caregiver>> getCaregiversByPatient(@PathVariable Long patientId) {
        User currentUser = getCurrentUser();

        // Convert patientId to userId for validation
        Patient patient = patientService.getPatientById(patientId);
        validatePatientAccess(patient.getUser().getId(), currentUser);

        List<Caregiver> caregivers = patientService.getCaregiversByPatient(patientId);
        return ResponseEntity.ok(caregivers);
    }

    // 2. Get patient details
    @GetMapping("/{patientId}")
    public ResponseEntity<Patient> getPatient(@PathVariable Long patientId) {
        User currentUser = getCurrentUser();

        // Get patient and validate access
        Patient patient = patientService.getPatientById(patientId);
        validatePatientAccess(patient.getUser().getId(), currentUser);

        return ResponseEntity.ok(patient);
    }

    @PutMapping("/{patientId}")
    public ResponseEntity<Patient> updatePatient(@PathVariable Long patientId, @RequestBody Patient updatedPatient) {
        User currentUser = getCurrentUser();
        // Family members have read-only access, cannot update
        if (currentUser.getRole() == Role.FAMILY_MEMBER) {
            throw new AppException(HttpStatus.FORBIDDEN, "Family members have read-only access");
        }

        // Validate access
        Patient patient = patientService.getPatientById(patientId);
        validatePatientAccess(patient.getUser().getId(), currentUser);

        Patient updatedResult = patientService.updatePatient(patientId, updatedPatient);
        return ResponseEntity.ok(updatedResult);
    }

    // --- Known Risks (client risk flags) ---
    @GetMapping("/{patientId}/risks")
    @Operation(summary = "Get flagged risks for a patient", description = "Returns all currently flagged risks for the patient (client)")
    @ApiResponses({
            @ApiResponse(responseCode = "200", description = "List of flagged risks"),
            @ApiResponse(responseCode = "403", description = "Access denied"),
            @ApiResponse(responseCode = "404", description = "Patient not found")
    })
    public ResponseEntity<List<PatientRiskResponseDto>> getPatientRisks(@PathVariable Long patientId) {
        User currentUser = getCurrentUser();
        Patient patient = patientService.getPatientById(patientId);
        validatePatientAccess(patient.getUser().getId(), currentUser);
        List<PatientRiskResponseDto> list = patientRiskService.getFlaggedRisksForPatient(patientId).stream()
                .map(PatientRiskResponseDto::from)
                .toList();
        return ResponseEntity.ok(list);
    }

    @PostMapping("/{patientId}/risks")
    @Operation(summary = "Flag a risk for a patient", description = "Caregiver flags a risk type for the client. Body: { \"riskTypeId\": <id> }")
    @ApiResponses({
            @ApiResponse(responseCode = "201", description = "Risk flagged"),
            @ApiResponse(responseCode = "403", description = "Access denied"),
            @ApiResponse(responseCode = "404", description = "Patient or risk type not found"),
            @ApiResponse(responseCode = "409", description = "Risk already flagged for this patient")
    })
    public ResponseEntity<PatientRiskResponseDto> flagPatientRisk(
            @PathVariable Long patientId,
            @RequestBody FlagRiskRequestDto body) {
        User currentUser = getCurrentUser();
        if (currentUser.getRole() == Role.FAMILY_MEMBER) {
            throw new AppException(HttpStatus.FORBIDDEN, "Family members cannot flag risks");
        }
        Patient patient = patientService.getPatientById(patientId);
        validatePatientAccess(patient.getUser().getId(), currentUser);
        if (body.getRiskTypeId() == null) {
            throw new AppException(HttpStatus.BAD_REQUEST, "riskTypeId is required");
        }
        PatientRiskResponseDto dto = PatientRiskResponseDto.from(
                patientRiskService.flagRisk(patientId, body.getRiskTypeId(), currentUser.getId()));
        return ResponseEntity.status(HttpStatus.CREATED).body(dto);
    }

    @DeleteMapping("/{patientId}/risks/{riskId}")
    @Operation(summary = "Unflag a risk for a patient", description = "Removes the risk flag for the client")
    @ApiResponses({
            @ApiResponse(responseCode = "204", description = "Risk unflagged"),
            @ApiResponse(responseCode = "403", description = "Access denied"),
            @ApiResponse(responseCode = "404", description = "Patient or risk flag not found")
    })
    public ResponseEntity<Void> unflagPatientRisk(
            @PathVariable Long patientId,
            @PathVariable Long riskId) {
        User currentUser = getCurrentUser();
        if (currentUser.getRole() == Role.FAMILY_MEMBER) {
            throw new AppException(HttpStatus.FORBIDDEN, "Family members cannot unflag risks");
        }
        Patient patient = patientService.getPatientById(patientId);
        validatePatientAccess(patient.getUser().getId(), currentUser);
        patientRiskService.unflagRisk(patientId, riskId, currentUser.getId());
        return ResponseEntity.noContent().build();
    }

    // 3. Get all family members for a patient
    @GetMapping("/{patientId}/family-members")
    public ResponseEntity<List<FamilyMemberLinkResponse>> getFamilyMembersByPatient(@PathVariable Long patientId) {
        User currentUser = getCurrentUser();
        LOG.debug("GET /patients/{}/family-members - Current user: id={}, email={}, role={}",
                patientId, currentUser.getId(), currentUser.getEmail(), currentUser.getRole());

        // Get patient by patientId to ensure it exists
        Patient patient = patientService.getPatientById(patientId);
        LOG.debug("Found patient: id={}, userId={}, email={}",
                patient.getId(), patient.getUser().getId(), patient.getUser().getEmail());

        // Enforce same role/link access policy used by other patient-detail endpoints
        validatePatientAccess(patient.getUser().getId(), currentUser);

        // Use optimized query with patient_id (no joins needed)
        List<FamilyMemberLinkResponse> familyMembers = familyMemberService.getFamilyMembersByPatientId(patientId);
        LOG.debug("Retrieved {} family members for patientId={}", familyMembers.size(), patientId);
        return ResponseEntity.ok(familyMembers);
    }

    // 4. Register a new family member for a patient
    @PostMapping("/{patientId}/family-members")
    public ResponseEntity<FamilyMemberLinkResponse> registerFamilyMember(
            @PathVariable Long patientId,
            @RequestBody FamilyMemberRegistration registration) {

        User currentUser = getCurrentUser();
        LOG.debug("POST /patients/{}/family-members - Current user: id={}, email={}, role={}",
                patientId, currentUser.getId(), currentUser.getEmail(), currentUser.getRole());

        // Only patients and caregivers can register family members, not family members themselves
        if (currentUser.getRole() == Role.FAMILY_MEMBER) {
            throw new AppException(HttpStatus.FORBIDDEN, "Family members cannot register other family members");
        }

        // Get patient by patientId and extract user_id
        Patient patient = patientService.getPatientById(patientId);
        LOG.debug("Found patient: id={}, userId={}, email={}",
                patient.getId(), patient.getUser().getId(), patient.getUser().getEmail());

        // Create new registration with correct patient user ID
        FamilyMemberRegistration updatedRegistration = new FamilyMemberRegistration(
                registration.firstName(),
                registration.lastName(),
                registration.email(),
                registration.phone(),
                registration.address() != null ? registration.address() : null,
                registration.relationship() != null ? registration.relationship() : null,
                patient.getUser().getId()  // Use patient's user ID, not patient ID
        );

        FamilyMemberLinkResponse response = familyMemberService.registerFamilyMember(updatedRegistration, currentUser.getId());
        return ResponseEntity.ok(response);
    }

    // 5. Revoke family member access to a patient
    @DeleteMapping("/family-members/{linkId}")
    public ResponseEntity<Void> revokeFamilyMemberAccess(@PathVariable Long linkId) {
        User currentUser = getCurrentUser();

        // Only patients and caregivers can revoke family member access
        if (currentUser.getRole() == Role.FAMILY_MEMBER) {
            throw new AppException(HttpStatus.FORBIDDEN, "Family members cannot revoke access");
        }

        familyMemberService.revokeFamilyMemberAccess(linkId, currentUser.getId());
        return ResponseEntity.noContent().build();
    }

    // 6. Get family members for the current patient (convenience endpoint)
    @GetMapping("/family-members")
    @Operation(
            summary = "👨‍👩‍👧‍👦 Get my family members",
            description = "Retrieve all family members linked to the current patient",
            tags = {"Patient Management", "👨‍👩‍👧‍👦 Family Members"}
    )
    @ApiResponses({
            @ApiResponse(responseCode = "200", description = "Family members retrieved successfully"),
            @ApiResponse(responseCode = "401", description = "Authentication required"),
            @ApiResponse(responseCode = "403", description = "Only patients can view their family members")
    })
    public ResponseEntity<List<FamilyMemberLinkResponse>> getMyFamilyMembers() {
        User currentUser = getCurrentUser();
        LOG.debug("GET /patients/family-members - Current user: id={}, email={}, role={}",
                currentUser.getId(), currentUser.getEmail(), currentUser.getRole());

        // Only patients can use this endpoint
        if (currentUser.getRole() != Role.PATIENT) {
            throw new AppException(HttpStatus.FORBIDDEN, "Only patients can access this endpoint");
        }

        List<FamilyMemberLinkResponse> familyMembers = familyMemberService.getFamilyMembersByPatient(currentUser.getId());
        LOG.debug("Retrieved {} family members for patient userId={}", familyMembers.size(), currentUser.getId());
        return ResponseEntity.ok(familyMembers);
    }

    // 7. Get current patient's profile
    @GetMapping("/me")
    @Operation(
            summary = "👤 Get my patient profile",
            description = "Retrieve the current patient's profile information",
            tags = {"Patient Management"}
    )
    @ApiResponses({
            @ApiResponse(responseCode = "200", description = "Patient profile retrieved successfully"),
            @ApiResponse(responseCode = "401", description = "Authentication required"),
            @ApiResponse(responseCode = "403", description = "Only patients can view their profile"),
            @ApiResponse(responseCode = "404", description = "Patient profile not found")
    })
    public ResponseEntity<Patient> getMyProfile() {
        User currentUser = getCurrentUser();
        LOG.debug("GET /patients/me - Current user: id={}, email={}, role={}",
                currentUser.getId(), currentUser.getEmail(), currentUser.getRole());

        // Only patients can use this endpoint
        if (currentUser.getRole() != Role.PATIENT) {
            throw new AppException(HttpStatus.FORBIDDEN, "Only patients can access this endpoint");
        }

        Patient patient = patientService.getPatientByUserId(currentUser.getId());
        LOG.debug("Retrieved patient profile: id={}, userId={}", patient.getId(), patient.getUser().getId());
        return ResponseEntity.ok(patient);
    }

    // === MOOD & PAIN LOG ENDPOINTS ===

    // 6. Create a new mood pain log entry
    @PostMapping("/mood-pain-log")
    @Operation(
            summary = "📊 Create mood & pain log entry",
            description = "Create a new mood and pain log entry for the current patient.\n\n"
                    + "**Requirements:**\n"
                    + "- Must be authenticated as a PATIENT\n"
                    + "- Mood value: 1-10 scale (1 = worst, 10 = best)\n"
                    + "- Pain value: 0-10 scale:\n"
                    + "  0 = No pain\n"
                    + "  1 = Pain is very mild, barely noticeable. Most of the time you don't think about it\n"
                    + "  2 = Minor pain. It's annoying. You may have sharp pain now and then\n"
                    + "  3 = Noticeable pain. It may distract you, but you can get used to it\n"
                    + "  4 = Moderate pain. If you are involved in an activity, you're able to ignore the pain for a while. But it is still distracting\n"
                    + "  5 = Moderately strong pain. You can't ignore it for more than a few minutes. But, with effort, you can still work or do some social activities\n"
                    + "  6 = Moderately stronger pain. You avoid some of your normal daily activities. You have trouble concentrating\n"
                    + "  7 = Strong pain. It keeps you from doing normal activities\n"
                    + "  8 = Very strong pain. It's hard to do anything at all\n"
                    + "  9 = Pain that is very hard to tolerate. You can't carry on a conversation\n"
                    + "  10 = Worst pain possible\n"
                    + "- Timestamp cannot be in the future\n\n"
                    + "**Usage:**\n"
                    + "This endpoint allows patients to track their daily mood and pain levels, "
                    + "providing valuable data for caregivers and healthcare providers.",
            tags = {"Patient Management", "📊 Mood & Pain Tracking"}
    )
    @ApiResponses({
            @ApiResponse(responseCode = "200", description = "Mood pain log created successfully",
                    content = @Content(mediaType = "application/json", schema = @Schema(implementation = MoodPainLogResponse.class))),
            @ApiResponse(responseCode = "400", description = "Invalid request data"),
            @ApiResponse(responseCode = "401", description = "Authentication required"),
            @ApiResponse(responseCode = "403", description = "Only patients can create mood pain logs")
    })
    public ResponseEntity<MoodPainLogResponse> createMoodPainLog(
            @Parameter(description = "Mood and pain log data", required = true)
            @Valid @RequestBody MoodPainLogRequest request) {
        User currentUser = getCurrentUser();

        // Only patients can create mood pain logs
        if (currentUser.getRole() != Role.PATIENT) {
            throw new AppException(HttpStatus.FORBIDDEN, "Only patients can create mood pain logs");
        }

        MoodPainLogResponse response = moodPainLogService.createMoodPainLog(currentUser, request);
        return ResponseEntity.ok(response);
    }

    // 7. Get all mood pain logs for the current patient
    @GetMapping("/mood-pain-log")
    @Operation(
            summary = "📋 Get all mood & pain logs",
            description = "Retrieve all mood and pain log entries for the current patient, ordered by timestamp (newest first)",
            tags = {"Patient Management", "📊 Mood & Pain Tracking"}
    )
    @ApiResponses({
            @ApiResponse(responseCode = "200", description = "Mood pain logs retrieved successfully"),
            @ApiResponse(responseCode = "401", description = "Authentication required"),
            @ApiResponse(responseCode = "403", description = "Only patients can view their mood pain logs")
    })
    public ResponseEntity<List<MoodPainLogResponse>> getMoodPainLogs() {
        User currentUser = getCurrentUser();

        // Only patients can view their own mood pain logs
        if (currentUser.getRole() != Role.PATIENT) {
            throw new AppException(HttpStatus.FORBIDDEN, "Only patients can view their mood pain logs");
        }

        List<MoodPainLogResponse> logs = moodPainLogService.getMoodPainLogs(currentUser);
        return ResponseEntity.ok(logs);
    }

    // 8. Get mood pain logs with pagination
    @GetMapping("/mood-pain-log/paginated")
    public ResponseEntity<Page<MoodPainLogResponse>> getMoodPainLogsWithPagination(
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "10") int size) {
        User currentUser = getCurrentUser();

        // Only patients can view their own mood pain logs
        if (currentUser.getRole() != Role.PATIENT) {
            throw new AppException(HttpStatus.FORBIDDEN, "Only patients can view their mood pain logs");
        }

        Page<MoodPainLogResponse> logs = moodPainLogService.getMoodPainLogsWithPagination(currentUser, page, size);
        return ResponseEntity.ok(logs);
    }

    // 9. Get mood pain logs within a date range
    @GetMapping("/mood-pain-log/range")
    public ResponseEntity<List<MoodPainLogResponse>> getMoodPainLogsByDateRange(
            @RequestParam @DateTimeFormat(iso = DateTimeFormat.ISO.DATE_TIME) LocalDateTime startDate,
            @RequestParam @DateTimeFormat(iso = DateTimeFormat.ISO.DATE_TIME) LocalDateTime endDate) {
        User currentUser = getCurrentUser();

        // Only patients can view their own mood pain logs
        if (currentUser.getRole() != Role.PATIENT) {
            throw new AppException(HttpStatus.FORBIDDEN, "Only patients can view their mood pain logs");
        }

        List<MoodPainLogResponse> logs = moodPainLogService.getMoodPainLogsByDateRange(currentUser, startDate, endDate);
        return ResponseEntity.ok(logs);
    }

    // 10. Get the latest mood pain log
    @GetMapping("/mood-pain-log/latest")
    public ResponseEntity<MoodPainLogResponse> getLatestMoodPainLog() {
        User currentUser = getCurrentUser();

        // Only patients can view their own mood pain logs
        if (currentUser.getRole() != Role.PATIENT) {
            throw new AppException(HttpStatus.FORBIDDEN, "Only patients can view their mood pain logs");
        }

        MoodPainLogResponse latestLog = moodPainLogService.getLatestMoodPainLog(currentUser);
        return ResponseEntity.ok(latestLog);
    }

    // 11. Update an existing mood pain log
    @PutMapping("/mood-pain-log/{logId}")
    public ResponseEntity<MoodPainLogResponse> updateMoodPainLog(
            @PathVariable Long logId,
            @Valid @RequestBody MoodPainLogRequest request) {
        User currentUser = getCurrentUser();

        // Only patients can update their mood pain logs
        if (currentUser.getRole() != Role.PATIENT) {
            throw new AppException(HttpStatus.FORBIDDEN, "Only patients can update their mood pain logs");
        }

        MoodPainLogResponse response = moodPainLogService.updateMoodPainLog(currentUser, logId, request);
        return ResponseEntity.ok(response);
    }

    // 12. Delete a mood pain log
    @DeleteMapping("/mood-pain-log/{logId}")
    public ResponseEntity<Void> deleteMoodPainLog(@PathVariable Long logId) {
        User currentUser = getCurrentUser();

        // Only patients can delete their mood pain logs
        if (currentUser.getRole() != Role.PATIENT) {
            throw new AppException(HttpStatus.FORBIDDEN, "Only patients can delete their mood pain logs");
        }

        moodPainLogService.deleteMoodPainLog(currentUser, logId);
        return ResponseEntity.noContent().build();
    }

    // 13. Get mood pain logs for a specific patient (for caregivers to view)
    @GetMapping("/{patientId}/mood-pain-log")
    public ResponseEntity<List<MoodPainLogResponse>> getMoodPainLogsForPatient(@PathVariable Long patientId) {
        User currentUser = getCurrentUser();

        // Convert patientId to userId for validation
        Patient patient = patientService.getPatientById(patientId);
        validatePatientAccess(patient.getUser().getId(), currentUser);

        List<MoodPainLogResponse> logs = moodPainLogService.getMoodPainLogsForPatient(patientId);
        return ResponseEntity.ok(logs);
    }

    // 14. Get advanced mood and pain analytics
    @GetMapping("/mood-pain-log/analytics")
    @Operation(
            summary = "📈 Get mood & pain analytics",
            description = "Get detailed analytics for mood and pain data including trends, averages, and time series data.\n\n"
                    + "**Features:**\n"
                    + "- Average mood and pain levels over the period\n"
                    + "- Trend analysis (improving/declining)\n"
                    + "- Min/max values\n"
                    + "- Entry counts\n"
                    + "- Time series data for charts",
            tags = {"Patient Management", "📊 Mood & Pain Tracking"}
    )
    public ResponseEntity<MoodPainAnalyticsDTO> getMoodPainAnalytics(
            @RequestParam @DateTimeFormat(iso = DateTimeFormat.ISO.DATE_TIME) LocalDateTime startDate,
            @RequestParam @DateTimeFormat(iso = DateTimeFormat.ISO.DATE_TIME) LocalDateTime endDate) {
        User currentUser = getCurrentUser();

        // Only patients can view their own analytics
        if (currentUser.getRole() != Role.PATIENT) {
            throw new AppException(HttpStatus.FORBIDDEN, "Only patients can view their mood pain analytics");
        }

        MoodPainAnalyticsDTO analytics = moodPainLogService.getMoodPainAnalytics(currentUser, startDate, endDate);
        return ResponseEntity.ok(analytics);
    }

    /**
     * Get complete patient profile including allergies
     */
    @GetMapping("/{patientId}/profile")
    @Operation(summary = "Get patient profile", description = "Get complete patient profile including allergies")
    @ApiResponses(value = {
            @ApiResponse(responseCode = "200", description = "Profile retrieved successfully"),
            @ApiResponse(responseCode = "403", description = "Access denied"),
            @ApiResponse(responseCode = "404", description = "Patient not found")
    })
    public ResponseEntity<?> getPatientProfile(@PathVariable Long patientId) {
        try {
            // Check authorization
            if (!hasAccessToPatient(patientId)) {
                return ResponseEntity.status(HttpStatus.FORBIDDEN)
                        .body(Map.of("error", "Not authorized to view this patient's profile"));
            }

            Optional<PatientProfileDTO> profile = patientService.getPatientProfile(patientId);
            if (profile.isEmpty()) {
                return ResponseEntity.status(HttpStatus.NOT_FOUND)
                        .body(Map.of("error", "Patient not found"));
            }

            return ResponseEntity.ok(Map.of(
                    "data", profile.get(),
                    "message", "Profile retrieved successfully"
            ));

        } catch (Exception e) {
            LOG.error("Error getting patient profile for patientId: {}", patientId, e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body(Map.of("error", "Failed to retrieve patient profile"));
        }
    }

    /**
     * Update patient profile information
     */
    @PutMapping("/{patientId}/profile")
    @Operation(summary = "Update patient profile", description = "Update patient profile information (allergies managed separately)")
    @ApiResponses(value = {
            @ApiResponse(responseCode = "200", description = "Profile updated successfully"),
            @ApiResponse(responseCode = "400", description = "Invalid input data"),
            @ApiResponse(responseCode = "403", description = "Access denied"),
            @ApiResponse(responseCode = "404", description = "Patient not found")
    })
    public ResponseEntity<?> updatePatientProfile(
            @PathVariable Long patientId,
            @RequestBody PatientProfileUpdateDTO updateDTO) {
        try {
            // Check authorization
            if (!hasAccessToPatient(patientId)) {
                return ResponseEntity.status(HttpStatus.FORBIDDEN)
                        .body(Map.of("error", "Not authorized to update this patient's profile"));
            }

            PatientProfileDTO updatedProfile = patientService.updatePatientProfile(patientId, updateDTO);

            return ResponseEntity.ok(Map.of(
                    "data", updatedProfile,
                    "message", "Profile updated successfully"
            ));

        } catch (IllegalArgumentException e) {
            return ResponseEntity.status(HttpStatus.BAD_REQUEST)
                    .body(Map.of("error", e.getMessage()));
        } catch (Exception e) {
            LOG.error("Error updating patient profile for patientId: {}", patientId, e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body(Map.of("error", "Failed to update patient profile"));
        }
    }

    /**
     * Check if current user has access to manage the given patient's data
     */
    private boolean hasAccessToPatient(Long patientId) {
        try {
            Authentication auth = SecurityContextHolder.getContext().getAuthentication();
            String userEmail = auth.getName();

            User currentUser = userRepository.findByEmail(userEmail)
                    .orElseThrow(() -> new IllegalStateException("User not found"));

            Optional<Patient> patientOpt = Optional.ofNullable(patientService.getPatientById(patientId));
            if (patientOpt.isEmpty()) {
                return false;
            }

            Patient patient = patientOpt.get();
            User patientUser = patient.getUser();

            // Check access based on role
            if (currentUser.getRole() == Role.PATIENT) {
                // Patient can only access their own data
                return currentUser.getId().equals(patientUser.getId());
            } else if (currentUser.getRole() == Role.CAREGIVER) {
                // Check if user is a caregiver for this patient
                List<Caregiver> caregivers = patientService.getCaregiversByPatient(patientId);
                return caregivers.stream()
                        .anyMatch(caregiver -> caregiver.getUser().getId().equals(currentUser.getId()));
            } else if (currentUser.getRole() == Role.FAMILY_MEMBER) {
                // Check if user is a family member for this patient
                List<FamilyMemberLinkResponse> familyMembers = familyMemberService.getFamilyMembersByPatient(patientId);
                return familyMembers.stream()
                        .anyMatch(fm -> fm.familyUserId().equals(currentUser.getId()));
            } else if (currentUser.getRole() == Role.ADMIN) {
                // Admins can access any patient's data
                return true;
            }

            return false;
        } catch (Exception e) {
            LOG.error("Error checking patient access", e);
            return false;
        }
    }

    /**
     * Get enhanced patient profile with comprehensive medical information
     * This includes medications, latest vitals, mood/pain data, and medical summary
     */
    @GetMapping("/{patientId}/profile/enhanced")
    @Operation(summary = "Get enhanced patient profile",
            description = "Get comprehensive patient profile including medications, latest vitals, mood/pain data, and medical summary")
    @ApiResponses(value = {
            @ApiResponse(responseCode = "200", description = "Enhanced profile retrieved successfully"),
            @ApiResponse(responseCode = "403", description = "Access denied"),
            @ApiResponse(responseCode = "404", description = "Patient not found")
    })
    public ResponseEntity<?> getEnhancedPatientProfile(@PathVariable Long patientId) {
        try {
            // Check authorization
            if (!hasAccessToPatient(patientId)) {
                return ResponseEntity.status(HttpStatus.FORBIDDEN)
                        .body(Map.of("error", "Not authorized to view this patient's enhanced profile"));
            }

            Optional<EnhancedPatientProfileDTO> profile = patientService.getEnhancedPatientProfile(patientId);
            if (profile.isEmpty()) {
                return ResponseEntity.status(HttpStatus.NOT_FOUND)
                        .body(Map.of("error", "Patient not found"));
            }

            return ResponseEntity.ok(Map.of(
                    "data", profile.get(),
                    "message", "Enhanced profile retrieved successfully"
            ));

        } catch (Exception e) {
            LOG.error("Error getting enhanced patient profile for patientId: {}", patientId, e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body(Map.of("error", "Failed to retrieve enhanced patient profile"));
        }
    }

    @GetMapping("/{patientId}/provider")
    public ResponseEntity<Map<String, Object>> getPrimaryCareProvider(@PathVariable Long patientId) {
        return ResponseEntity.ok(patientService.getPrimaryProvider(patientId));
    }

    @GetMapping("/{patientID}/medications")
    @Operation(summary = "Get all medications for patient",
            description = "Get all medications for a specific patient")
    @ApiResponses(value = {
            @ApiResponse(responseCode = "200", description = "Medications retrieved successfully"),
            @ApiResponse(responseCode = "403", description = "Access denied"),
            @ApiResponse(responseCode = "404", description = "Patient not found")
    })
    public ResponseEntity<List<MedicationDTO>> getAllMedications(@PathVariable Long patientID) {
        User currentUser = getCurrentUser();

        // Convert patientId to userId for validation
        Patient patient = patientService.getPatientById(patientID);
        validatePatientAccess(patient.getUser().getId(), currentUser);

        List<MedicationDTO> allMeds = medicationService.getAllMedicationsForPatient(patientID);
        return ResponseEntity.ok(allMeds);
    }

    @PostMapping("/{patientID}/medications")
    @Operation(summary = "Add medication for patient",
            description = "Create a new medication for a specific patient")
    @ApiResponses(value = {
            @ApiResponse(responseCode = "200", description = "Medication created successfully"),
            @ApiResponse(responseCode = "400", description = "Invalid medication data"),
            @ApiResponse(responseCode = "403", description = "Access denied"),
            @ApiResponse(responseCode = "404", description = "Patient not found")
    })
    public ResponseEntity<MedicationDTO> addMedication(
            @PathVariable Long patientID,
            @Valid @RequestBody MedicationDTO medicationDTO) {
        User currentUser = getCurrentUser();

        // Family members have read-only access, cannot add medications
        if (currentUser.getRole() == Role.FAMILY_MEMBER) {
            throw new AppException(HttpStatus.FORBIDDEN, "Family members have read-only access");
        }

        // Convert patientId to userId for validation
        Patient patient = patientService.getPatientById(patientID);
        validatePatientAccess(patient.getUser().getId(), currentUser);

        // Ensure the patientId in the DTO matches the path parameter
        MedicationDTO medicationWithPatientId = new MedicationDTO(
                null, // id will be generated
                patientID,
                medicationDTO.medicationName(),
                medicationDTO.dosage(),
                medicationDTO.frequency(),
                medicationDTO.route(),
                medicationDTO.medicationType(),
                medicationDTO.prescribedBy(),
                medicationDTO.prescribedDate(),
                medicationDTO.startDate(),
                medicationDTO.endDate(),
                medicationDTO.notes(),
                true, // Set as active by default
                null
        );

        MedicationDTO createdMedication = medicationService.createMedication(medicationWithPatientId);
        return ResponseEntity.ok(createdMedication);
    }

    @DeleteMapping("/{patientID}/medications/{medicationId}")
    @Operation(summary = "Remove medication for patient",
            description = "Deactivate a medication for a specific patient (soft delete)")
    @ApiResponses(value = {
            @ApiResponse(responseCode = "204", description = "Medication deactivated successfully"),
            @ApiResponse(responseCode = "403", description = "Access denied"),
            @ApiResponse(responseCode = "404", description = "Patient or medication not found")
    })
    public ResponseEntity<Void> removeMedication(
            @PathVariable Long patientID,
            @PathVariable Long medicationId) {
        User currentUser = getCurrentUser();

        // Family members have read-only access, cannot remove medications
        if (currentUser.getRole() == Role.FAMILY_MEMBER) {
            throw new AppException(HttpStatus.FORBIDDEN, "Family members have read-only access");
        }

        // Convert patientId to userId for validation
        Patient patient = patientService.getPatientById(patientID);
        validatePatientAccess(patient.getUser().getId(), currentUser);

        // Deactivate the medication (soft delete)
        medicationService.deactivateMedication(patientID, medicationId);
        return ResponseEntity.noContent().build();
    }

    @PutMapping("/{patientID}/medications/{medicationId}/last-taken")
    @Operation(summary = "Mark medication as taken",
            description = "Persist last taken timestamp for medication reminder tracking")
    @ApiResponses(value = {
            @ApiResponse(responseCode = "200", description = "Medication taken time updated successfully"),
            @ApiResponse(responseCode = "403", description = "Access denied"),
            @ApiResponse(responseCode = "404", description = "Patient or medication not found")
    })
    public ResponseEntity<MedicationDTO> updateMedicationLastTaken(
            @PathVariable Long patientID,
            @PathVariable Long medicationId,
            @RequestBody(required = false) MedicationLastTakenUpdateDTO request) {
        User currentUser = getCurrentUser();

        // Family members have read-only access, cannot modify medications
        if (currentUser.getRole() == Role.FAMILY_MEMBER) {
            throw new AppException(HttpStatus.FORBIDDEN, "Family members have read-only access");
        }

        Patient patient = patientService.getPatientById(patientID);
        validatePatientAccess(patient.getUser().getId(), currentUser);

        final Instant lastTaken = request != null && request.lastTaken() != null
                ? request.lastTaken()
                : Instant.now();
        MedicationDTO updated = medicationService.updateMedicationLastTaken(patientID, medicationId, lastTaken);
        return ResponseEntity.ok(updated);
    }

    @DeleteMapping("/{patientID}/medications/{medicationId}/last-taken")
    @Operation(summary = "Clear medication taken status",
            description = "Clear persisted last taken timestamp for medication reminder tracking")
    @ApiResponses(value = {
            @ApiResponse(responseCode = "204", description = "Medication taken status cleared successfully"),
            @ApiResponse(responseCode = "403", description = "Access denied"),
            @ApiResponse(responseCode = "404", description = "Patient or medication not found")
    })
    public ResponseEntity<Void> clearMedicationLastTaken(
            @PathVariable Long patientID,
            @PathVariable Long medicationId) {
        User currentUser = getCurrentUser();

        // Family members have read-only access, cannot modify medications
        if (currentUser.getRole() == Role.FAMILY_MEMBER) {
            throw new AppException(HttpStatus.FORBIDDEN, "Family members have read-only access");
        }

        Patient patient = patientService.getPatientById(patientID);
        validatePatientAccess(patient.getUser().getId(), currentUser);

        medicationService.clearMedicationLastTaken(patientID, medicationId);
        return ResponseEntity.noContent().build();
    }

}
