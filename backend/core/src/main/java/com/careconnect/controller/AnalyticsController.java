package com.careconnect.controller;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.servlet.mvc.method.annotation.SseEmitter;
import jakarta.validation.Valid;
import jakarta.annotation.PreDestroy;
import lombok.RequiredArgsConstructor;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.Permission;
import com.careconnect.security.Role;
import com.careconnect.security.RequirePermission;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.util.SecurityUtil;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.MediaType;

import com.careconnect.dto.DashboardDTO;
import com.careconnect.model.User;
import java.util.Optional;
import java.util.Map;
import java.util.Collections;
import org.springframework.security.core.Authentication;
import com.careconnect.dto.ExportLinkDTO;
import com.careconnect.dto.VitalAlertEventDTO;
import com.careconnect.dto.VitalSampleDTO;
import com.careconnect.dto.WearableReadingIngestionRequest;
import com.careconnect.dto.WearableReadingIngestionResponse;
import com.careconnect.service.AnalyticsService;
import com.careconnect.service.VitalSampleService;
import com.careconnect.exception.AppException;
import com.careconnect.model.Patient;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.PatientCaregiverRepository;
import com.careconnect.repository.FamilyMemberLinkRepository;
import com.careconnect.model.FamilyMemberLink;
import com.careconnect.repository.UserRepository;
import com.careconnect.service.CaregiverService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.context.SecurityContext;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.core.userdetails.UserDetails;
import java.time.Period;
import org.springframework.security.core.Authentication;
import com.careconnect.security.UserPrincipal;
import java.util.Map;
import java.util.Collections;

import com.careconnect.model.CaregiverPatientLink;

import java.time.Period;
import java.util.List;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicBoolean;
import java.time.LocalDateTime;

@RestController
@RequestMapping("/v1/api/analytics")
@RequiredArgsConstructor
public class AnalyticsController {
    // ...existing code...

    private final SecurityUtil securityUtil;
    private final AuthorizationService authorizationService;

    @Autowired
    private final UserRepository userRepository;


    @Autowired
    private final PatientRepository patientRepository;
    
    @Autowired
    private final CaregiverService caregiverService;

    @Autowired
private final PatientCaregiverRepository caregiverPatientLinkRepository;

    @Autowired
private final FamilyMemberLinkRepository familyMemberPatientLinkRepository;

    @Autowired
    private AnalyticsService analyticsService;
    
    @Autowired
    private VitalSampleService vitalSampleService;
    private final ScheduledExecutorService sseExecutor = Executors.newScheduledThreadPool(2);

    @GetMapping("/dashboard")
    public DashboardDTO dashboard(
            @RequestParam Long patientId,
            @RequestParam(defaultValue = "7") int days) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireAdminOrCaregiver(currentUser);
        if (days < 1) days = 1;
        return analyticsService.getDashboard(patientId, Period.ofDays(days));
    }

    @GetMapping("/export/vitals/csv")
    public ResponseEntity<byte[]> exportVitalsCsv(
        @RequestParam Long patientId,
        @RequestParam(defaultValue = "7") int days) throws UnauthorizedException {
    User currentUser = securityUtil.resolveCurrentUser();
    authorizationService.requireAdminOrCaregiver(currentUser);
    if (days < 1) days = 1;
    byte[] csv = analyticsService.exportVitalsCsv(patientId, Period.ofDays(days));
    return ResponseEntity.ok()
            .header("Content-Disposition", "attachment; filename=\"vitals.csv\"")
            .contentType(org.springframework.http.MediaType.parseMediaType("text/csv"))
            .body(csv);
    }

    @GetMapping("/export/vitals/pdf")
    public ResponseEntity<byte[]> exportVitalsPdf(
        @RequestParam Long patientId,
        @RequestParam(defaultValue = "7") int days) throws UnauthorizedException {
    User currentUser = securityUtil.resolveCurrentUser();
    authorizationService.requireAdminOrCaregiver(currentUser);
    if (days < 1) days = 1;
    byte[] pdf = analyticsService.exportVitalsPdf(patientId, Period.ofDays(days));
    return ResponseEntity.ok()
            .header("Content-Disposition", "attachment; filename=\"vitals.pdf\"")
            .contentType(org.springframework.http.MediaType.APPLICATION_PDF)
            .body(pdf);
}

    @GetMapping(value = "/live", produces = MediaType.TEXT_EVENT_STREAM_VALUE)
    public SseEmitter live(@RequestParam Long patientId) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireAdminOrCaregiver(currentUser);
        SseEmitter emitter = new SseEmitter(30 * 60 * 1000L); // 30 min
        AtomicBoolean active = new AtomicBoolean(true);
        ScheduledFuture<?> task = sseExecutor.scheduleAtFixedRate(() -> {
            if (!active.get()) {
                return;
            }
            try {
                DashboardDTO dto = analyticsService.getDashboard(patientId, Period.ofDays(1));
                emitter.send(dto);
            } catch (Exception e) {
                active.set(false);
                emitter.completeWithError(e);
            }
        }, 0, 2, TimeUnit.SECONDS);

        emitter.onCompletion(() -> {
            active.set(false);
            task.cancel(true);
        });
        emitter.onTimeout(() -> {
            active.set(false);
            task.cancel(true);
            emitter.complete();
        });
        emitter.onError((ex) -> {
            active.set(false);
            task.cancel(true);
        });
        return emitter;
    }

    @PreDestroy
    public void shutdownSseExecutor() {
        sseExecutor.shutdownNow();
    }

