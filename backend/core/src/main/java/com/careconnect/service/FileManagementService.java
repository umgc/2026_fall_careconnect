package com.careconnect.service;

import com.careconnect.dto.UserFileDTO;
import com.careconnect.dto.FileUploadResponse;
import com.careconnect.dto.StructuredDocumentEntryDTO;
import com.careconnect.dto.StructuredEntryRequest;
import com.careconnect.dto.UploadedFileDTO;
import com.careconnect.indexing.DocumentIndexedPayload;
import com.careconnect.indexing.IndexingEventEmitter;
import com.careconnect.model.StructuredDocumentEntry;
import com.careconnect.model.UserFile;
import com.careconnect.model.Patient;
import com.careconnect.model.User;
import com.careconnect.repository.StructuredDocumentEntryRepository;
import com.careconnect.repository.UserFileRepository;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.UserRepository;
import com.careconnect.service.ai.ask.AskAiDocumentOcrService;
import com.careconnect.service.ai.indexing.RetrievalIndexService;
import com.careconnect.service.ai.retrieval.RetrievalRecordType;
import com.careconnect.util.ContentHashUtil;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.extern.slf4j.Slf4j;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.stream.Collectors;

//@Service
@Slf4j
@Transactional
@Service
public class FileManagementService {

    private static final Logger log = LoggerFactory.getLogger(FileManagementService.class);
    private static final ObjectMapper OBJECT_MAPPER = new ObjectMapper();
    private static final String DEFAULT_CONSENT_SCOPE = "on_consent";

    private final UserFileRepository userFileRepository;
    private final StructuredDocumentEntryRepository structuredEntryRepository;
    private final UserRepository userRepository;
    private final PatientRepository patientRepository;
    private final DatabaseStorageService databaseStorageService;
    private final S3StorageService s3StorageService;
    private final DocumentComplianceService documentComplianceService;
    private final IndexingEventEmitter indexingEventEmitter;
    private final RetrievalIndexService retrievalIndexService;
    private final DocumentProcessingService documentProcessingService;
    private final AskAiDocumentOcrService askAiDocumentOcrService;

    @Autowired
    public FileManagementService(UserFileRepository userFileRepository,
                               StructuredDocumentEntryRepository structuredEntryRepository,
                               UserRepository userRepository,
                               PatientRepository patientRepository,
                               DatabaseStorageService databaseStorageService,
                               DocumentComplianceService documentComplianceService,
                               IndexingEventEmitter indexingEventEmitter,
                               RetrievalIndexService retrievalIndexService,
                               DocumentProcessingService documentProcessingService,
                               @Autowired(required = false) S3StorageService s3StorageService,
                               AskAiDocumentOcrService askAiDocumentOcrService) {
        this.userFileRepository = userFileRepository;
        this.structuredEntryRepository = structuredEntryRepository;
        this.userRepository = userRepository;
        this.patientRepository = patientRepository;
        this.databaseStorageService = databaseStorageService;
        this.documentComplianceService = documentComplianceService;
        this.indexingEventEmitter = indexingEventEmitter;
        this.retrievalIndexService = retrievalIndexService;
        this.documentProcessingService = documentProcessingService;
        this.s3StorageService = s3StorageService;
        this.askAiDocumentOcrService = askAiDocumentOcrService;
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
            
            // Handle profile image updates (resolve aliases so PROFILE/PROFILE_PICTURE also match)
            if (mapCategoryToEnum(category) == UserFile.FileCategory.PROFILE_IMAGE) {
                updateUserProfileImage(userId, filePath);
            }

            // Compliance tracking: an uploaded required document moves its
            // checklist entry forward (MISSING -> IN_PROGRESS), audited with
            // the uploader and filename. Never fails the upload itself.
            documentComplianceService.recordDocumentUploaded(userFile, userId);

            tryExtractAndPersistText(userFile, file);
            emitDocumentIndexed(userFile);
            
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
        emitDocumentIndexed(saved);
        return saved;
    }

    /**
     * Emits {@code DOCUMENT_INDEXED} for Ask AI when a patient-scoped file has description
     * and/or extracted plain text. Best-effort: indexing failures must not fail the upload.
     */
    private void emitDocumentIndexed(final UserFile file) {
        if (file == null || file.getId() == null || file.getPatientId() == null) {
            return;
        }
        final String excerpt = indexableDocumentText(file);
        if (excerpt == null || excerpt.isBlank()) {
            return;
        }
        try {
            final String category = file.getFileCategory() == null
                    ? null
                    : file.getFileCategory().name();
            indexingEventEmitter.emitDocumentIndexed(new DocumentIndexedPayload(
                    file.getId(),
                    file.getPatientId(),
                    ContentHashUtil.sha256(excerpt),
                    category,
                    excerpt,
                    DEFAULT_CONSENT_SCOPE));
        } catch (Exception e) {
            log.warn("Failed to emit DOCUMENT_INDEXED for fileId {}: {}",
                    file.getId(), e.getMessage(), e);
        }
    }

