package com.careconnect.service;

import com.careconnect.dto.S3Props;
import com.careconnect.dto.UserFileDTO;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;
import software.amazon.awssdk.core.ResponseBytes;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.core.sync.ResponseTransformer;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.*;

import java.io.IOException;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.util.List;
import java.util.UUID;

@Service
@RequiredArgsConstructor
@Slf4j
@ConditionalOnProperty(name = "careconnect.aws.enabled", havingValue = "true", matchIfMissing = true)
public class S3StorageService implements StorageService {

    private final S3Client s3;
    private final S3Props props;

    @Override
    public String upload(String path, byte[] content, String mimeType) {
        try {
            log.info("DEBUG: Uploading to S3 - Bucket: {}, Key: {}, ContentType: {}",
                    props.getBucket(), path, mimeType);

            PutObjectResponse resp = s3.putObject(
                    PutObjectRequest.builder()
                            .bucket(props.getBucket())
                            .key(path)
                            .serverSideEncryption(ServerSideEncryption.AWS_KMS)
                            .contentType(mimeType)
                            .build(),
                    RequestBody.fromBytes(content)
            );

            log.info("File uploaded successfully to S3: {}", path);
            return props.getBaseUrl() + "/" + path;
        } catch (Exception e) {
            log.error("Failed to upload file to S3: {}", path, e);
            throw new RuntimeException("Failed to upload file to S3", e);
        }
    }

    @Override
    public String uploadFile(MultipartFile file, Long userId, String userType, String category) {
        try {
            log.info("DEBUG: Starting file upload for user: {}, type: {}, category: {}",
                    userId, userType, category);
            log.info("DEBUG: Original filename: {}, size: {} bytes, content-type: {}",
                    file.getOriginalFilename(), file.getSize(), file.getContentType());
            log.info("DEBUG: S3 Config - Bucket: {}, Region: {}, BaseURL: {}",
                    props.getBucket(), props.getRegion(), props.getBaseUrl());
            log.info("DEBUG: Access Key starts with: {}...",
                    props.getAccessKey() != null ? props.getAccessKey().substring(0, 8) : "NULL");

//            String fileName = generateFileName(file.getOriginalFilename(), userId, userType, category);
            String fullPath = buildFilePath(userId, userType, category, file.getOriginalFilename());

            log.info("DEBUG: Generated filename: {}", file.getOriginalFilename());
            log.info("DEBUG: Full S3 path: {}", fullPath);

            PutObjectResponse resp = s3.putObject(
                    PutObjectRequest.builder()
                            .bucket(props.getBucket())
                            .key(fullPath)
                            .serverSideEncryption(ServerSideEncryption.AWS_KMS)
                            .contentType(file.getContentType())
                            .contentLength(file.getSize())
                            .build(),
                    RequestBody.fromInputStream(file.getInputStream(), file.getSize())
            );

            log.info("DEBUG: S3 Response - ETag: {}, VersionId: {}",
                    resp.eTag(), resp.versionId());
            log.info("File uploaded successfully: {} for user: {}", fullPath, userId);

            String fileUrl = getFileUrl(fullPath);
            log.info("DEBUG: Generated file URL: {}", fileUrl);

            return fullPath;
        } catch (IOException e) {
            log.error("IOException during file upload for user: {}", userId, e);
            throw new RuntimeException("Failed to upload file - IO Error", e);
        } catch (Exception e) {
            log.error("Failed to upload file for user: {} - Error: {}", userId, e.getMessage(), e);
            throw new RuntimeException("Failed to upload file: " + e.getMessage(), e);
        }
    }

    @Override
    public byte[] download(String path) {
        try {
            log.info("DEBUG: Downloading from S3 - Bucket: {}, Key: {}", props.getBucket(), path);

            ResponseBytes<GetObjectResponse> respBytes = s3.getObject(
                    GetObjectRequest.builder()
                            .bucket(props.getBucket())
                            .key(path)
                            .build(),
                    ResponseTransformer.toBytes()
            );

            log.info("File downloaded successfully: {}, size: {} bytes", path, respBytes.asByteArray().length);
            return respBytes.asByteArray();
        } catch (NoSuchKeyException e) {
            log.error("File not found in S3: {}", path);
            throw new RuntimeException("File not found: " + path, e);
        } catch (Exception e) {
            log.error("Failed to download file from S3: {}", path, e);
            throw new RuntimeException("Failed to download file", e);
        }
    }

