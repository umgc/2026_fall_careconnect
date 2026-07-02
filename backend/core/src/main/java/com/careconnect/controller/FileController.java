package com.careconnect.controller;

import com.careconnect.security.Permission;
import com.careconnect.security.RequirePermission;

import com.careconnect.dto.FileUploadResponse;
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
            
            // Validate patient access if patientId is specified
            if (patientId != null && !hasAccessToPatient(currentUser, patientId)) {
                return ResponseEntity.status(HttpStatus.FORBIDDEN)
                        .body(Map.of("error", "Not authorized to upload files for this patient"));
            }
            
            String userType = currentUser.getRole().name();
            FileUploadResponse response = fileManagementService.uploadFile(
                    file, currentUser.getId(), userType, category, description, patientId);
            
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
}