    public static String indexableDocumentText(final UserFile file) {
        if (file == null) {
            return null;
        }
        final String extracted = file.getExtractedText() == null ? "" : file.getExtractedText().trim();
        final String description = file.getDescription() == null ? "" : file.getDescription().trim();
        if (!extracted.isBlank() && !description.isBlank()) {
            if (extracted.contains(description)) {
                return extracted;
            }
            return description + "\n\n" + extracted;
        }
        if (!extracted.isBlank()) {
            return extracted;
        }
        return description.isBlank() ? null : description;
    }

    private void tryExtractAndPersistText(final UserFile userFile, final MultipartFile file) {
        if (userFile == null || file == null || documentProcessingService == null) {
            return;
        }
        try {
            final byte[] bytes = file.getBytes();
            if (bytes == null || bytes.length == 0) {
                return;
            }
            final String base64 = java.util.Base64.getEncoder().encodeToString(bytes);
            final UploadedFileDTO dto = UploadedFileDTO.builder()
                    .filename(file.getOriginalFilename() == null
                            ? userFile.getOriginalFilename()
                            : file.getOriginalFilename())
                    .contentType(file.getContentType())
                    .content(base64)
                    .build();
            final String extracted = documentProcessingService.extractTextContent(dto);
            if (!isExtractFailurePlaceholder(extracted)) {
                userFile.setExtractedText(extracted);
                userFileRepository.save(userFile);
                return;
            }
            // Local extractors miss scanned PDFs / images — enqueue async Textract OCR
            // after the upload transaction commits (see AskAiDocumentOcrService).
            if (askAiDocumentOcrService != null) {
                askAiDocumentOcrService.enqueueAfterFailedExtract(userFile);
            }
        } catch (Exception e) {
            log.warn("Document text extraction skipped for fileId {}: {}",
                    userFile.getId(), e.getMessage());
            try {
                if (askAiDocumentOcrService != null) {
                    askAiDocumentOcrService.enqueueAfterFailedExtract(userFile);
                }
            } catch (Exception ocrError) {
                log.warn("Ask AI document OCR enqueue skipped for fileId {}: {}",
                        userFile.getId(), ocrError.getMessage());
            }
        }
    }

