package com.careconnect.service;

import java.util.Map;

import com.careconnect.model.Caregiver;
import com.careconnect.model.Patient;
import com.careconnect.model.User;
import com.careconnect.model.Address;
import com.careconnect.repository.CaregiverRepository;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.UserRepository;
import com.careconnect.exception.AppException;
import com.careconnect.dto.AllergyDTO;
import com.careconnect.dto.PatientProfileDTO;
import com.careconnect.dto.PatientProfileUpdateDTO;
import com.careconnect.dto.AddressDto;
import com.careconnect.dto.EnhancedPatientProfileDTO;
import com.careconnect.dto.MedicationDTO;
import com.careconnect.dto.LatestVitalsDTO;
import com.careconnect.dto.LatestMoodPainDTO;
import com.careconnect.dto.MedicalSummaryDTO;
import com.careconnect.dto.VitalSampleDTO;
import com.careconnect.dto.MoodPainLogResponse;
import com.careconnect.service.AllergyService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;

import java.util.HashMap;
import java.util.ArrayList;


import java.util.Collections;
import java.util.List;
import java.util.Optional;
import java.util.stream.Collectors;

import com.careconnect.dto.CaregiverPatientLinkResponse;

import com.careconnect.dto.FamilyMemberLinkResponse;

import com.careconnect.service.FamilyMemberService;

@Service
public class PatientService {

    @Autowired
    private PatientRepository patientRepository;

    @Autowired
    private CaregiverRepository caregiverRepository;

    @Autowired
    private UserRepository userRepository;

    @Autowired
    private CaregiverPatientLinkService caregiverPatientLinkService;

    @Autowired
    private AllergyService allergyService;

    @Autowired
    private MedicationService medicationService;

    @Autowired
    private VitalSampleService vitalSampleService;

    @Autowired
    private MoodPainLogService moodPainLogService;

    @Autowired
    private FamilyMemberService familyMemberService;

    // 1. List caregivers associated with a patient (ACTIVE links only)
    public List<Caregiver> getCaregiversByPatient(Long patientId) {
        Patient patient = patientRepository.findById(patientId)
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Patient not found"));

        // Get active caregiver links via CaregiverPatientLinkService
        List<CaregiverPatientLinkResponse> activeLinks = caregiverPatientLinkService.getCaregiversByPatient(patient.getUser().getId());

        // Extract caregiver user IDs from active links and get User objects
        List<Caregiver> caregivers = activeLinks.stream()
                .map(link -> userRepository.findById(link.caregiverUserId()))
                .filter(Optional::isPresent)
                .map(Optional::get)
                .map(user -> caregiverRepository.findByUser(user))
                .filter(Optional::isPresent)
                .map(Optional::get)
                .collect(Collectors.toList());

        return caregivers;
    }

    // 2. Get patient details
    public Patient getPatientById(Long patientId) {
        return patientRepository.findById(patientId)
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Patient not found"));
    }

