package com.careconnect.dto;

import java.util.List;

public record PatientWithLinkDto(
        PatientSummaryDTO patient,
        CaregiverPatientLinkResponse link,
        List<PatientRiskResponseDto> flaggedRisks
) {
}
