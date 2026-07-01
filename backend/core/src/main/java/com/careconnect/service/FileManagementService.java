package com.careconnect.service;

import com.careconnect.dto.UserFileDTO;
import com.careconnect.dto.FileUploadResponse;
import com.careconnect.model.UserFile;
import com.careconnect.model.Patient;
import com.careconnect.model.User;
import com.careconnect.repository.UserFileRepository;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.UserRepository;
import lombok.extern.slf4j.Slf4j;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;
import java.util.List;
import java.util.Optional;
import java.util.stream.Collectors;

//@Service
@Slf4j
@Transactional
@Service
public class FileManagementService {

    private static final Logger log = LoggerFactory.getLogger(FileManagementService.class);
    private final UserFileRepository userFileRepository;
    private final UserRepository userRepository;
    private final PatientRepository patientRepository;
    private final DatabaseStorageService databaseStorageService;
    private final S3StorageService s3StorageService;

    @Autowired
    public FileManagementService(UserFileRepository userFileRepository,
                               UserRepository userRepository,
                               PatientRepository patientRepository,
                               DatabaseStorageService databaseStorageService,
                               @Autowired(required = false) S3StorageService s3StorageService) {
        this.userFileRepository = userFileRepository;
        this.userRepository = userRepository;
        this.patientRepository = patientRepository;
        this.databaseStorageService = databaseStorageService;
        this.s3StorageService = s3StorageService;
    }
    
    @Value("${app.file.storage.default:database}")
    private String defaultStorageType;
    
    @Value("${app.file.storage.use-s3:false}")
    private boolean useS3ForNewFiles;
    
    /**
     * Upload a file for a user
     */
    public FileUploadResponse uploadFile(MultipartFile file, Long userId, String userType, 
                                       String category, String description, Long patientId) {
        try {
            log.info("Uploading file for user: {}, type: {}, category: {}", userId, userType, category);
            
            // Validate file
            validateFile(file);
            // No access control or ownership checks; all uploads are allowed for now
            
            // Determine storage service - fall back to database if S3 is not available
            StorageService storageService = (useS3ForNewFiles && s3StorageService != null) ? s3StorageService : databaseStorageService;
            
            // Upload file
            String filePath = storageService.uploadFile(file, userId, userType, category);
            
            // Create file metadata record (for database storage, this might be redundant, but keeps consistency)
            UserFile userFile = UserFile.builder()
                    .filename(generateUniqueFilename(file.getOriginalFilename(), userId, userType, category))
                    .originalFilename(file.getOriginalFilename())
                    .contentType(file.getContentType())
                    .fileSize(file.getSize())
                    .ownerId(userId)
                    .ownerType(UserFile.OwnerType.valueOf(userType.toUpperCase()))
                    .fileCategory(mapCategoryToEnum(category))
                    .patientId(patientId != null ? patientId : determinePatientId(userId, userType))
                    .storageType((useS3ForNewFiles && s3StorageService != null) ? UserFile.StorageType.S3 : UserFile.StorageType.DATABASE)
                    .s3Path((useS3ForNewFiles && s3StorageService != null) ? filePath : null)
                    .description(description)
                    .build();
            
            // For database storage, we need to update the record that was already created
            if (!(useS3ForNewFiles && s3StorageService != null)) {
                Long fileId = extractFileIdFromPath(filePath);
                Optional<UserFile> existingFile = userFileRepository.findById(fileId);
                if (existingFile.isPresent()) {
                    UserFile existing = existingFile.get();
                    existing.setDescription(description);
                    existing.setPatientId(patientId != null ? patientId : determinePatientId(userId, userType));
                    userFile = userFileRepository.save(existing);
                } else {
                    userFile = userFileRepository.save(userFile);
                }
            } else {
                userFile = userFileRepository.save(userFile);
            }
            
            // Handle profile image updates
            if (UserFile.FileCategory.PROFILE_IMAGE.name().equals(category.toUpperCase())) {
                updateUserProfileImage(userId, filePath);
            }
            
            return FileUploadResponse.builder()
                    .fileId(userFile.getId())
                    .filename(userFile.getFilename())
                    .originalFilename(userFile.getOriginalFilename())
                    .fileUrl(storageService.getFileUrl(filePath))
                    .contentType(userFile.getContentType())
                    .fileSize(userFile.getFileSize())
                    .category(userFile.getFileCategory().name())
                    .uploadedAt(userFile.getUploadedAt())
                    .message("File uploaded successfully")
                    .build();
                    
        } catch (Exception e) {
            log.error("Failed to upload file for user: {}", userId, e);
            throw new RuntimeException("Failed to upload file: " + e.getMessage(), e);
        }
    }
    
