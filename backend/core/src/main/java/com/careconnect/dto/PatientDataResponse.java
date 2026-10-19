package com.careconnect.dto;

import java.util.List;

public record PatientDataResponse(
        Long patientId,
        String patientName,
        String email,
        String phone,
        String relationship,
        List<VitalSampleDTO> recentVitals,
        DashboardDTO dashboard,
        String accessLevel // "READ_ONLY" for family members
) {
}
