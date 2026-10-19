package com.careconnect.dto;

public record FamilyMemberRegistration(
        String firstName,
        String lastName,
        String email,
        String phone,
        AddressDto address, // optional
        String relationship, // optional
        Long patientUserId
) {
}
