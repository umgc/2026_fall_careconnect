package com.careconnect.dto;

import java.time.LocalDate;

public record FamilyMemberResponse(
        Long id,
        String firstName,
        String lastName,
        String email,
        String phone,
        String relationship,
        LocalDate linkedDate,
        String accessLevel
) {
    public static FamilyMemberResponse readOnly(Long id, String firstName, String lastName,
                                                String email, String phone, String relationship,
                                                LocalDate linkedDate) {
        return new FamilyMemberResponse(id, firstName, lastName, email, phone, relationship, linkedDate, "READ_ONLY");
    }
}