@GetMapping("/vitals")
public ResponseEntity<?> vitals(@RequestParam Long patientId, @RequestParam int days) {
  try {
        if (days < 1) {
            days = 1;
        }
        // Get user details from JWT token
        Authentication auth = SecurityContextHolder.getContext().getAuthentication();
        String userEmail = auth.getName();
        
        // Find user
        User currentUser = userRepository.findByEmail(userEmail)
            .orElseThrow(() -> new IllegalStateException("User not found"));
        
        // Find patient
        Optional<Patient> patientOpt = patientRepository.findById(patientId);
        if (patientOpt.isEmpty()) {
            return ResponseEntity.status(HttpStatus.NOT_FOUND)
                .body(Map.of("error", "Patient not found"));
        }
        
        Patient patient = patientOpt.get();
        User patientUser = patient.getUser();
        
        // Check access based on role
        boolean hasAccess = false;
        
        if (currentUser.getRole() == Role.PATIENT) {
            // Patient can only access their own data
            hasAccess = currentUser.getId().equals(patientUser.getId());
        } 
        else if (currentUser.getRole() == Role.CAREGIVER) {
            // Check if user is a caregiver for this patient
    hasAccess = caregiverService.hasAccessToPatient(currentUser.getId(), patientId);

        }
        else if (currentUser.getRole() == Role.FAMILY_MEMBER) {
            // Check if user is a family member for this patient
    hasAccess = caregiverService.hasAccessToPatient(currentUser.getId(), patientId);

        }
        else if (currentUser.getRole() == Role.ADMIN) {
            // Admins have access to all patients
            hasAccess = true;
        }
        
        if (!hasAccess) {
            return ResponseEntity.status(HttpStatus.FORBIDDEN)
                .body(Map.of("error", "Not authorized to access this patient's data"));
        }

        // Access granted, return data
        return ResponseEntity.ok(Map.of(
            "data", analyticsService.getVitals(patientId, Period.ofDays(days)),
            "message", "Vitals data retrieved successfully"
        ));
    } catch (Exception e) {
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(Map.of(
            "error", "Failed to retrieve vitals data"
        ));
    }
    }