    // 3. Get patient by user ID (for family member access)
    public Patient getPatientByUserId(Long userId) {
        User user = userRepository.findById(userId)
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "User not found"));
        return patientRepository.findByUser(user)
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Patient profile not found"));
    }

    // 4. Update patient information
    public Patient updatePatient(Long patientId, Patient updatedPatient) {
        Patient existing = patientRepository.findById(patientId)
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Patient not found"));
        existing.setFirstName(updatedPatient.getFirstName());
        existing.setLastName(updatedPatient.getLastName());
        existing.setDob(updatedPatient.getDob());
        existing.setEmail(updatedPatient.getEmail());
        existing.setPhone(updatedPatient.getPhone());
        existing.setAddress(updatedPatient.getAddress());
        existing.setRelationship(updatedPatient.getRelationship());
        existing.setLikes(updatedPatient.getLikes());
        existing.setDislikes(updatedPatient.getDislikes());
        existing.setHabits(updatedPatient.getHabits());
        existing.setPhobias(updatedPatient.getPhobias());
        existing.setPreferredCommunicationMethod(updatedPatient.getPreferredCommunicationMethod());
        return patientRepository.save(existing);
    }

    // 5. Check if a patient exists by user ID
    public boolean existsByUserId(Long userId) {
        User user = userRepository.findById(userId).orElse(null);
        return user != null && patientRepository.existsByUser(user);
    }


    // 6. Get primary care provider details for a patient
    public Map<String, Object> getPrimaryProvider(Long patientId) {
        Patient patient = patientRepository.findById(patientId)
                .orElseThrow(() -> new IllegalArgumentException("Patient not found"));
        Map<String, Object> provider = new HashMap<>();
        if (patient.getPrimaryCareProvider() != null) {
            provider.put("name", patient.getPrimaryCareProvider().getName());
            provider.put("specialty", patient.getPrimaryCareProvider().getSpecialty());
            provider.put("organization", patient.getPrimaryCareProvider().getOrganization());
            provider.put("phone", patient.getPrimaryCareProvider().getPhone());
            provider.put("email", patient.getPrimaryCareProvider().getEmail());
        }
        return provider;
    }


    /**
     * Get complete patient profile including allergies
     */
    public Optional<PatientProfileDTO> getPatientProfile(Long patientId) {
        Optional<Patient> patientOpt = patientRepository.findById(patientId);
        if (patientOpt.isEmpty()) {
            return Optional.empty();
        }

        Patient patient = patientOpt.get();
        List<AllergyDTO> allergies = allergyService.getAllergiesForPatient(patientId);

        return Optional.of(PatientProfileDTO.builder()
                .id(patient.getId())
                .firstName(patient.getFirstName())
                .lastName(patient.getLastName())
                .email(patient.getEmail())
                .phone(patient.getPhone())
                .dob(patient.getDob())
                .gender(patient.getGender())
                .address(mapAddressToDto(patient.getAddress()))
                .relationship(patient.getRelationship())
                .allergies(allergies)
                .build());
    }

    /**
     * Update patient profile information
     */
    @org.springframework.transaction.annotation.Transactional
    public PatientProfileDTO updatePatientProfile(Long patientId, PatientProfileUpdateDTO updateDTO) {
        Patient patient = patientRepository.findById(patientId)
                .orElseThrow(() -> new IllegalArgumentException("Patient not found with id: " + patientId));

        // Update only non-null fields
        if (updateDTO.getFirstName() != null) {
            patient.setFirstName(updateDTO.getFirstName());
        }
        if (updateDTO.getLastName() != null) {
            patient.setLastName(updateDTO.getLastName());
        }
        if (updateDTO.getPhone() != null) {
            patient.setPhone(updateDTO.getPhone());
        }
        if (updateDTO.getDob() != null) {
            patient.setDob(updateDTO.getDob());
        }
        if (updateDTO.getGender() != null) {
            patient.setGender(updateDTO.getGender());
        }
        if (updateDTO.getAddress() != null) {
            patient.setAddress(mapDtoToAddress(updateDTO.getAddress()));
        }
        if (updateDTO.getRelationship() != null) {
            patient.setRelationship(updateDTO.getRelationship());
        }
        if (updateDTO.getLikes() != null) {
            patient.setLikes(updateDTO.getLikes());
        }
        if (updateDTO.getDislikes() != null) {
            patient.setDislikes(updateDTO.getDislikes());
        }
        if (updateDTO.getHabits() != null) {
            patient.setHabits(updateDTO.getHabits());
        }
        if (updateDTO.getPhobias() != null) {
            patient.setPhobias(updateDTO.getPhobias());
        }
        if (updateDTO.getPreferredCommunicationMethod() != null) {
            patient.setPreferredCommunicationMethod(updateDTO.getPreferredCommunicationMethod());
        }

        // Save updated patient
        Patient savedPatient = patientRepository.save(patient);

        // Get current allergies (allergies are managed separately via allergy endpoints)
        List<AllergyDTO> allergies = allergyService.getAllergiesForPatient(patientId);

        return PatientProfileDTO.builder()
                .id(savedPatient.getId())
                .firstName(savedPatient.getFirstName())
                .lastName(savedPatient.getLastName())
                .email(savedPatient.getEmail())
                .phone(savedPatient.getPhone())
                .dob(savedPatient.getDob())
                .gender(savedPatient.getGender())
                .address(mapAddressToDto(savedPatient.getAddress()))
                .relationship(savedPatient.getRelationship())
                .allergies(allergies)
                .likes(savedPatient.getLikes())
                .dislikes(savedPatient.getDislikes())
                .habits(savedPatient.getHabits())
                .phobias(savedPatient.getPhobias())
                .preferredCommunicationMethod(savedPatient.getPreferredCommunicationMethod())
                .build();
    }

    /**
     * Get enhanced patient profile with comprehensive medical information
     * This includes medications, latest vitals, mood/pain data, and medical summary
     */
    public Optional<EnhancedPatientProfileDTO> getEnhancedPatientProfile(Long patientId) {
        Optional<Patient> patientOpt = patientRepository.findById(patientId);
        if (patientOpt.isEmpty()) {
            return Optional.empty();
        }

        Patient patient = patientOpt.get();

        // Get all medical information
        List<AllergyDTO> allergies = allergyService.getAllergiesForPatient(patientId);
        List<MedicationDTO> activeMedications = medicationService.getAllMedicationsForPatient(patientId);
        LatestVitalsDTO latestVitals = getLatestVitals(patientId);
        LatestMoodPainDTO latestMoodPain = getLatestMoodPain(patientId);
        MedicalSummaryDTO medicalSummary = buildMedicalSummary(patientId, allergies, activeMedications, latestVitals, latestMoodPain);

        // Get caregiver and family member link IDs (not user IDs)
        List<CaregiverPatientLinkResponse> caregiverLinks = caregiverPatientLinkService.getCaregiversByPatient(patient.getUser().getId());
        Long caregiverId = caregiverLinks.isEmpty() ? null : caregiverLinks.get(0).id();

        List<FamilyMemberLinkResponse> familyLinks = familyMemberService.getFamilyMembersByPatientId(patient.getId());
        Long familyMemberId = familyLinks.isEmpty() ? null : familyLinks.get(0).id();

        return Optional.of(EnhancedPatientProfileDTO.builder()
                .id(patient.getId())
                .firstName(patient.getFirstName())
                .lastName(patient.getLastName())
                .email(patient.getEmail())
                .phone(patient.getPhone())
                .dob(patient.getDob())
                .gender(patient.getGender())
                .address(mapAddressToDto(patient.getAddress()))
                .relationship(patient.getRelationship())
                .allergies(allergies)
                .activeMedications(activeMedications)
                .latestVitals(latestVitals)
                .latestMoodPain(latestMoodPain)
                .medicalSummary(medicalSummary)
                .caregiverId(caregiverId)
                .familyMemberId(familyMemberId)
                .build());
    }

    /**
     * Get latest vital signs for a patient
     */
    private LatestVitalsDTO getLatestVitals(Long patientId) {
        try {
            // Get the most recent vital sample
            // Assuming VitalSampleService has a method to get latest vitals
            Optional<VitalSampleDTO> latestVitalOpt = vitalSampleService.getLatestVitalSample(patientId);
            if (latestVitalOpt.isPresent()) {
                VitalSampleDTO vital = latestVitalOpt.get();
                return LatestVitalsDTO.builder()
                        .id(null) // VitalSampleDTO doesn't have ID exposed
                        .timestamp(vital.timestamp())
                        .heartRate(vital.heartRate())
                        .spo2(vital.spo2())
                        .systolic(vital.systolic())
                        .diastolic(vital.diastolic())
                        .weight(vital.weight())
                        .moodValue(vital.moodValue())
                        .painValue(vital.painValue())
                        .createdAt(vital.timestamp()) // Using timestamp as created time
                        .build();
            }
        } catch (Exception e) {
            // Log error but don't fail the entire request
            // log.warn("Error fetching latest vitals for patient {}: {}", patientId, e.getMessage());
        }
        return null;
    }

    /**
     * Get latest mood and pain log for a patient
     */
    private LatestMoodPainDTO getLatestMoodPain(Long patientId) {
        try {
            Patient patient = patientRepository.findById(patientId).orElse(null);
            if (patient != null) {
                // Get the most recent mood/pain log
                MoodPainLogResponse recent = moodPainLogService.getLatestMoodPainLog(patient.getUser());
                if (recent != null) {
                    return LatestMoodPainDTO.builder()
                            .id(recent.getId())
                            .moodValue(recent.getMoodValue())
                            .painValue(recent.getPainValue())
                            .note(recent.getNote())
                            .timestamp(recent.getTimestamp())
                            .createdAt(recent.getCreatedAt())
                            .build();
                }
            }
        } catch (Exception e) {
            // Log error but don't fail the entire request
            // log.warn("Error fetching latest mood/pain for patient {}: {}", patientId, e.getMessage());
        }
        return null;
    }

    /**
     * Build medical summary with key statistics and health indicators
     */
    private MedicalSummaryDTO buildMedicalSummary(Long patientId, List<AllergyDTO> allergies,
                                                  List<MedicationDTO> medications,
                                                  LatestVitalsDTO latestVitals,
                                                  LatestMoodPainDTO latestMoodPain) {

        // Calculate basic counts
        int totalAllergies = allergies != null ? allergies.size() : 0;
        int activeMedications = medications != null ? medications.size() : 0;

        // Determine if there's recent activity (within last 7 days)
        java.time.Instant sevenDaysAgo = java.time.Instant.now().minus(java.time.Duration.ofDays(7));
        java.time.LocalDateTime sevenDaysAgoLocal = java.time.LocalDateTime.now().minus(java.time.Duration.ofDays(7));

        boolean hasRecentVitals = latestVitals != null &&
                latestVitals.timestamp() != null &&
                latestVitals.timestamp().isAfter(sevenDaysAgo);

        boolean hasRecentMoodPain = latestMoodPain != null &&
                latestMoodPain.timestamp() != null &&
                latestMoodPain.timestamp().isAfter(sevenDaysAgoLocal);

        // Determine overall health status based on available data
        String healthStatus = determineHealthStatus(latestVitals, latestMoodPain, totalAllergies);

        // Find the most recent activity date
        String lastActivityDate = findLastActivityDate(latestVitals, latestMoodPain);

        return MedicalSummaryDTO.builder()
                .totalAllergies(totalAllergies)
                .activeMedications(activeMedications)
                .totalVitalReadings(0) // Would need additional query to count all vitals
                .totalMoodPainEntries(0) // Would need additional query to count all entries
                .hasRecentVitals(hasRecentVitals)
                .hasRecentMoodPain(hasRecentMoodPain)
                .overallHealthStatus(healthStatus)
                .lastActivityDate(lastActivityDate)
                .build();
    }

    /**
     * Determine overall health status based on available data
     */
    private String determineHealthStatus(LatestVitalsDTO vitals, LatestMoodPainDTO moodPain, int allergyCount) {
        // Simple health status logic - can be made more sophisticated
        if (vitals == null && moodPain == null) {
            return "No Recent Data";
        }

        boolean hasWarningVitals = false;
        if (vitals != null) {
            // Check for concerning vital signs
            if ((vitals.heartRate() != null && (vitals.heartRate() < 60 || vitals.heartRate() > 100)) ||
                    (vitals.systolic() != null && (vitals.systolic() < 90 || vitals.systolic() > 140)) ||
                    (vitals.spo2() != null && vitals.spo2() < 95)) {
                hasWarningVitals = true;
            }
        }

        boolean hasHighPain = moodPain != null && moodPain.painValue() != null && moodPain.painValue() >= 7;
        boolean hasLowMood = moodPain != null && moodPain.moodValue() != null && moodPain.moodValue() <= 3;

        if (hasWarningVitals || hasHighPain) {
            return "Needs Attention";
        } else if (hasLowMood) {
            return "Monitor Mood";
        } else {
            return "Stable";
        }
    }

    /**
     * Find the most recent activity date across all health data
     */
    private String findLastActivityDate(LatestVitalsDTO vitals, LatestMoodPainDTO moodPain) {
        java.time.Instant latestVitalTime = vitals != null ? vitals.timestamp() : null;
        java.time.LocalDateTime latestMoodTime = moodPain != null ? moodPain.timestamp() : null;

        if (latestVitalTime == null && latestMoodTime == null) {
            return "No recent activity";
        }

        // Convert to comparable format and find the latest
        java.time.LocalDateTime vitalsAsLocal = latestVitalTime != null ?
                java.time.LocalDateTime.ofInstant(latestVitalTime, java.time.ZoneOffset.UTC) : null;

        java.time.LocalDateTime latest = null;
        if (vitalsAsLocal != null && latestMoodTime != null) {
            latest = vitalsAsLocal.isAfter(latestMoodTime) ? vitalsAsLocal : latestMoodTime;
        } else if (vitalsAsLocal != null) {
            latest = vitalsAsLocal;
        } else if (latestMoodTime != null) {
            latest = latestMoodTime;
        }

        if (latest != null) {
            return latest.toLocalDate().toString();
        }

        return "No recent activity";
    }

    /**
     * Map Address entity to AddressDto
     */
    private AddressDto mapAddressToDto(Address address) {
        if (address == null) {
            return null;
        }

        return new AddressDto(
                address.getLine1(),
                address.getLine2(),
                address.getCity(),
                address.getState(),
                address.getZip(),
                null // phone is not part of Address entity
        );
    }

    /**
     * Map AddressDto to Address entity
     */
    private Address mapDtoToAddress(AddressDto dto) {
        if (dto == null) {
            return null;
        }

        return Address.builder()
                .line1(dto.line1())
                .line2(dto.line2())
                .city(dto.city())
                .state(dto.state())
                .zip(dto.zip())
                .build();
    }

}