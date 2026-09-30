package com.careconnect.dto;

import lombok.Data;
import lombok.AllArgsConstructor;
import lombok.NoArgsConstructor;
import lombok.Builder;

import java.time.Instant;


@Data
@Builder
@AllArgsConstructor
@NoArgsConstructor
public class ExportLinkDTO {
    private String downloadUrl;
    private String fileName;
    private String fileType;
    private Long fileSizeBytes;
    private String expiresAt;
    private String status;
    private String url;
    private Instant instantExpiresAt;
}