    /**
     * True when {@link DocumentProcessingService} returned a bracketed failure/empty
     * sentinel rather than real document text. Avoids the overly broad
     * {@code startsWith("[")} check that would drop legitimate content like citations.
     */
    static boolean isExtractFailurePlaceholder(final String extracted) {
        if (extracted == null || extracted.isBlank()) {
            return true;
        }
        final String text = extracted.trim();
        if (!text.startsWith("[")) {
            return false;
        }
        return text.startsWith("[Error ")
                || text.startsWith("[Unable to extract")
                || text.startsWith("[Empty ")
                || text.startsWith("[Binary file:")
                || text.startsWith("[File contains no extractable")
                || text.contains(" contains no extractable text:");
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

        if (userFile.getPatientId() != null) {
            try {
                retrievalIndexService.removeIndexedSource(
                        userFile.getPatientId(),
                        String.valueOf(userFile.getId()),
                        RetrievalRecordType.UPLOADED_DOCUMENT);
            } catch (Exception e) {
                log.warn("Failed to de-index uploaded document {}: {}", fileId, e.getMessage(), e);
            }
        }

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
    
    /**
     * List employment / home-care intake documents owned by a user (e.g. a caregiver's
     * hiring and onboarding forms).
     */
    public List<UserFileDTO> listEmploymentDocumentsForUser(Long userId, String userType) {
        UserFile.OwnerType ownerType = UserFile.OwnerType.valueOf(userType.toUpperCase());
        return userFileRepository
                .findByOwnerIdAndOwnerTypeAndFileCategoryInAndIsActiveTrue(
                        userId, ownerType, UserFile.FileCategory.EMPLOYMENT_INTAKE)
                .stream()
                .map(this::mapToDTO)
                .collect(Collectors.toList());
    }

    /**
     * List employment / home-care intake documents linked to a specific patient
     * (the care recipient at the center of a care circle).
     */
    public List<UserFileDTO> listEmploymentDocumentsForPatient(Long patientId) {
        return userFileRepository
                .findByPatientIdAndFileCategoryInAndIsActiveTrue(
                        patientId, UserFile.FileCategory.EMPLOYMENT_INTAKE)
                .stream()
                .map(this::mapToDTO)
                .collect(Collectors.toList());
    }

    // ==================== STRUCTURED FORM ENTRIES ====================

    /**
     * Create a structured form entry for an uploaded document. The original file
     * remains linked to the record as supporting evidence. Fails with
     * {@link IllegalArgumentException} when the document type is unsupported,
     * neither patient nor employee context is supplied, or required fields are
     * missing (see {@link StructuredDocumentEntry#REQUIRED_FIELDS}).
     */
    public StructuredDocumentEntryDTO createStructuredEntry(Long fileId,
                                                            StructuredEntryRequest request,
                                                            Long createdBy) {
        UserFile file = userFileRepository.findById(fileId)
                .filter(UserFile::getIsActive)
                .orElseThrow(() -> new IllegalArgumentException("File not found: " + fileId));

        if (structuredEntryRepository.findFirstByUserFileIdAndIsActiveTrue(fileId).isPresent()) {
            throw new IllegalArgumentException(
                    "A structured entry already exists for this file; update it instead");
        }

        // Default the document type to the linked file's category when omitted.
        UserFile.FileCategory documentType = resolveDocumentType(request.getDocumentType(), file);
        // Default the patient context to the file's linked patient when omitted.
        Long patientId = request.getPatientId() != null ? request.getPatientId() : file.getPatientId();
        Long employeeUserId = request.getEmployeeUserId();

        validateStructuredEntry(documentType, patientId, employeeUserId, request.getFields());

        StructuredDocumentEntry entry = StructuredDocumentEntry.builder()
                .userFileId(fileId)
                .documentType(documentType)
                .patientId(patientId)
                .employeeUserId(employeeUserId)
                .fieldsJson(writeFieldsJson(request.getFields()))
                .createdBy(createdBy)
                .build();

        entry = structuredEntryRepository.save(entry);
        log.info("Structured entry created: ID={}, file={}, type={}, patient={}, employee={}",
                entry.getId(), fileId, documentType, patientId, employeeUserId);

        // Compliance tracking: a digitized structured record completes the
        // requirement on the subject's checklist (audited transition).
        documentComplianceService.recordStructuredEntrySaved(entry, file, createdBy);

        return mapEntryToDTO(entry, file);
    }

    /**
     * Update an existing structured form entry. The link to the original file is
     * immutable; document type, context and captured fields may change but are
     * re-validated against the same rules as creation.
     */
    public StructuredDocumentEntryDTO updateStructuredEntry(Long entryId, StructuredEntryRequest request) {
        StructuredDocumentEntry entry = structuredEntryRepository.findById(entryId)
                .filter(StructuredDocumentEntry::getIsActive)
                .orElseThrow(() -> new IllegalArgumentException("Structured entry not found: " + entryId));

        UserFile file = userFileRepository.findById(entry.getUserFileId())
                .orElseThrow(() -> new IllegalArgumentException(
                        "Linked file not found: " + entry.getUserFileId()));

        UserFile.FileCategory documentType = request.getDocumentType() != null
                ? resolveDocumentType(request.getDocumentType(), file)
                : entry.getDocumentType();
        Long patientId = request.getPatientId() != null ? request.getPatientId() : entry.getPatientId();
        Long employeeUserId = request.getEmployeeUserId() != null
                ? request.getEmployeeUserId()
                : entry.getEmployeeUserId();

        validateStructuredEntry(documentType, patientId, employeeUserId, request.getFields());

        entry.setDocumentType(documentType);
        entry.setPatientId(patientId);
        entry.setEmployeeUserId(employeeUserId);
        entry.setFieldsJson(writeFieldsJson(request.getFields()));

        StructuredDocumentEntry saved = structuredEntryRepository.save(entry);
        log.info("Structured entry updated: ID={}, file={}", entryId, saved.getUserFileId());
        return mapEntryToDTO(saved, file);
    }

    /** Get a structured entry by its ID. */
    public Optional<StructuredDocumentEntryDTO> getStructuredEntry(Long entryId) {
        return structuredEntryRepository.findById(entryId)
                .filter(StructuredDocumentEntry::getIsActive)
                .flatMap(entry -> userFileRepository.findById(entry.getUserFileId())
                        .map(file -> mapEntryToDTO(entry, file)));
    }

    /** Get the structured entry captured from a specific uploaded file, if any. */
    public Optional<StructuredDocumentEntryDTO> getStructuredEntryForFile(Long fileId) {
        return structuredEntryRepository.findFirstByUserFileIdAndIsActiveTrue(fileId)
                .flatMap(entry -> userFileRepository.findById(entry.getUserFileId())
                        .map(file -> mapEntryToDTO(entry, file)));
    }

    /** List structured entries linked to a patient (care-circle context). */
    public List<StructuredDocumentEntryDTO> listStructuredEntriesForPatient(Long patientId) {
        List<StructuredDocumentEntry> entries = structuredEntryRepository.findByPatientIdAndIsActiveTrue(patientId);
        Set<Long> fileIds = entries.stream()
                .map(StructuredDocumentEntry::getUserFileId)
                .collect(Collectors.toSet());
        Map<Long, UserFile> fileMap = userFileRepository.findAllById(fileIds)
                .stream()
                .collect(Collectors.toMap(UserFile::getId, f -> f));
        return entries.stream()
                .filter(entry -> fileMap.containsKey(entry.getUserFileId()))
                .map(entry -> mapEntryToDTO(entry, fileMap.get(entry.getUserFileId())))
                .collect(Collectors.toList());
    }

    private UserFile.FileCategory resolveDocumentType(String rawType, UserFile file) {
        UserFile.FileCategory documentType = (rawType != null && !rawType.isBlank())
                ? mapCategoryToEnum(rawType)
                : file.getFileCategory();
        if (!StructuredDocumentEntry.SUPPORTED_TYPES.contains(documentType)) {
            throw new IllegalArgumentException(
                    "'" + documentType + "' does not support structured entries. Supported types: "
                            + StructuredDocumentEntry.supportedTypeNames());
        }
        return documentType;
    }

    /**
     * Enforce the structured-entry invariants: patient or employee context must be
     * present, and every required field for the document type must be filled in.
     */
    private void validateStructuredEntry(UserFile.FileCategory documentType,
                                         Long patientId, Long employeeUserId,
                                         Map<String, String> fields) {
        if (patientId == null && employeeUserId == null) {
            throw new IllegalArgumentException(
                    "A patient or employee context is required before saving a structured entry");
        }

        Set<String> required = StructuredDocumentEntry.REQUIRED_FIELDS
                .getOrDefault(documentType, Set.of());
        List<String> missing = required.stream()
                .filter(key -> fields == null
                        || fields.get(key) == null
                        || fields.get(key).isBlank())
                .sorted()
                .collect(Collectors.toList());
        if (!missing.isEmpty()) {
            throw new IllegalArgumentException(
                    "Missing required fields for " + documentType + ": " + String.join(", ", missing));
        }
    }

    private String writeFieldsJson(Map<String, String> fields) {
        try {
            return OBJECT_MAPPER.writeValueAsString(fields != null ? fields : Map.of());
        } catch (IOException e) {
            throw new RuntimeException("Failed to serialize structured entry fields", e);
        }
    }

    private Map<String, String> readFieldsJson(String fieldsJson) {
        if (fieldsJson == null || fieldsJson.isBlank()) {
            return new LinkedHashMap<>();
        }
        try {
            return OBJECT_MAPPER.readValue(fieldsJson, new TypeReference<LinkedHashMap<String, String>>() {});
        } catch (IOException e) {
            log.error("Failed to parse structured entry fields JSON", e);
            return new LinkedHashMap<>();
        }
    }

    private StructuredDocumentEntryDTO mapEntryToDTO(StructuredDocumentEntry entry, UserFile file) {
        return StructuredDocumentEntryDTO.builder()
                .id(entry.getId())
                .fileId(entry.getUserFileId())
                .documentType(entry.getDocumentType().name())
                .patientId(entry.getPatientId())
                .employeeUserId(entry.getEmployeeUserId())
                .fields(readFieldsJson(entry.getFieldsJson()))
                .createdBy(entry.getCreatedBy())
                .createdAt(entry.getCreatedAt())
                .updatedAt(entry.getUpdatedAt())
                .originalFilename(file != null ? file.getOriginalFilename() : null)
                .fileUrl(file != null ? resolveFileUrl(file) : null)
                .build();
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
    
    /**
     * Map a client-supplied category string to the canonical {@link UserFile.FileCategory}.
     * Delegates to the single source of truth on the enum so the frontend and backend stay
     * aligned. Unknown values throw {@link IllegalArgumentException} (callers that take user
     * input should validate up-front so the message can be surfaced as a 400).
     */
    private UserFile.FileCategory mapCategoryToEnum(String category) {
        return UserFile.FileCategory.fromClientValue(category);
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
    
    private String resolveFileUrl(UserFile userFile) {
        if (userFile.getStorageType() == UserFile.StorageType.DATABASE) {
            return databaseStorageService.getFileUrl("db://files/" + userFile.getId());
        }
        if (s3StorageService == null) {
            return "unavailable://s3-service-not-configured";
        }
        return s3StorageService.getFileUrl(userFile.getS3Path());
    }

    private UserFileDTO mapToDTO(UserFile userFile) {
        String fileUrl = resolveFileUrl(userFile);

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
