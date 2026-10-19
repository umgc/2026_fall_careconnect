package com.careconnect.dto;

import java.time.LocalDateTime;

public record FamilyMemberLinkResponse(
        Long id,
        Long familyUserId,
        String familyMemberName,
        String familyMemberEmail,
        Long patientUserId,
        String patientName,
        String relationship,
        String status,
        LocalDateTime createdAt,
        String grantedBy
) {
}
