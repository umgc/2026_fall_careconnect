package com.careconnect.dto;

import lombok.Data;

/**
 * Request DTO for STML-4 recall history search.
 */
@Data
public class StmlSearchRequest {
    private Long patientId;
    private String keyword;
    private String sender;
    private String fromDate;
    private String toDate;
}