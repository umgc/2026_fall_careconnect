package com.careconnect.service;

import com.careconnect.dto.UserFileDTO;
import org.springframework.web.multipart.MultipartFile;

import java.util.List;

public interface StorageService {
    String upload(String path, byte[] content, String mimeType);

    String uploadFile(MultipartFile file, Long userId, String userType, String category);

    byte[] download(String path);

    String getFileUrl(String path);

    void deleteFile(String path);

    List<String> listUserFiles(Long userId, String userType);
}