    @Override
    public String getFileUrl(String path) {
        String url = props.getBaseUrl() + "/" + path;
        log.debug("DEBUG: Generated file URL: {} for path: {}", url, path);
        return url;
    }

    @Override
    public void deleteFile(String path) {
        try {
            log.info("DEBUG: Deleting from S3 - Bucket: {}, Key: {}", props.getBucket(), path);

            s3.deleteObject(DeleteObjectRequest.builder()
                    .bucket(props.getBucket())
                    .key(path)
                    .build());

            log.info("File deleted successfully: {}", path);
        } catch (Exception e) {
            log.error("Failed to delete file from S3: {}", path, e);
            throw new RuntimeException("Failed to delete file", e);
        }
    }

    @Override
    public List<String> listUserFiles(Long userId, String userType) {
        try {
            String prefix = userType.toLowerCase() + "_" + userId + "/";
            log.info("DEBUG: Listing files for user - Bucket: {}, Prefix: {}", props.getBucket(), prefix);

            ListObjectsV2Response response = s3.listObjectsV2(
                    ListObjectsV2Request.builder()
                            .bucket(props.getBucket())
                            .prefix(prefix)
                            .build()
            );

            List<String> files = response.contents().stream()
                    .map(S3Object::key)
                    .toList();

            log.info("DEBUG: Found {} files for user {}", files.size(), userId);
            return files;
        } catch (Exception e) {
            log.error("Failed to list files for user: {}", userId, e);
            throw new RuntimeException("Failed to list user files", e);
        }
    }

    public List<UserFileDTO> listUserFilesDto(Long userId, String userType) {
        try {
            String prefix = userType.toLowerCase() + "_" + userId + "/";
            log.info("DEBUG: Listing files for user DTO - Bucket: {}, Prefix: {}", props.getBucket(), prefix);

            ListObjectsV2Response response = s3.listObjectsV2(
                    ListObjectsV2Request.builder()
                            .bucket(props.getBucket())
                            .prefix(prefix)
                            .build()
            );

            List<UserFileDTO> files = response.contents().stream()
                    .map(
                            object -> UserFileDTO.builder()
                                    .s3FullKey(object.key())
                                    .filename(object.key().substring(object.key().lastIndexOf("/") + 1))
                                    .fileCategory(object.key().split("/")[1])
                                    .fileUrl(getFileUrl(object.key()))
                                    .fileSize(object.size())
                                    .updatedAt(LocalDateTime.ofInstant(object.lastModified(), ZoneId.systemDefault()))
                                    .build()
                    )
                    .toList();

            log.info("DEBUG: Found {} files for user {}", files.size(), userId);
            return files;
        } catch (Exception e) {
            log.error("Failed to list files for user: {}", userId, e);
            throw new RuntimeException("Failed to list user files", e);
        }
    }

    private String generateFileName(String originalFileName, Long userId, String userType, String category) {
        String timestamp = LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyyMMdd_HHmmss"));
        String uuid = UUID.randomUUID().toString().substring(0, 8);
        String extension = getFileExtension(originalFileName);

        String fileName = String.format("%s_%s_%s_%s%s",
                userType.toLowerCase(), userId, timestamp, uuid, extension);

        log.debug("DEBUG: Generated filename: {} from original: {}", fileName, originalFileName);
        return fileName;
    }

    private String buildFilePath(Long userId, String userType, String category, String fileName) {
        String path = String.format("%s_%s/%s/%s",
                userType.toLowerCase(), userId, category.toLowerCase(), fileName);
        log.debug("DEBUG: Built file path: {}", path);
        return path;
    }

    private String getFileExtension(String filename) {
        if (filename == null || !filename.contains(".")) {
            return "";
        }
        return filename.substring(filename.lastIndexOf("."));
    }
}