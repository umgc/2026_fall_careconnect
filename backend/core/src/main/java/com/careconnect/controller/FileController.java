package com.careconnect.controller;

import com.careconnect.security.Permission;
import com.careconnect.security.RequirePermission;

import com.careconnect.dto.FileUploadResponse;
import com.careconnect.dto.StructuredDocumentEntryDTO;
import com.careconnect.dto.StructuredEntryRequest;
import com.careconnect.dto.UserFileDTO;
import com.careconnect.service.S3StorageService;
import com.careconnect.service.FileManagementService;
import com.careconnect.repository.UserRepository;
import com.careconnect.model.User;
import com.careconnect.security.Role;
import com.careconnect.service.CaregiverService;
import com.careconnect.service.PatientService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.security.SecurityRequirement;
import io.swagger.v3.oas.annotations.tags.Tag;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

import java.util.Collections;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.stream.Collectors;

import com.careconnect.model.Patient;
import com.careconnect.model.UserFile;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.MessageRepository;

@RestController
@RequestMapping("/v1/api/files")
@Slf4j
@Tag(name = "File Management", description = "File upload, download, and management endpoints supporting both S3 and database storage")
@SecurityRequirement(name = "Bearer Authentication")
public class FileController {

    private final S3StorageService s3StorageService;
    private final FileManagementService fileManagementService;
    private final UserRepository userRepository;
    private final PatientRepository patientRepository;
    private final MessageRepository messageRepository;
    private final CaregiverService caregiverService;
    private final PatientService patientService;

    @Autowired
    public FileController(@Autowired(required = false) S3StorageService s3StorageService,
                         FileManagementService fileManagementService,
                         UserRepository userRepository,
                         PatientRepository patientRepository,
                         MessageRepository messageRepository,
                         CaregiverService caregiverService,
                         PatientService patientService) {
        this.s3StorageService = s3StorageService;
        this.fileManagementService = fileManagementService;
        this.userRepository = userRepository;
        this.patientRepository = patientRepository;
        this.messageRepository = messageRepository;
        this.caregiverService = caregiverService;
        this.patientService = patientService;
    }
    
    @Value("${app.file.storage.use-s3:true}")
    private boolean useS3ForLegacyEndpoints;

    // ==================== NEW DATABASE-FIRST ENDPOINTS ====================
    
    /**
     * Upload a file using the new database-first approach
     */
    @RequirePermission(Permission.RECORD_HEALTH_DATA)

