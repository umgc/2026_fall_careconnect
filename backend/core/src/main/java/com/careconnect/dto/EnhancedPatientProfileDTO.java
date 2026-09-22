package com.careconnect.dto;

import lombok.Builder;

import java.util.List;

/**
 * Enhanced patient profile DTO with comprehensive medical information
 * This extends the basic profile with medications, latest vitals, and mood/pain data
 * for caregivers and healthcare providers
 */
@Builder
public record EnhancedPatientProfileDTO(
        // Basic patient information (same as PatientProfileDTO)
        Long id,
        String firstName,
        String lastName,
        String email,
        String phone,
        String dob,
        com.careconnect.model.Gender gender,
        AddressDto address,
        String relationship,

        // Medical information
        List<AllergyDTO> allergies,
        List<MedicationDTO> activeMedications,
        LatestVitalsDTO latestVitals,
        LatestMoodPainDTO latestMoodPain,

        // Summary statistics for quick overview
        MedicalSummaryDTO medicalSummary,

        // Relationship information
        Long caregiverId,
        Long familyMemberId
) {
}
