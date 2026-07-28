package com.careconnect.dto;

import lombok.Data;

@Data
public class StmlRecallRequest {
    private Long patientId;
    private Long userId;
    private String question;
}