    @PostMapping("/upload")
    @Operation(summary = "Upload a file", description = "Upload a file for the current user (database-first storage)")
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "File uploaded successfully"),
        @ApiResponse(responseCode = "400", description = "Invalid file or parameters"),
        @ApiResponse(responseCode = "401", description = "Authentication required"),
        @ApiResponse(responseCode = "413", description = "File too large")
    })
    public ResponseEntity<?> uploadFile(
            @RequestParam("file") MultipartFile file,
            @RequestParam(value = "category", defaultValue = "OTHER_DOCUMENT") String category,
            @RequestParam(value = "description", required = false) String description,
            @RequestParam(value = "patientId", required = false) Long patientId) {
        
        try {
            User currentUser = getCurrentUser();
            log.info("File upload request - User: {}, Category: {}, PatientId: {}",
                    currentUser.getId(), category, patientId);

            // Validate the category up-front so an invalid value returns a clear 400.
            // (The service wraps failures in a RuntimeException, which would otherwise
            //  surface as a generic 500 and lose the helpful message.)
            UserFile.FileCategory resolvedCategory;
            try {
                resolvedCategory = UserFile.FileCategory.fromClientValue(category);
            } catch (IllegalArgumentException e) {
                return ResponseEntity.badRequest().body(Map.of("error", e.getMessage()));
            }

            // Validate patient access if patientId is specified
            if (patientId != null && !hasAccessToPatient(currentUser, patientId)) {
                return ResponseEntity.status(HttpStatus.FORBIDDEN)
                        .body(Map.of("error", "Not authorized to upload files for this patient"));
            }

            String userType = currentUser.getRole().name();
            // Pass the canonical token downstream so storage naming/logs never see a raw alias.
            FileUploadResponse response = fileManagementService.uploadFile(
                    file, currentUser.getId(), userType, resolvedCategory.name(), description, patientId);
            
            return ResponseEntity.ok(Map.of(
                    "data", response,
                    "message", "File uploaded successfully"
            ));
            
        } catch (IllegalArgumentException e) {
            return ResponseEntity.badRequest()
                    .body(Map.of("error", e.getMessage()));
        } catch (Exception e) {
            log.error("Error uploading file", e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body(Map.of("error", "Failed to upload file"));
        }
    }

    // ==================== EMPLOYMENT / HOME-CARE INTAKE WORKFLOW ====================

    /**
     * Dedicated intake workflow for employment and home-care documents (hiring and
     * onboarding forms). The document type is selected from the typed category model and
     * the file is linked to the uploading owner and, when supplied, to the patient /
     * care circle it pertains to.
     */
    @RequirePermission(Permission.RECORD_HEALTH_DATA)

    @PostMapping("/intake")
    @Operation(summary = "Upload an employment / home-care intake document",
            description = "Intake workflow for hiring and onboarding forms with typed document-type "
                    + "selection. The document is linked to the uploading owner and, when provided, to the "
                    + "patient / care circle it pertains to.")
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "Intake document uploaded successfully"),
        @ApiResponse(responseCode = "400", description = "Invalid or missing document type"),
        @ApiResponse(responseCode = "401", description = "Authentication required"),
        @ApiResponse(responseCode = "403", description = "Not authorized for the target patient / care circle")
    })
    public ResponseEntity<?> uploadIntakeDocument(
            @RequestParam("file") MultipartFile file,
            @RequestParam(value = "documentType", required = false) String documentType,
            @RequestParam(value = "category", required = false) String category,
            @RequestParam(value = "description", required = false) String description,
            @RequestParam(value = "patientId", required = false) Long patientId,
            @RequestParam(value = "careCircleId", required = false) Long careCircleId) {

        try {
            User currentUser = getCurrentUser();

            // A document type is mandatory for intake; accept either parameter name.
            String rawType = (documentType != null && !documentType.isBlank()) ? documentType : category;
            if (rawType == null || rawType.isBlank()) {
                return ResponseEntity.badRequest()
                        .body(Map.of("error", "A document type is required for intake uploads. "
                                + "Valid types: " + employmentIntakeTypeNames()));
            }

            // Resolve + validate against the typed category model (clear 400 on a bad value).
            UserFile.FileCategory resolved;
            try {
                resolved = UserFile.FileCategory.fromClientValue(rawType);
            } catch (IllegalArgumentException e) {
                return ResponseEntity.badRequest().body(Map.of("error", e.getMessage()));
            }

            // Intake is restricted to employment / home-care document types.
            if (!resolved.isEmploymentIntake()) {
                return ResponseEntity.badRequest()
                        .body(Map.of("error", "'" + rawType + "' is not a valid intake document type. "
                                + "Use one of: " + employmentIntakeTypeNames()));
            }

            // Care-circle context: a care circle is anchored on its care recipient (patient),
            // so both parameters identify the same person. Reject conflicting values instead
            // of silently preferring one, then accept whichever was supplied.
            if (patientId != null && careCircleId != null && !patientId.equals(careCircleId)) {
                return ResponseEntity.badRequest()
                        .body(Map.of("error", "patientId and careCircleId refer to the same care "
                                + "recipient but were given conflicting values ("
                                + patientId + " vs " + careCircleId + "). Provide just one."));
            }
            Long careRecipientId = (patientId != null) ? patientId : careCircleId;

            // Ensure the uploader may attach documents to that patient / care circle.
            if (careRecipientId != null && !hasAccessToPatient(currentUser, careRecipientId)) {
                return ResponseEntity.status(HttpStatus.FORBIDDEN)
                        .body(Map.of("error",
                                "Not authorized to upload intake documents for this patient / care circle"));
            }

            log.info("Intake upload - owner: {} ({}), type: {}, patient/careCircle: {}",
                    currentUser.getId(), currentUser.getRole(), resolved, careRecipientId);

            String userType = currentUser.getRole().name();
            FileUploadResponse response = fileManagementService.uploadFile(
                    file, currentUser.getId(), userType, resolved.name(), description, careRecipientId);

            return ResponseEntity.ok(Map.of(
                    "data", response,
                    "message", "Intake document uploaded successfully"));

        } catch (IllegalArgumentException e) {
            return ResponseEntity.badRequest().body(Map.of("error", e.getMessage()));
        } catch (Exception e) {
            log.error("Error uploading intake document", e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body(Map.of("error", "Failed to upload intake document"));
        }
    }

    /**
     * List the current user's employment / onboarding intake documents.
     */
    @RequirePermission(Permission.VIEW_HEALTH_DATA)

    @GetMapping("/intake/my")
    @Operation(summary = "List my intake documents",
            description = "List employment / onboarding documents owned by the current user")
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "Intake documents retrieved successfully"),
        @ApiResponse(responseCode = "401", description = "Authentication required")
    })
    public ResponseEntity<?> listMyIntakeDocuments() {
        try {
            User currentUser = getCurrentUser();
            List<UserFileDTO> files = fileManagementService.listEmploymentDocumentsForUser(
                    currentUser.getId(), currentUser.getRole().name());
            return ResponseEntity.ok(Map.of(
                    "data", files,
                    "message", "Intake documents retrieved successfully"));
        } catch (Exception e) {
            log.error("Error listing intake documents", e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body(Map.of("error", "Failed to list intake documents"));
        }
    }

    /**
     * List intake documents linked to a specific patient / care circle.
     */
    @RequirePermission(Permission.VIEW_HEALTH_DATA)

    @GetMapping("/intake/patient/{patientId}")
    @Operation(summary = "List intake documents for a patient / care circle",
            description = "List employment / onboarding documents linked to a patient (care-circle context)")
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "Intake documents retrieved successfully"),
        @ApiResponse(responseCode = "403", description = "Access denied")
    })
    public ResponseEntity<?> listPatientIntakeDocuments(@PathVariable Long patientId) {
        try {
            User currentUser = getCurrentUser();
            if (!hasAccessToPatient(currentUser, patientId)) {
                return ResponseEntity.status(HttpStatus.FORBIDDEN)
                        .body(Map.of("error", "Not authorized to access this patient's intake documents"));
            }
            List<UserFileDTO> files = fileManagementService.listEmploymentDocumentsForPatient(patientId);
            return ResponseEntity.ok(Map.of(
                    "data", files,
                    "message", "Intake documents retrieved successfully"));
        } catch (Exception e) {
            log.error("Error listing patient intake documents for patientId: {}", patientId, e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body(Map.of("error", "Failed to list patient intake documents"));
        }
    }

    // ==================== STRUCTURED FORM ENTRIES ====================

    /**
     * Create a structured form entry for an uploaded document. The original file
     * remains linked to the record as supporting evidence.
     */
    @RequirePermission(Permission.RECORD_HEALTH_DATA)

    @PostMapping("/{fileId}/structured-entry")
    @Operation(summary = "Create a structured entry for a file",
            description = "Capture key fields from an uploaded onboarding document as a structured, "
                    + "searchable record. The original file stays linked as supporting evidence. "
                    + "A patient or employee context and all required fields for the document type "
                    + "must be supplied.")
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "Structured entry created successfully"),
        @ApiResponse(responseCode = "400", description = "Missing context, unsupported document type, or incomplete required fields"),
        @ApiResponse(responseCode = "403", description = "Access denied"),
        @ApiResponse(responseCode = "404", description = "File not found")
    })
    public ResponseEntity<?> createStructuredEntry(
            @PathVariable Long fileId,
            @RequestBody StructuredEntryRequest request) {
        try {
            User currentUser = getCurrentUser();

            Optional<UserFileDTO> fileOpt = fileManagementService.getFile(fileId);
            if (fileOpt.isEmpty()) {
                return ResponseEntity.status(HttpStatus.NOT_FOUND)
                        .body(Map.of("error", "File not found"));
            }
            ResponseEntity<?> denied = checkStructuredEntryAccess(currentUser, fileOpt.get(), request);
            if (denied != null) {
                return denied;
            }

            StructuredDocumentEntryDTO entry = fileManagementService.createStructuredEntry(
                    fileId, request, currentUser.getId());
            return ResponseEntity.ok(Map.of(
                    "data", entry,
                    "message", "Structured entry created successfully"));

        } catch (IllegalArgumentException e) {
            return ResponseEntity.badRequest().body(Map.of("error", e.getMessage()));
        } catch (Exception e) {
            log.error("Error creating structured entry for file: {}", fileId, e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body(Map.of("error", "Failed to create structured entry"));
        }
    }

    /**
     * Get the structured entry captured from a specific file, if any.
     */
    @RequirePermission(Permission.VIEW_HEALTH_DATA)

    @GetMapping("/{fileId}/structured-entry")
    @Operation(summary = "Get the structured entry for a file",
            description = "Fetch the structured record captured from an uploaded document")
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "Structured entry retrieved successfully"),
        @ApiResponse(responseCode = "403", description = "Access denied"),
        @ApiResponse(responseCode = "404", description = "File or structured entry not found")
    })
    public ResponseEntity<?> getStructuredEntry(@PathVariable Long fileId) {
        try {
            User currentUser = getCurrentUser();

            Optional<UserFileDTO> fileOpt = fileManagementService.getFile(fileId);
            if (fileOpt.isEmpty()) {
                return ResponseEntity.status(HttpStatus.NOT_FOUND)
                        .body(Map.of("error", "File not found"));
            }
            if (!hasAccessToFile(currentUser, fileOpt.get())) {
                return ResponseEntity.status(HttpStatus.FORBIDDEN)
                        .body(Map.of("error", "Not authorized to access this file"));
            }

            Optional<StructuredDocumentEntryDTO> entry =
                    fileManagementService.getStructuredEntryForFile(fileId);
            if (entry.isEmpty()) {
                return ResponseEntity.status(HttpStatus.NOT_FOUND)
                        .body(Map.of("error", "No structured entry exists for this file"));
            }
            return ResponseEntity.ok(Map.of(
                    "data", entry.get(),
                    "message", "Structured entry retrieved successfully"));

        } catch (Exception e) {
            log.error("Error getting structured entry for file: {}", fileId, e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body(Map.of("error", "Failed to get structured entry"));
        }
    }

    /**
     * Update an existing structured entry (the link to the original file is immutable).
     */
    @RequirePermission(Permission.RECORD_HEALTH_DATA)

    @PutMapping("/structured-entries/{entryId}")
    @Operation(summary = "Update a structured entry",
            description = "Edit the captured fields, document type or context of a structured record. "
                    + "The same completeness rules as creation apply.")
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "Structured entry updated successfully"),
        @ApiResponse(responseCode = "400", description = "Missing context, unsupported document type, or incomplete required fields"),
        @ApiResponse(responseCode = "403", description = "Access denied"),
        @ApiResponse(responseCode = "404", description = "Structured entry not found")
    })
    public ResponseEntity<?> updateStructuredEntry(
            @PathVariable Long entryId,
            @RequestBody StructuredEntryRequest request) {
        try {
            User currentUser = getCurrentUser();

            // Authorize against the linked file before applying any change.
            Optional<StructuredDocumentEntryDTO> existingOpt =
                    fileManagementService.getStructuredEntry(entryId);
            if (existingOpt.isEmpty()) {
                return ResponseEntity.status(HttpStatus.NOT_FOUND)
                        .body(Map.of("error", "Structured entry not found"));
            }
            Optional<UserFileDTO> fileOpt = fileManagementService.getFile(existingOpt.get().getFileId());
            if (fileOpt.isEmpty()) {
                return ResponseEntity.status(HttpStatus.NOT_FOUND)
                        .body(Map.of("error", "Linked file not found"));
            }
            ResponseEntity<?> denied = checkStructuredEntryAccess(currentUser, fileOpt.get(), request);
            if (denied != null) {
                return denied;
            }

            StructuredDocumentEntryDTO entry =
                    fileManagementService.updateStructuredEntry(entryId, request, currentUser.getId());
            return ResponseEntity.ok(Map.of(
                    "data", entry,
                    "message", "Structured entry updated successfully"));

        } catch (IllegalArgumentException e) {
            return ResponseEntity.badRequest().body(Map.of("error", e.getMessage()));
        } catch (Exception e) {
            log.error("Error updating structured entry: {}", entryId, e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body(Map.of("error", "Failed to update structured entry"));
        }
    }

    /**
     * List structured entries linked to a patient (care-circle context).
     */
    @RequirePermission(Permission.VIEW_HEALTH_DATA)

    @GetMapping("/structured-entries/patient/{patientId}")
    @Operation(summary = "List structured entries for a patient",
            description = "List structured document records linked to a patient / care circle")
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "Structured entries retrieved successfully"),
        @ApiResponse(responseCode = "403", description = "Access denied")
    })
    public ResponseEntity<?> listPatientStructuredEntries(@PathVariable Long patientId) {
        try {
            User currentUser = getCurrentUser();
            if (!hasAccessToPatient(currentUser, patientId)) {
                return ResponseEntity.status(HttpStatus.FORBIDDEN)
                        .body(Map.of("error", "Not authorized to access this patient's structured entries"));
            }
            List<StructuredDocumentEntryDTO> entries =
                    fileManagementService.listStructuredEntriesForPatient(patientId);
            return ResponseEntity.ok(Map.of(
                    "data", entries,
                    "message", "Structured entries retrieved successfully"));
        } catch (Exception e) {
            log.error("Error listing structured entries for patientId: {}", patientId, e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body(Map.of("error", "Failed to list structured entries"));
        }
    }

    /**
     * Download a file by ID
     */
    @RequirePermission(Permission.VIEW_HEALTH_DATA)

    @GetMapping("/{fileId}/download")
    @Operation(summary = "Download a file", description = "Download file content by file ID")
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "File downloaded successfully"),
        @ApiResponse(responseCode = "403", description = "Access denied"),
        @ApiResponse(responseCode = "404", description = "File not found")
    })
    public ResponseEntity<?> downloadFile(@PathVariable Long fileId) {
        try {
            User currentUser = getCurrentUser();
            
            // Get file metadata
            Optional<UserFileDTO> fileOpt = fileManagementService.getFile(fileId);
            if (fileOpt.isEmpty()) {
                return ResponseEntity.notFound().build();
            }
            
            UserFileDTO fileDto = fileOpt.get();
            
            // Check access permissions
            if (!hasAccessToFile(currentUser, fileDto)) {
                return ResponseEntity.status(HttpStatus.FORBIDDEN)
                        .body(Map.of("error", "Not authorized to access this file"));
            }
            
            // Download file content
            byte[] content = fileManagementService.downloadFile(fileId);
            
            return ResponseEntity.ok()
                    .contentType(MediaType.parseMediaType(fileDto.getContentType()))
                    .header(HttpHeaders.CONTENT_DISPOSITION, 
                            "attachment; filename=\"" + fileDto.getOriginalFilename() + "\"")
                    .body(content);
                    
        } catch (Exception e) {
            log.error("Error downloading file: {}", fileId, e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body(Map.of("error", "Failed to download file"));
        }
    }
    
    /**
     * List files for current user
     */
    @RequirePermission(Permission.VIEW_HEALTH_DATA)

    @GetMapping("/my-files")
    @Operation(summary = "List my files", description = "List files owned by the current user")
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "Files retrieved successfully"),
        @ApiResponse(responseCode = "401", description = "Authentication required")
    })
    public ResponseEntity<?> listMyFiles(
            @Parameter(description = "Filter by file category") 
            @RequestParam(value = "category", required = false) String category) {
        try {
            User currentUser = getCurrentUser();
            String userType = currentUser.getRole().name();
            
            List<UserFileDTO> files = fileManagementService.listUserFiles(
                    currentUser.getId(), userType, category);
            
            return ResponseEntity.ok(Map.of(
                    "data", files,
                    "message", "Files retrieved successfully"
            ));
            
        } catch (Exception e) {
            log.error("Error listing user files", e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body(Map.of("error", "Failed to list files"));
        }
    }
    
    /**
     * List files for a specific patient
     */
    @RequirePermission(Permission.VIEW_HEALTH_DATA)

    @GetMapping("/patient/{patientId}")
    @Operation(summary = "List patient files", description = "List files associated with a specific patient")
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "Patient files retrieved successfully"),
        @ApiResponse(responseCode = "403", description = "Access denied"),
        @ApiResponse(responseCode = "404", description = "Patient not found")
    })
    public ResponseEntity<?> listPatientFiles(
            @PathVariable Long patientId,
            @Parameter(description = "Filter by file category")
            @RequestParam(value = "category", required = false) String category) {
        try {
            User currentUser = getCurrentUser();
            
            // Check access to patient
            if (!hasAccessToPatient(currentUser, patientId)) {
                return ResponseEntity.status(HttpStatus.FORBIDDEN)
                        .body(Map.of("error", "Not authorized to access this patient's files"));
            }
            
            List<UserFileDTO> files;
            if (currentUser.getRole() == Role.PATIENT) {
                files = fileManagementService.listFilesForPatient(patientId, category);
            } else {
                files = fileManagementService.listFilesForCaregiverPatient(patientId, category);
            }
            
            return ResponseEntity.ok(Map.of(
                    "data", files,
                    "message", "Patient files retrieved successfully"
            ));
            
        } catch (Exception e) {
            log.error("Error listing patient files for patientId: {}", patientId, e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body(Map.of("error", "Failed to list patient files"));
        }
    }
    
    /**
     * Delete a file
     */
    @RequirePermission(Permission.RECORD_HEALTH_DATA)

    @DeleteMapping("/{fileId}")
    @Operation(summary = "Delete a file", description = "Delete a file by ID")
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "File deleted successfully"),
        @ApiResponse(responseCode = "403", description = "Access denied"),
        @ApiResponse(responseCode = "404", description = "File not found")
    })
    public ResponseEntity<?> deleteFile(@PathVariable Long fileId) {
        try {
            User currentUser = getCurrentUser();
            
            // Get file to check ownership
            Optional<UserFileDTO> fileOpt = fileManagementService.getFile(fileId);
            if (fileOpt.isEmpty()) {
                return ResponseEntity.status(HttpStatus.NOT_FOUND)
                        .body(Map.of("error", "File not found"));
            }
            
            UserFileDTO fileDto = fileOpt.get();
            if (!fileDto.getOwnerId().equals(currentUser.getId())) {
                return ResponseEntity.status(HttpStatus.FORBIDDEN)
                        .body(Map.of("error", "Not authorized to delete this file"));
            }
            
            fileManagementService.deleteFile(fileId, currentUser.getId());
            
            return ResponseEntity.ok(Map.of(
                    "message", "File deleted successfully"
            ));
            
        } catch (Exception e) {
            log.error("Error deleting file: {}", fileId, e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body(Map.of("error", "Failed to delete file"));
        }
    }
    
    /**
     * Get user's profile image
     */
    @RequirePermission(Permission.VIEW_HEALTH_DATA)

    @GetMapping("/profile-image")
    @Operation(summary = "Get profile image", description = "Get current user's profile image")
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "Profile image retrieved"),
        @ApiResponse(responseCode = "404", description = "No profile image found")
    })
    public ResponseEntity<?> getProfileImage() {
        try {
            User currentUser = getCurrentUser();
            String userType = currentUser.getRole().name();
            
            Optional<UserFileDTO> profileImage = fileManagementService.getUserProfileImage(
                    currentUser.getId(), userType);
            
            if (profileImage.isEmpty()) {
                return ResponseEntity.status(HttpStatus.NOT_FOUND)
                        .body(Map.of("error", "No profile image found"));
            }
            
            return ResponseEntity.ok(Map.of(
                    "data", profileImage.get(),
                    "message", "Profile image retrieved successfully"
            ));
            
        } catch (Exception e) {
            log.error("Error getting profile image", e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body(Map.of("error", "Failed to get profile image"));
        }
    }
    
    // ==================== S3 ENDPOINTS ====================

    @RequirePermission(Permission.RECORD_HEALTH_DATA)


    @PostMapping("/users/{userId}/upload")
    @Operation(summary = "Upload file for user", description = "S3-based file upload (maintained for backward compatibility)")
    public ResponseEntity<?> uploadFileLegacy(
            @PathVariable Long userId,
            @RequestParam("file") MultipartFile file,
            @RequestParam(value = "category", defaultValue = "documents") String category) {
        
        try {
            log.info("Upload request for user ID: {}, category: {}", userId, category);
            
            // Get user details from database
            User user = userRepository.findById(userId)
                .orElseThrow(() -> new RuntimeException("User not found: " + userId));
            
            // Get userType from user's role
            String userType = user.getRole().name();
            
            if (file.isEmpty()) {
                return ResponseEntity.badRequest()
                    .body(Map.of("error", "File is empty"));
            }
            
            if (file.getSize() > 10 * 1024 * 1024) {
                return ResponseEntity.badRequest()
                    .body(Map.of("error", "File size exceeds 10MB limit"));
            }
            
            // Use S3 or database based on configuration
            String filePath;
            String fileUrl;

            filePath = s3StorageService.uploadFile(file, userId, userType, category);
            fileUrl = s3StorageService.getFileUrl(filePath);

            
            log.info("File uploaded successfully: {} for user: {} ({})", filePath, userId, userType);
            
            return ResponseEntity.ok(Map.of(
                "message", "File uploaded successfully",
                "filePath", filePath,
                "fileUrl", fileUrl,
                "fileName", file.getOriginalFilename(),
                "userId", userId,
                "userType", userType,
                "category", category
            ));
            
        } catch (Exception e) {
            log.error("File upload failed for user {}: {}", userId, e.getMessage(), e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body(Map.of("error", "File upload failed: " + e.getMessage()));
        }
    }

    @RequirePermission(Permission.VIEW_HEALTH_DATA)


    @GetMapping("/users/{userId}/download/{*filePath}")
    @Operation(summary = "Download file", description = "S3-based file download")
    public ResponseEntity<byte[]> downloadFile(
            @PathVariable Long userId,
            @PathVariable String filePath) {
        try {
            // Verify user exists and get their role
            User user = userRepository.findById(userId)
                    .orElseThrow(() -> new RuntimeException("User not found: " + userId));

            String userType = user.getRole().name().toLowerCase();

            // Verify file belongs to this user
            String userPrefix = userType + "_" + userId;
            // Removing the leading slash
            filePath = filePath.substring(1);
            if (!filePath.startsWith(userPrefix)) {
                return ResponseEntity.status(HttpStatus.FORBIDDEN).build();
            }

            byte[] fileContent = s3StorageService.download(filePath);

            return ResponseEntity.ok()
                    .header("Content-Disposition", "attachment; filename=\"" + extractFileName(filePath) + "\"")
                    .body(fileContent);

        } catch (Exception e) {
            log.error("File download failed for user {}, path: {}", userId, filePath, e);
            return ResponseEntity.notFound().build();
        }
    }

    @RequirePermission(Permission.RECORD_HEALTH_DATA)


    @DeleteMapping("/users/{userId}/delete/{*filePath}")
    public ResponseEntity<?> deleteFile(
            @PathVariable Long userId,
            @PathVariable String filePath) {
        try {
            // Verify user exists and get their role
            User user = userRepository.findById(userId)
                    .orElseThrow(() -> new RuntimeException("User not found: " + userId));

            String userType = user.getRole().name().toLowerCase();

            // Verify file belongs to this user
            String userPrefix = userType + "_" + userId;
            // Removing the leading slash
            filePath = filePath.substring(1);
            if (!filePath.startsWith(userPrefix)) {
                return ResponseEntity.status(HttpStatus.FORBIDDEN)
                        .body(Map.of("error", "Access denied"));
            }

            s3StorageService.deleteFile(filePath);

            return ResponseEntity.ok(Map.of("message", "File deleted successfully"));

        } catch (Exception e) {
            log.error("File deletion failed for user {}, path: {}", userId, filePath, e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body(Map.of("error", "File deletion failed"));
        }
    }

    @RequirePermission(Permission.VIEW_HEALTH_DATA)


    @GetMapping("/users/{userId}/list")
    @Operation(summary = "List user files", description = "S3-based file listing")
    public ResponseEntity<?> listUserFiles(
            @PathVariable Long userId,
            @RequestParam(value = "category", required = false) String category) {
        try {
            // Verify user exists and get their role
            User user = userRepository.findById(userId)
                    .orElseThrow(() -> new RuntimeException("User not found: " + userId));

            String userType = user.getRole().name();

            List<UserFileDTO> files;
            if (useS3ForLegacyEndpoints && s3StorageService != null) {
                files = s3StorageService.listUserFilesDto(userId, userType);
                // Filter by category if specified
                if (category != null && !category.isEmpty()) {
                    files = files.stream()
                            .filter(file -> file.getS3FullKey() != null
                                    && file.getS3FullKey().contains("/" + category.toLowerCase() + "/"))
                            .toList();
                }
            } else {
                // Database-backed listing (dev/local; same source as /my-files).
                files = fileManagementService.listUserFiles(userId, userType, category);
            }

            return ResponseEntity.ok(Map.of(
                    "files", files,
                    "count", files.size(),
                    "userId", userId,
                    "userType", userType,
                    "userRole", user.getRole().name(),
                    "category", category != null ? category : "all"
            ));

        } catch (Exception e) {
            log.error("Failed to list files for user {}: {}", userId, e.getMessage(), e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body(Map.of("error", "Failed to list files"));
        }
    }

    @RequirePermission(Permission.VIEW_HEALTH_DATA)


    @GetMapping("/users/{userId}/categories")
    @Operation(summary = "[LEGACY] Get valid categories", description = "Get valid file categories for user role")
    public ResponseEntity<?> getValidCategories(@PathVariable Long userId) {
        try {
            User user = userRepository.findById(userId)
                .orElseThrow(() -> new RuntimeException("User not found: " + userId));
            
            var categories = getValidCategoriesForRole(user.getRole());
            
            return ResponseEntity.ok(Map.of(
                "categories", categories,
                "userType", user.getRole().name(),
                "userId", userId
            ));
            
        } catch (Exception e) {
            log.error("Failed to get categories for user {}: {}", userId, e.getMessage(), e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body(Map.of("error", "Failed to get categories"));
        }
    }

    // ==================== UTILITY METHODS ====================

    /**
     * Get the current authenticated user
     */
    private User getCurrentUser() {
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        String email = authentication.getName(); // In our system, username is usually email
        return userRepository.findByEmail(email)
                .orElseThrow(() -> new RuntimeException("Current user not found: " + email));
    }

    /**
     * Check if the current user has access to a specific patient
     */
    private boolean hasAccessToPatient(User currentUser, Long patientId) {
        if (currentUser.getRole() == Role.ADMIN) {
            return true;
        }
        
        if (currentUser.getRole() == Role.PATIENT) {
            return currentUser.getId().equals(patientId);
        }
        
        if (currentUser.getRole() == Role.CAREGIVER) {
            // Check if caregiver has access to this patient
            Optional<Patient> patient = patientRepository.findById(patientId);
            if (patient.isPresent()) {
                // Use the caregiverService to check access
                return caregiverService.hasAccessToPatient(currentUser.getId(), patientId);
            }
        }
        
        return false;
    }

    /**
     * Check if the current user has access to a specific file
     */
    private boolean hasAccessToFile(User currentUser, UserFileDTO fileDto) {
        // Admin has access to all files
        if (currentUser.getRole() == Role.ADMIN) {
            return true;
        }
        
        // Owner has access to their files
        if (fileDto.getOwnerId().equals(currentUser.getId())) {
            return true;
        }
        
        // If file is associated with a patient, check patient access
        if (fileDto.getPatientId() != null) {
            return hasAccessToPatient(currentUser, fileDto.getPatientId());
        }

        // Allow chat attachment recipients/senders to access files shared in their conversation
        if (messageRepository.existsAttachmentInUserConversation(fileDto.getId(), currentUser.getId())) {
            return true;
        }
        
        return false;
    }

    /**
     * Authorization for creating/updating a structured entry: the caller must be
     * able to access the linked file, any patient context must be a patient they
     * may act for, and a non-admin may only set the employee context to themselves.
     * Returns a 403 response when denied, or {@code null} when access is allowed.
     */
    private ResponseEntity<?> checkStructuredEntryAccess(User currentUser, UserFileDTO fileDto,
                                                         StructuredEntryRequest request) {
        if (!hasAccessToFile(currentUser, fileDto)) {
            return ResponseEntity.status(HttpStatus.FORBIDDEN)
                    .body(Map.of("error", "Not authorized to access this file"));
        }
        Long effectivePatientId = request.getPatientId() != null ? request.getPatientId() : fileDto.getPatientId();
        if (effectivePatientId != null && !hasAccessToPatient(currentUser, effectivePatientId)) {
            return ResponseEntity.status(HttpStatus.FORBIDDEN)
                    .body(Map.of("error", "Not authorized to create structured entries for this patient"));
        }
        if (request.getEmployeeUserId() != null
                && currentUser.getRole() != Role.ADMIN
                && !request.getEmployeeUserId().equals(currentUser.getId())) {
            return ResponseEntity.status(HttpStatus.FORBIDDEN)
                    .body(Map.of("error", "Not authorized to create structured entries for another employee"));
        }
        return null;
    }

    private List<String> getValidCategoriesForRole(Role role) {
        return switch (role) {
            case PATIENT -> List.of("profile", "documents", "medical-records", "prescriptions", 
                                            "insurance", "reports", "consent-forms", "emergency-contacts");
            case CAREGIVER -> List.of("profile", "certifications", "documents", "training", 
                                              "background-check", "references", "contracts");
            case FAMILY_MEMBER -> List.of("profile", "documents", "authorization");
            default -> List.of("documents");
        };
    }

    private String extractFileName(String filePath) {
        String[] parts = filePath.split("/");
        return parts[parts.length - 1];
    }

    /** Comma-separated, sorted list of valid intake document types (for error messages). */
    private static String employmentIntakeTypeNames() {
        return UserFile.FileCategory.EMPLOYMENT_INTAKE.stream()
                .map(Enum::name)
                .sorted()
                .collect(Collectors.joining(", "));
    }
}