@GetMapping("/alerts/recent")
public ResponseEntity<?> recentVitalAlerts(
        @RequestParam Long patientId,
        @RequestParam(defaultValue = "5") int limit
) {
    try {
        Authentication auth = SecurityContextHolder.getContext().getAuthentication();
        String userEmail = auth.getName();
        User currentUser = userRepository.findByEmail(userEmail)
                .orElseThrow(() -> new IllegalStateException("User not found"));

        Optional<Patient> patientOpt = patientRepository.findById(patientId);
        if (patientOpt.isEmpty()) {
            return ResponseEntity.status(HttpStatus.NOT_FOUND)
                    .body(Map.of("error", "Patient not found"));
        }
        Patient patient = patientOpt.get();
        User patientUser = patient.getUser();

        boolean hasAccess = false;
        if (currentUser.getRole() == Role.PATIENT) {
            hasAccess = currentUser.getId().equals(patientUser.getId());
        } else if (currentUser.getRole() == Role.CAREGIVER) {
            hasAccess = caregiverService.hasAccessToPatient(currentUser.getId(), patientId);
        } else if (currentUser.getRole() == Role.FAMILY_MEMBER) {
            hasAccess = familyMemberPatientLinkRepository.existsByFamilyMemberUserIdAndPatientId(
                    currentUser.getId(),
                    patientId,
                    LocalDateTime.now()
            );
        } else if (currentUser.getRole() == Role.ADMIN) {
            hasAccess = true;
        }

        if (!hasAccess) {
            return ResponseEntity.status(HttpStatus.FORBIDDEN)
                    .body(Map.of("error", "Not authorized to access this patient's alerts"));
        }

        List<VitalAlertEventDTO> alerts = analyticsService.getRecentVitalAlertEvents(patientId, limit);
        return ResponseEntity.ok(Map.of(
                "data", alerts,
                "message", "Recent vital alerts retrieved successfully"
        ));
    } catch (Exception e) {
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(Map.of(
                "error", "Failed to retrieve recent vital alerts"
        ));
    }
}

    /**
     * Create a new vital sample
     */
    @PostMapping("/vitals")
    public ResponseEntity<?> createVitalSample(@RequestBody VitalSampleDTO vitalSampleDTO) {
        try {
            // Get user details from JWT token
            Authentication auth = SecurityContextHolder.getContext().getAuthentication();
            String userEmail = auth.getName();
            
            // Find user
            User currentUser = userRepository.findByEmail(userEmail)
                .orElseThrow(() -> new IllegalStateException("User not found"));
            
            // Find patient
            Optional<Patient> patientOpt = patientRepository.findById(vitalSampleDTO.patientId());
            if (patientOpt.isEmpty()) {
                return ResponseEntity.status(HttpStatus.NOT_FOUND)
                    .body(Map.of("error", "Patient not found"));
            }
            
            Patient patient = patientOpt.get();
            User patientUser = patient.getUser();
            
            // Check access - only allow patients to create their own vitals or authorized caregivers/family
            boolean hasAccess = false;
            
            if (currentUser.getRole() == Role.PATIENT) {
                // Patient can only create their own data
                hasAccess = currentUser.getId().equals(patientUser.getId());
            } 
            else if (currentUser.getRole() == Role.CAREGIVER) {
                // Check if user is a caregiver for this patient
                hasAccess = caregiverService.hasAccessToPatient(currentUser.getId(), vitalSampleDTO.patientId());
            }
            else if (currentUser.getRole() == Role.FAMILY_MEMBER) {
                // Check if user is a family member for this patient
                hasAccess = caregiverService.hasAccessToPatient(currentUser.getId(), vitalSampleDTO.patientId());
            }
            else if (currentUser.getRole() == Role.ADMIN) {
                // Admins can create vitals for any patient
                hasAccess = true;
            }
            
            if (!hasAccess) {
                return ResponseEntity.status(HttpStatus.FORBIDDEN)
                    .body(Map.of("error", "Not authorized to create vitals for this patient"));
            }

            // Create the vital sample
            VitalSampleDTO created = vitalSampleService.createVitalSample(vitalSampleDTO);
            
            return ResponseEntity.status(HttpStatus.CREATED)
                .body(Map.of(
                    "data", created,
                    "message", "Vital sample created successfully"
                ));
            
        } catch (IllegalArgumentException e) {
            return ResponseEntity.status(HttpStatus.BAD_REQUEST)
                .body(Map.of("error", e.getMessage()));
        } catch (Exception e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body(Map.of("error", "Failed to create vital sample"));
        }
    }

    @PostMapping("/vitals/ingest")
    @RequirePermission(Permission.RECORD_HEALTH_DATA)
    public ResponseEntity<?> ingestWearableReadings(@Valid @RequestBody WearableReadingIngestionRequest request) {
        Authentication auth = SecurityContextHolder.getContext().getAuthentication();
        String userEmail = auth.getName();

        User currentUser = userRepository.findByEmail(userEmail)
                .orElseThrow(() -> new AppException(HttpStatus.UNAUTHORIZED, "User not found"));

        WearableReadingIngestionResponse response = vitalSampleService.ingestWearableReadings(currentUser, request);

        if (response.acceptedCount() == 0) {
            return ResponseEntity.status(HttpStatus.BAD_REQUEST).body(Map.of(
                    "error", "No wearable readings were accepted",
                    "data", response
            ));
        }

        if (response.rejectedCount() > 0) {
            return ResponseEntity.status(HttpStatus.MULTI_STATUS).body(Map.of(
                    "data", response,
                    "message", "Wearable readings partially ingested"
            ));
        }

        return ResponseEntity.status(HttpStatus.CREATED).body(Map.of(
                "data", response,
                "message", "Wearable readings ingested successfully"
        ));
    }

    /**
     * Update an existing vital sample
     */
    @PutMapping("/vitals/{id}")
    public ResponseEntity<?> updateVitalSample(@PathVariable Long id, @RequestBody VitalSampleDTO vitalSampleDTO) {
        try {
            // Get user details from JWT token
            Authentication auth = SecurityContextHolder.getContext().getAuthentication();
            String userEmail = auth.getName();
            
            // Find user
            User currentUser = userRepository.findByEmail(userEmail)
                .orElseThrow(() -> new IllegalStateException("User not found"));
            
            // Check if vital sample exists and get patient info
            Optional<VitalSampleDTO> existingVitalOpt = vitalSampleService.getVitalSample(id);
            if (existingVitalOpt.isEmpty()) {
                return ResponseEntity.status(HttpStatus.NOT_FOUND)
                    .body(Map.of("error", "Vital sample not found"));
            }
            
            VitalSampleDTO existingVital = existingVitalOpt.get();
            Long patientId = existingVital.patientId();
            
            // Find patient
            Optional<Patient> patientOpt = patientRepository.findById(patientId);
            if (patientOpt.isEmpty()) {
                return ResponseEntity.status(HttpStatus.NOT_FOUND)
                    .body(Map.of("error", "Patient not found"));
            }
            
            Patient patient = patientOpt.get();
            User patientUser = patient.getUser();
            
            // Check access - only allow patients to update their own vitals or authorized caregivers/family
            boolean hasAccess = false;
            
            if (currentUser.getRole() == Role.PATIENT) {
                // Patient can only update their own data
                hasAccess = currentUser.getId().equals(patientUser.getId());
            } 
            else if (currentUser.getRole() == Role.CAREGIVER) {
                // Check if user is a caregiver for this patient
                hasAccess = caregiverService.hasAccessToPatient(currentUser.getId(), patientId);
            }
            else if (currentUser.getRole() == Role.FAMILY_MEMBER) {
                // Check if user is a family member for this patient
                hasAccess = caregiverService.hasAccessToPatient(currentUser.getId(), patientId);
            }
            else if (currentUser.getRole() == Role.ADMIN) {
                // Admins can update vitals for any patient
                hasAccess = true;
            }
            
            if (!hasAccess) {
                return ResponseEntity.status(HttpStatus.FORBIDDEN)
                    .body(Map.of("error", "Not authorized to update vitals for this patient"));
            }

            // Update the vital sample
            VitalSampleDTO updated = vitalSampleService.updateVitalSample(id, vitalSampleDTO);
            
            return ResponseEntity.ok(Map.of(
                "data", updated,
                "message", "Vital sample updated successfully"
            ));
            
        } catch (IllegalArgumentException e) {
            return ResponseEntity.status(HttpStatus.BAD_REQUEST)
                .body(Map.of("error", e.getMessage()));
        } catch (Exception e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body(Map.of("error", "Failed to update vital sample"));
        }
    }
}
