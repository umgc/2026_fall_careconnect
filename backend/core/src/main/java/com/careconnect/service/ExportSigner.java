package com.careconnect.service;

import java.time.Instant;
import java.time.Duration;

import org.springframework.stereotype.Service;

import com.careconnect.dto.ExportLinkDTO;
import lombok.Builder;

@Builder
@Service
public class ExportSigner {
    private static final Duration TTL = Duration.ofHours(1);

    /**
     * Generates a signed URL for file exports
     *
     * @param fileName  the name of the file to export
     * @param patientId the patient ID
     * @return signed URL string
     */
    public String generateSignedUrl(String fileName, Long patientId) {
        // Simple implementation - in production, this would generate actual signed URLs
        String baseUrl = "https://api.careconnect.com/exports";
        long timestamp = System.currentTimeMillis();
        String signature = generateSignature(fileName, patientId, timestamp);

        return String.format("%s/%s?patientId=%d&timestamp=%d&signature=%s",
                baseUrl, fileName, patientId, timestamp, signature);
    }

    private String generateSignature(String fileName, Long patientId, long timestamp) {
        // Simple signature generation - in production, use proper cryptographic signing
        return Integer.toHexString((fileName + patientId + timestamp).hashCode());
    }

    public ExportLinkDTO sign(String relativePath) {
        String url = "https://files.careconnect.ai" + relativePath + "?sig=mock123"; // TODO real signer
        return ExportLinkDTO.builder()
                .url(url)
                .instantExpiresAt(Instant.now().plus(TTL))
                .build();
    }
}
