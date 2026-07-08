package com.careconnect.service;

import com.careconnect.model.UserFile;
import com.careconnect.repository.UserFileRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.List;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
@Slf4j
public class DatabaseStorageService implements StorageService {
    
    private static final Logger log = LoggerFactory.getLogger(DatabaseStorageService.class);
    private final UserFileRepository userFileRepository;
    
    @Override
    public String upload(String path, byte[] content, String mimeType) {
        // For direct byte array uploads, we'll create a generic file entry
        // This method is mainly for backward compatibility
        try {
            UserFile userFile = UserFile.builder()
                    .filename(generateFilenameFromPath(path))
                    .originalFilename(generateFilenameFromPath(path))
                    .contentType(mimeType)
                    .fileSize((long) content.length)
                    .fileData(content)
                    .ownerId(extractUserIdFromPath(path))
                    .ownerType(extractOwnerTypeFromPath(path))
                    .fileCategory(UserFile.FileCategory.OTHER_DOCUMENT)
                    .storageType(UserFile.StorageType.DATABASE)
                    .description("Direct upload via API")
                    .build();
            
            UserFile saved = userFileRepository.save(userFile);
            log.info("File uploaded to database with ID: {}", saved.getId());
            
            return "db://files/" + saved.getId();
        } catch (Exception e) {
            log.error("Failed to upload file to database: {}", path, e);
            throw new RuntimeException("Failed to upload file to database", e);
        }
    }
    
    @Override
    public String uploadFile(MultipartFile file, Long userId, String userType, String category) {
        try {
            log.info("Starting database file upload for user: {}, type: {}, category: {}", 
                    userId, userType, category);
            
            if (file.isEmpty()) {
                throw new IllegalArgumentException("File is empty");
            }
            
            // Generate unique filename
            String filename = generateUniqueFilename(file.getOriginalFilename(), userId, userType, category);
            
            // Determine owner type and patient ID
            UserFile.OwnerType ownerType = UserFile.OwnerType.valueOf(userType.toUpperCase());
            UserFile.FileCategory fileCategory = mapCategoryToEnum(category);
            Long patientId = determinePatientId(userId, ownerType);
            
            // Create file entity
            UserFile userFile = UserFile.builder()
                    .filename(filename)
                    .originalFilename(file.getOriginalFilename())
                    .contentType(file.getContentType())
                    .fileSize(file.getSize())
                    .fileData(file.getBytes())
                    .ownerId(userId)
                    .ownerType(ownerType)
                    .fileCategory(fileCategory)
                    .patientId(patientId)
                    .storageType(UserFile.StorageType.DATABASE)
                    .description("Uploaded via web interface")
                    .build();
            
            UserFile saved = userFileRepository.save(userFile);
            log.info("File uploaded successfully to database: {} with ID: {}", filename, saved.getId());
            
            return "db://files/" + saved.getId();
            
        } catch (IOException e) {
            log.error("IOException during database file upload for user: {}", userId, e);
            throw new RuntimeException("Failed to upload file - IO Error", e);
        } catch (Exception e) {
            log.error("Failed to upload file to database for user: {}", userId, e);
            throw new RuntimeException("Failed to upload file to database: " + e.getMessage(), e);
        }
    }
    
    @Override
    public byte[] download(String path) {
        try {
            Long fileId = extractFileIdFromPath(path);
            UserFile userFile = userFileRepository.findById(fileId)
                    .orElseThrow(() -> new RuntimeException("File not found: " + path));
            
            if (!userFile.getIsActive()) {
                throw new RuntimeException("File has been deleted: " + path);
            }
            
            log.info("Downloaded file from database: ID={}, size={} bytes", fileId, userFile.getFileSize());
            return userFile.getFileData();
            
        } catch (Exception e) {
            log.error("Failed to download file from database: {}", path, e);
            throw new RuntimeException("Failed to download file from database", e);
        }
    }
    
    @Override
    public String getFileUrl(String path) {
        // For database storage, we'll return a URL that points to our download endpoint
        try {
            Long fileId = extractFileIdFromPath(path);
            return "/v1/api/files/" + fileId + "/download";
        } catch (Exception e) {
            log.error("Failed to generate file URL for path: {}", path, e);
            return path; // Return original path as fallback
        }
    }
    