    /**
     * Store an application-generated document (e.g., a submitted form's PDF copy)
     * as a database-backed {@link UserFile} owned by {@code ownerId}. The file
     * then appears in that user's File Management ("My Files").
     */
    public UserFile storeGeneratedDocument(byte[] data,
                                           String originalFilename,
                                           String contentType,
                                           Long ownerId,
                                           UserFile.OwnerType ownerType,
                                           String category,
                                           String description,
                                           Long patientId) {
        UserFile userFile = UserFile.builder()
                .filename(generateUniqueFilename(originalFilename, ownerId, ownerType.name(), category))
                .originalFilename(originalFilename)
                .contentType(contentType)
                .fileSize((long) data.length)
                .fileData(data)
                .ownerId(ownerId)
                .ownerType(ownerType)
                .fileCategory(mapCategoryToEnum(category))
                .patientId(patientId)
                .storageType(UserFile.StorageType.DATABASE)
                .description(description)
                .build();
        UserFile saved = userFileRepository.save(userFile);
        log.info("Stored generated document {} ({} bytes) for {} {}",
                saved.getId(), data.length, ownerType, ownerId);
        return saved;
    }

    /**
     * Get file by ID
     */
    public Optional<UserFileDTO> getFile(Long fileId) {
        return userFileRepository.findById(fileId)
                .filter(UserFile::getIsActive)
                .map(this::mapToDTO);
    }
    
    /**
     * Download file content
     */
    public byte[] downloadFile(Long fileId) {
        UserFile userFile = userFileRepository.findById(fileId)
                .filter(UserFile::getIsActive)
                .orElseThrow(() -> new RuntimeException("File not found: " + fileId));
        
        if (userFile.getStorageType() == UserFile.StorageType.DATABASE) {
            return userFile.getFileData();
        } else {
            // File is in S3
            if (s3StorageService == null) {
                throw new RuntimeException("S3 storage service not available, but file is stored in S3");
            }
            return s3StorageService.download(userFile.getS3Path());
        }
    }
    
    /**
     * List files for a user
     */
    public List<UserFileDTO> listUserFiles(Long userId, String userType, String category) {
        UserFile.OwnerType ownerType = UserFile.OwnerType.valueOf(userType.toUpperCase());
        
        List<UserFile> files;
        if (category != null && !category.isEmpty()) {
            UserFile.FileCategory fileCategory = mapCategoryToEnum(category);
            files = userFileRepository.findByOwnerIdAndOwnerTypeAndFileCategoryAndIsActiveTrue(
                    userId, ownerType, fileCategory);
        } else {
            files = userFileRepository.findByOwnerIdAndOwnerTypeAndIsActiveTrue(userId, ownerType);
        }
        
        return files.stream()
                .map(this::mapToDTO)
                .collect(Collectors.toList());
    }
    
    /**
     * List files accessible by a patient (includes files from caregivers/family)
     */
    public List<UserFileDTO> listFilesForPatient(Long patientId, String category) {
        List<UserFile> files;
        if (category != null && !category.isEmpty()) {
            UserFile.FileCategory fileCategory = mapCategoryToEnum(category);
            files = userFileRepository.findByPatientIdAndFileCategory(patientId, fileCategory);
        } else {
            files = userFileRepository.findFilesAccessibleByPatient(patientId);
        }
        
        return files.stream()
                .map(this::mapToDTO)
                .collect(Collectors.toList());
    }
    
    /**
     * List files accessible by caregiver for a specific patient
     */
    public List<UserFileDTO> listFilesForCaregiverPatient(Long patientId, String category) {
        List<UserFile> files;
        if (category != null && !category.isEmpty()) {
            UserFile.FileCategory fileCategory = mapCategoryToEnum(category);
            files = userFileRepository.findByPatientIdAndFileCategory(patientId, fileCategory);
        } else {
            files = userFileRepository.findFilesAccessibleByCaregiverForPatient(patientId);
        }
        
        return files.stream()
                .map(this::mapToDTO)
                .collect(Collectors.toList());
    }
    
    /**
     * Delete file
     */
    public void deleteFile(Long fileId, Long userId) {
        UserFile userFile = userFileRepository.findById(fileId)
                .orElseThrow(() -> new RuntimeException("File not found: " + fileId));


        // Soft delete
        userFile.setIsActive(false);
        userFileRepository.save(userFile);

        // If it's a profile image, clear the user's profile image URL
        if (userFile.getFileCategory() == UserFile.FileCategory.PROFILE_IMAGE) {
            clearUserProfileImage(userFile.getOwnerId());
        }

        log.info("File deleted: ID={}, owner={}", fileId, userFile.getOwnerId());
    }
    
    /**
     * Get user's profile image
     */
    public Optional<UserFileDTO> getUserProfileImage(Long userId, String userType) {
        UserFile.OwnerType ownerType = UserFile.OwnerType.valueOf(userType.toUpperCase());
        return userFileRepository.findFirstByOwnerIdAndOwnerTypeAndFileCategoryAndIsActiveTrue(
                userId, ownerType, UserFile.FileCategory.PROFILE_IMAGE)
                .map(this::mapToDTO);
    }
    
    // Helper methods
    private void validateFile(MultipartFile file) {
        if (file.isEmpty()) {
            throw new IllegalArgumentException("File is empty");
        }
        
        // Add size validation (e.g., max 10MB)
        long maxSize = 10 * 1024 * 1024; // 10MB
        if (file.getSize() > maxSize) {
            throw new IllegalArgumentException("File size exceeds maximum allowed size of 10MB");
        }
        
        // Add content type validation if needed
        String contentType = file.getContentType();
        if (contentType == null) {
            throw new IllegalArgumentException("File content type is unknown");
        }
    }
    
