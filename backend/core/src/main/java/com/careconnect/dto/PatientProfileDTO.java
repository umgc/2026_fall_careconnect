package com.careconnect.dto;

import com.careconnect.model.Gender;
import lombok.Builder;

import java.util.List;

/**
 * DTO for returning complete patient profile information
 * This includes all patient data including allergies
 */
@Builder
public record PatientProfileDTO(
        Long id,
        String firstName,
        String lastName,
        String email,
        String phone,
        String dob,
        Gender gender,
        AddressDto address,
        String relationship,
        List<AllergyDTO> allergies,
        Long caregiverId,
        Long familyMemberId,
        // In-Home personalization fields
        String likes,
        String dislikes,
        String habits,
        String phobias,
        String preferredCommunicationMethod
) {
}