    @Override
    public void deleteFile(String path) {
        try {
            Long fileId = extractFileIdFromPath(path);
            UserFile userFile = userFileRepository.findById(fileId)
                    .orElseThrow(() -> new RuntimeException("File not found: " + path));
            
            // Soft delete - mark as inactive
            userFile.setIsActive(false);
            userFileRepository.save(userFile);
            
            log.info("File soft deleted from database: ID={}", fileId);
            
        } catch (Exception e) {
            log.error("Failed to delete file from database: {}", path, e);
            throw new RuntimeException("Failed to delete file from database", e);
        }
    }
    
    @Override
    public List<String> listUserFiles(Long userId, String userType) {
        try {
            UserFile.OwnerType ownerType = UserFile.OwnerType.valueOf(userType.toUpperCase());
            List<UserFile> files = userFileRepository.findByOwnerIdAndOwnerTypeAndIsActiveTrue(userId, ownerType);
            
            return files.stream()
                    .map(file -> "db://files/" + file.getId())
                    .collect(Collectors.toList());
                    
        } catch (Exception e) {
            log.error("Failed to list files for user: {}", userId, e);
            throw new RuntimeException("Failed to list user files", e);
        }
    }
    
    // Helper methods
    private String generateUniqueFilename(String originalFilename, Long userId, String userType, String category) {
        String timestamp = LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyyMMdd_HHmmss"));
        String extension = getFileExtension(originalFilename);
        return String.format("%s_%d_%s_%s%s", userType.toLowerCase(), userId, category, timestamp, extension);
    }
    
    private String getFileExtension(String filename) {
        if (filename == null || !filename.contains(".")) {
            return "";
        }
        return filename.substring(filename.lastIndexOf("."));
    }
    
    /**
     * Map a client-supplied category string to the canonical {@link UserFile.FileCategory}.
     * Delegates to the single source of truth on the enum so files persisted through the
     * (default) database storage path are stored under the same category the user selected,
     * keeping the frontend and backend category models aligned.
     */
    private UserFile.FileCategory mapCategoryToEnum(String category) {
        return UserFile.FileCategory.fromClientValue(category);
    }
    
    private Long determinePatientId(Long userId, UserFile.OwnerType ownerType) {
        // For patients, the patient ID is derived from the user ID
        // For caregivers and family members, we might need to look up the patient they're associated with
        // For now, we'll handle the patient case and leave others as null
        if (ownerType == UserFile.OwnerType.PATIENT) {
            // You might need to implement a service to get patient ID from user ID
            return userId; // Simplified assumption
        }
        return null; // Will need to be set by the calling service for caregivers/family members
    }
    
    private Long extractFileIdFromPath(String path) {
        // Expected format: "db://files/123" or just "123"
        if (path.startsWith("db://files/")) {
            return Long.parseLong(path.substring("db://files/".length()));
        }
        try {
            return Long.parseLong(path);
        } catch (NumberFormatException e) {
            throw new IllegalArgumentException("Invalid file path format: " + path);
        }
    }
    
    private String generateFilenameFromPath(String path) {
        // Extract filename from path or generate a default one
        if (path.contains("/")) {
            return path.substring(path.lastIndexOf("/") + 1);
        }
        return "uploaded_file_" + System.currentTimeMillis();
    }
    
    private Long extractUserIdFromPath(String path) {
        // Try to extract user ID from path format like "user_123/file"
        try {
            if (path.contains("user_")) {
                String userPart = path.substring(path.indexOf("user_") + 5);
                if (userPart.contains("/")) {
                    userPart = userPart.substring(0, userPart.indexOf("/"));
                }
                return Long.parseLong(userPart);
            }
        } catch (Exception e) {
            log.warn("Could not extract user ID from path: {}", path);
        }
        return 1L; // Default fallback
    }
    
    private UserFile.OwnerType extractOwnerTypeFromPath(String path) {
        if (path.contains("patient")) return UserFile.OwnerType.PATIENT;
        if (path.contains("caregiver")) return UserFile.OwnerType.CAREGIVER;
        if (path.contains("family")) return UserFile.OwnerType.FAMILY_MEMBER;
        return UserFile.OwnerType.PATIENT; // Default
    }
}