    private String generateUniqueFilename(String originalFilename, Long userId, String userType, String category) {
        String timestamp = String.valueOf(System.currentTimeMillis());
        String extension = getFileExtension(originalFilename);
        return String.format("%s_%d_%s_%s%s", userType.toLowerCase(), userId, category, timestamp, extension);
    }
    
    private String getFileExtension(String filename) {
        if (filename == null || !filename.contains(".")) {
            return "";
        }
        return filename.substring(filename.lastIndexOf("."));
    }
    
    private UserFile.FileCategory mapCategoryToEnum(String category) {
        if (category == null) {
            return UserFile.FileCategory.OTHER_DOCUMENT;
        }
        
        return switch (category.toUpperCase()) {
            case "PROFILE_IMAGE", "PROFILE" -> UserFile.FileCategory.PROFILE_IMAGE;
            case "MEDICAL_RECORD", "MEDICAL" -> UserFile.FileCategory.MEDICAL_RECORD;
            case "CLINICAL_NOTE", "CLINICAL" -> UserFile.FileCategory.CLINICAL_NOTE;
            case "PRESCRIPTION" -> UserFile.FileCategory.PRESCRIPTION;
            case "LAB_RESULT", "LAB" -> UserFile.FileCategory.LAB_RESULT;
            case "INSURANCE_DOCUMENT", "INSURANCE" -> UserFile.FileCategory.INSURANCE_DOCUMENT;
            case "CONSENT_FORM", "CONSENT" -> UserFile.FileCategory.CONSENT_FORM;
            case "CARE_PLAN", "CARE" -> UserFile.FileCategory.CARE_PLAN;
            case "ONBOARDING_FORM", "ONBOARDING" -> UserFile.FileCategory.ONBOARDING_FORM;
            case "HIRING_DOCUMENT", "HIRING" -> UserFile.FileCategory.HIRING_DOCUMENT;
            default -> UserFile.FileCategory.OTHER_DOCUMENT;
        };
    }
    
    private Long determinePatientId(Long userId, String userType) {
        if ("PATIENT".equals(userType.toUpperCase())) {
            // Find patient by user ID
            Optional<Patient> patient = patientRepository.findByUser(
                    userRepository.findById(userId).orElse(null));
            return patient.map(Patient::getId).orElse(null);
        }
        return null; // For caregivers/family members, this should be set explicitly
    }
    
    private void updateUserProfileImage(Long userId, String filePath) {
        try {
            Optional<User> userOpt = userRepository.findById(userId);
            if (userOpt.isPresent()) {
                User user = userOpt.get();
                String imageUrl = (useS3ForNewFiles && s3StorageService != null) ? s3StorageService.getFileUrl(filePath) :
                                 databaseStorageService.getFileUrl(filePath);
                user.setProfileImageUrl(imageUrl);
                userRepository.save(user);
                log.info("Updated profile image URL for user: {}", userId);
            }
        } catch (Exception e) {
            log.error("Failed to update profile image URL for user: {}", userId, e);
        }
    }
    
    private void clearUserProfileImage(Long userId) {
        try {
            Optional<User> userOpt = userRepository.findById(userId);
            if (userOpt.isPresent()) {
                User user = userOpt.get();
                user.setProfileImageUrl(null);
                userRepository.save(user);
                log.info("Cleared profile image URL for user: {}", userId);
            }
        } catch (Exception e) {
            log.error("Failed to clear profile image URL for user: {}", userId, e);
        }
    }
    
    private Long extractFileIdFromPath(String path) {
        if (path.startsWith("db://files/")) {
            return Long.parseLong(path.substring("db://files/".length()));
        }
        return null;
    }
    
    private UserFileDTO mapToDTO(UserFile userFile) {
        String fileUrl;
        if (userFile.getStorageType() == UserFile.StorageType.DATABASE) {
            fileUrl = databaseStorageService.getFileUrl("db://files/" + userFile.getId());
        } else {
            if (s3StorageService == null) {
                fileUrl = "unavailable://s3-service-not-configured";
            } else {
                fileUrl = s3StorageService.getFileUrl(userFile.getS3Path());
            }
        }
        
        return UserFileDTO.builder()
                .id(userFile.getId())
                .filename(userFile.getFilename())
                .originalFilename(userFile.getOriginalFilename())
                .contentType(userFile.getContentType())
                .fileSize(userFile.getFileSize())
                .fileUrl(fileUrl)
                .ownerId(userFile.getOwnerId())
                .ownerType(userFile.getOwnerType().name())
                .fileCategory(userFile.getFileCategory().name())
                .patientId(userFile.getPatientId())
                .storageType(userFile.getStorageType().name())
                .description(userFile.getDescription())
                .uploadedAt(userFile.getUploadedAt())
                .updatedAt(userFile.getUpdatedAt())
                .build();
    }
}
