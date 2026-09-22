package com.careconnect.service.invoice;


public interface S3StorageService {
    void upload(byte[] data, String key);

    void upload(byte[] data, String key, String contentType);
}
