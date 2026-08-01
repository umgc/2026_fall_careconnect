package com.careconnect.service;

import com.careconnect.model.Caregiver;
import com.careconnect.model.Patient;
import com.careconnect.model.Address;
import com.careconnect.repository.CaregiverRepository;
import com.careconnect.repository.PatientRepository;
import com.careconnect.dto.CaregiverRegistration;
import com.careconnect.dto.PatientRegistration;
import com.careconnect.dto.CaregiverPatientLinkResponse;
import com.careconnect.exception.RegistrationException;
import com.careconnect.exception.AppException;
import org.springframework.transaction.annotation.Transactional;
import java.util.List;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import com.careconnect.model.User;
import com.careconnect.repository.PatientRepository;
import com.careconnect.model.ProfessionalInfo;
import com.careconnect.repository.UserRepository;
import com.careconnect.security.JwtTokenProvider;
import com.careconnect.security.Role;
import com.careconnect.dto.ProfessionalInfoDto;
import com.careconnect.dto.AddressDto;
import com.careconnect.dto.PatientWithLinkDto;
import com.careconnect.dto.PatientSummaryDTO;
import com.careconnect.dto.PatientRiskResponseDto;
import com.careconnect.model.Plan;
import com.careconnect.model.Subscription;
import com.careconnect.repository.FamilyMemberLinkRepository;
import com.careconnect.repository.PlanRepository;
import com.careconnect.repository.SubscriptionRepository;
import java.util.Map;
import java.util.Objects;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.http.HttpStatus;

import java.util.List;
import java.util.Optional;
import java.util.stream.Collectors;
import java.util.Map;
import java.time.Instant;
import java.time.LocalDateTime;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

@Service
public class CaregiverService {
    
    private static final Logger LOG = LoggerFactory.getLogger(CaregiverService.class);

    @Autowired
    private CaregiverRepository caregiverRepository;

    @Autowired
    private PatientRepository patientRepository;

    @Autowired
    private UserRepository users;

    @Autowired
    private PasswordEncoder encoder;

    @Autowired
    private JwtTokenProvider jwt;

    @Autowired
    private EmailService emailService;

    @Autowired
    private CaregiverPatientLinkService caregiverPatientLinkService;

    @Autowired 
    private  FamilyMemberLinkRepository familyMemberLinkRepository;
    
    @Autowired(required = false)
    private StripeService stripeService;
    
    @Autowired
    private PlanRepository planRepository;
    
    @Autowired
    private SubscriptionRepository subscriptionRepository;

    @Autowired
    private PatientRiskService patientRiskService;
    
    // public List<Patient> getPatientsByCaregiver(Long caregiverId, String email, String name) {
    //     // Get caregiver user
    //     Caregiver caregiver = getCaregiverById(caregiverId);
    //     User caregiverUser = caregiver.getUser();
        
    //     // Get active patient links via CaregiverPatientLinkService
    //     List<CaregiverPatientLinkResponse> activeLinks = caregiverPatientLinkService.getPatientsByCaregiver(caregiverUser.getId());
        
    //     // Extract patient user IDs from active links and get Patient objects
    //     List<Patient> patients = activeLinks.stream()
    //             .map(link -> users.findById(link.patientUserId()))
    //             .filter(Optional::isPresent)
    //             .map(Optional::get)
    //             .map(user -> patientRepository.findByUser(user))
    //             .filter(Optional::isPresent)
    //             .map(Optional::get)
    //             .collect(Collectors.toList());

    //     // Apply filters
    //     if (email != null && !email.isEmpty()) {
    //         patients = patients.stream()
    //                 .filter(p -> p.getEmail() != null && p.getEmail().equalsIgnoreCase(email))
    //                 .collect(Collectors.toList());
    //     }
    //     if (name != null && !name.isEmpty()) {
    //         patients = patients.stream()
    //                 .filter(p -> (p.getFirstName() + " " + p.getLastName()).toLowerCase().contains(name.toLowerCase()))
    //                 .collect(Collectors.toList());
    //     }
    //     return patients;
    // }

    // 1. List patients under a caregiver, with optional filtering (ACTIVE links only)
public List<PatientWithLinkDto> getPatientsByCaregiver(Long caregiverId, String email, String name) {
    // Get caregiver user
    Caregiver caregiver = getCaregiverById(caregiverId);
    User caregiverUser = caregiver.getUser();
    
    // Get active patient links via CaregiverPatientLinkService
    List<CaregiverPatientLinkResponse> activeLinks = caregiverPatientLinkService.getPatientsByCaregiver(caregiverUser.getId());
    
    // Get patient objects and combine with link data
    return activeLinks.stream()
            .map(link -> {
                Optional<User> userOpt = users.findById(link.patientUserId());
                if (userOpt.isPresent()) {
                    Optional<Patient> patientOpt = patientRepository.findByUser(userOpt.get());
                    if (patientOpt.isPresent()) {
                        Patient patient = patientOpt.get();
                        if (email != null && !email.isEmpty() && 
                           (patient.getEmail() == null || !patient.getEmail().equalsIgnoreCase(email))) {
                            return null;
                        }
                        if (name != null && !name.isEmpty() && 
                           !(patient.getFirstName() + " " + patient.getLastName())
                           .toLowerCase().contains(name.toLowerCase())) {
                            return null;
                        }
                        PatientSummaryDTO summary = PatientSummaryDTO.builder()
                            .id(patient.getId())
                            .firstName(patient.getFirstName())
                            .lastName(patient.getLastName())
                            .email(patient.getEmail())
                            .phone(patient.getPhone())
                            .dob(patient.getDob())
                            .gender(patient.getGender())
                            .address(patient.getAddress())
                            .relationship(patient.getRelationship())
                            .build();
                        return new PatientWithLinkDto(summary, link, List.of());
                    }
                }
                return null;
            })
            .filter(Objects::nonNull)
            .collect(Collectors.toList());
}

    // 2. Get caregiver details
    public Caregiver getCaregiverById(Long caregiverId) {
        return caregiverRepository.findById(caregiverId)
                .orElseThrow(() -> new RuntimeException("Caregiver not found"));
    }

public Caregiver updateCaregiver(Long caregiverId, Caregiver updatedCaregiver) {
    Caregiver existing = caregiverRepository.findById(caregiverId)
        .orElseThrow(() -> new RuntimeException("Caregiver not found"));
    existing.setFirstName(updatedCaregiver.getFirstName());
    existing.setLastName(updatedCaregiver.getLastName());
    existing.setDob(updatedCaregiver.getDob());
    existing.setEmail(updatedCaregiver.getEmail());
    existing.setPhone(updatedCaregiver.getPhone());
    existing.setAddress(updatedCaregiver.getAddress());
    existing.setProfessional(updatedCaregiver.getProfessional());
    existing.setCaregiverType(updatedCaregiver.getCaregiverType()); 
    return caregiverRepository.save(existing);
}

@Transactional 
public Patient registerPatient(PatientRegistration reg) {
    if (users.existsByEmail(reg.getEmail()))
        throw new RegistrationException("Email already registered");

    // Generate a temporary token for password setup
    String passwordSetupToken = java.util.UUID.randomUUID().toString();

    // Always generate a random password for patient registration
    String password = generateRandomPassword(12);
    String encodedPassword = encoder.encode(password);

    // Create and save the user first to ensure we have an ID
    User user = new User();
    user.setEmail(reg.getEmail());
    user.setPassword(encodedPassword);
    user.setPasswordHash(encodedPassword);
    user.setIsVerified(false);
    user.setRole(Role.PATIENT);
    user.setVerificationToken(passwordSetupToken);
    user.setCreatedAt(new java.sql.Timestamp(System.currentTimeMillis()));
    
    User savedUser = users.save(user); // Save user first to get ID

    Address addr = reg.getAddress() != null ? toAddress(reg.getAddress()) : null;

    // Build the patient object
    Patient patient = Patient.builder()
            .firstName(reg.getFirstName())
            .lastName(reg.getLastName())
            .dob(reg.getDob())
            .email(reg.getEmail())
            .phone(reg.getPhone())
            .address(addr)
            .user(savedUser) // Use the saved user with ID
            .relationship(reg.getRelationship())
            .gender(reg.getGender())
            .build();

    try {
        Patient savedPatient = patientRepository.save(patient);
        
        // Create caregiver-patient link if caregiver is specified
        if (reg.getCaregiverId() != null) {
            Caregiver caregiver = caregiverRepository.findById(reg.getCaregiverId())
                    .orElseThrow(() -> new RegistrationException("Caregiver not found"));
            
            try {
                // Create the permanent link between caregiver and patient
                caregiverPatientLinkService.createPermanentLink(
                    caregiver.getUser().getId(), 
                    savedUser.getId(), 
                    "Patient registered by caregiver"
                );
            } catch (Exception e) {
                throw new AppException(HttpStatus.INTERNAL_SERVER_ERROR,
                    "Failed to establish caregiver-patient relationship");
            }
        }
        
        emailService.sendPasswordSetupEmailWithCredentials(
            reg.getEmail(),
            passwordSetupToken,
            reg.getFirstName(),
            reg.getEmail(),
            password
        );
        
        // Firebase notification logic removed
        
        return savedPatient;
    } catch (Exception e) {
        throw new AppException(HttpStatus.INTERNAL_SERVER_ERROR,
                "Exception occurred while saving patient to the database");
    }
}
      /**
     * Generate a secure random password of the given length
     */
    private String generateRandomPassword(int length) {
        String chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@#$%^&*()_+-=";
        java.security.SecureRandom random = new java.security.SecureRandom();
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < length; i++) {
            sb.append(chars.charAt(random.nextInt(chars.length())));
        }
        return sb.toString();
    }

    @Transactional
    public Caregiver registerCaregiver(CaregiverRegistration reg) {
        if (users.existsByEmail(reg.getCredentials().getEmail()))
            throw new RegistrationException("Email already registered");
            
        // Create Stripe customer first
        String fullName = reg.getFirstName() + " " + reg.getLastName();
        Map<String, Object> customerResult;
        
        try {
            if (stripeService != null) {
                customerResult = stripeService.createCustomer(fullName, reg.getCredentials().getEmail());
            } else {
                // Mock customer result for development mode
                customerResult = Map.of(
                    "id", "cus_mock_" + System.currentTimeMillis(),
                    "success", true
                );
                LOG.info("Development mode: Using mock Stripe customer creation");
            }
        } catch (Exception e) {
            throw new AppException(HttpStatus.INTERNAL_SERVER_ERROR,
                "Failed to create Stripe customer: " + e.getMessage());
        }
        
        // Extract customer ID
        String paymentCustomerId = (String) customerResult.get("id");
        if (paymentCustomerId == null) {
            throw new AppException(HttpStatus.INTERNAL_SERVER_ERROR,
                "Invalid response from Stripe customer creation");
        }

        User user = new User();
        user.setEmail(reg.getCredentials().getEmail());
        String encodedPassword = encoder.encode(reg.getCredentials().getPassword());
        user.setPassword(encodedPassword);
        user.setPasswordHash(encodedPassword);
        user.setRole(Role.CAREGIVER);
        user.setPaymentCustomerId(paymentCustomerId);

        Address addr = toAddress(reg.getAddress());

        ProfessionalInfoDto profDto = reg.getProfessional();
        ProfessionalInfo prof = new ProfessionalInfo();
        if (profDto != null) {
            prof.setLicenseNumber(profDto.getLicenseNumber());
            prof.setIssuingState(profDto.getIssuingState());
            prof.setYearsExperience(profDto.getYearsExperience());
        }

        String caregiverType = reg.getCaregiverType();
        if (caregiverType == null || caregiverType.isBlank()) {
            caregiverType = "PROFESSIONAL";
        }
        
        Caregiver cg = Caregiver.builder()
                .firstName(reg.getFirstName())
                .lastName(reg.getLastName())
                .dob(reg.getDob())
                .email(reg.getCredentials().getEmail())
                .phone(reg.getPhone())
                .professional(prof)
                .address(addr)
                .user(user)
                .caregiverType(caregiverType)
                .gender(reg.getGender())
                .build();

        try {
            Caregiver savedCaregiver = caregiverRepository.save(cg);
            
            // If plan ID is provided, create subscription
            if (reg.getPlanId() != null) {
                // Get the plan from database - convert String to Long
                Plan plan = planRepository.findById(Long.parseLong(reg.getPlanId()))
                    .orElseThrow(() -> new AppException(HttpStatus.BAD_REQUEST, "Invalid plan selected"));
                
                // Create subscription
                try {
                    Map<String, Object> subscriptionResult;
                    if (stripeService != null) {
                        subscriptionResult = stripeService.createSubscription(
                            paymentCustomerId, plan.getCode() // using plan.code as the Stripe price ID
                        );
                    } else {
                        // Mock subscription result for development mode
                        subscriptionResult = Map.of(
                            "id", "sub_mock_" + System.currentTimeMillis(),
                            "success", true
                        );
                        LOG.info("Development mode: Using mock Stripe subscription creation");
                    }
                    
                    // Save subscription information to database
                    if (subscriptionResult != null && subscriptionResult.get("id") != null) {
                        Subscription subscription = new Subscription();
                        subscription.setPaymentSubscriptionId((String) subscriptionResult.get("id"));
                        subscription.setPaymentCustomerId(paymentCustomerId);
                        subscription.setUser(user);
                        subscription.setPlan(plan);
                        subscription.setStatus("active");
                        subscription.setStartedAt(java.time.Instant.now());
                        subscription.setCurrentPeriodEnd(java.time.Instant.now().plusSeconds(2592000)); // 30 days
                        // Add additional fields as needed
                        subscriptionRepository.save(subscription);
                    }
                } catch (Exception e) {
                    // Log the error but continue with registration
                    System.err.println("Failed to create subscription: " + e.getMessage());
                    // You could rollback the customer creation in Stripe here if needed
                }
            }
            
            return savedCaregiver;
        } catch (Exception e) {
            throw new AppException(HttpStatus.INTERNAL_SERVER_ERROR,
                    "Exception occurred while saving caregiver to the database: " + e.getMessage());
        }
    }

    private Address toAddress(AddressDto dto) {

        return Address.builder()
                .line1(dto.line1())
                .line2(dto.line2())
                .city(dto.city())
                .state(dto.state())
                .zip(dto.zip())
                .build();
    }

public boolean hasAccessToPatient(Long userId, Long patientId) {
    User user = users.findById(userId)
        .orElse(null);
    
    if (user == null) {
        return false;
    }
    
    // Check role-specific access
    switch (user.getRole()) {
        case PATIENT:
            // Patient can only access their own data
            return patientRepository.existsByIdAndUserId(patientId, userId);
            
        case CAREGIVER:
            // Use the new query method
            return patientRepository.hasAccessByCaregiverId(patientId, userId);
            
        case FAMILY_MEMBER:
            // Similar check for family members
            return familyMemberLinkRepository.existsByFamilyMemberUserIdAndPatientId(
                userId,
                patientId,
                LocalDateTime.now()
            );
            
        case ADMIN:
            return true;
            
        default:
            return false;
    }
}

/**
 * Check if a caregiver (by caregiver entity ID) has access to a patient (by patient entity ID)
 * This method handles the conversion from entity IDs to user IDs internally
 */
public boolean caregiverHasAccessToPatient(Long caregiverId, Long patientId) {
    // Get caregiver and extract user ID
    Caregiver caregiver = caregiverRepository.findById(caregiverId).orElse(null);
    if (caregiver == null) {
        return false;
    }
    
    // Get patient and extract user ID  
    Patient patient = patientRepository.findById(patientId).orElse(null);
    if (patient == null) {
        return false;
    }
    
    // Use the existing CaregiverPatientLinkService which works with user IDs
    return caregiverPatientLinkService.hasAccessToPatient(caregiver.getUser().getId(), patient.getUser().getId());
}

/**
 * Get a specific patient with link information by patientId for a caregiver
 * @param caregiverId The ID of the caregiver
 * @param patientId The ID of the patient
 * @return A PatientWithLinkDto object containing patient and link information
 */
public PatientWithLinkDto getPatientWithLinkById(Long caregiverId, Long patientId) {
    // Get caregiver user
    Caregiver caregiver = getCaregiverById(caregiverId);
    User caregiverUser = caregiver.getUser();
    
    // Check if patient exists
    Patient patient = patientRepository.findById(patientId)
        .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Patient not found"));
    
    // Get link between caregiver and patient
    List<CaregiverPatientLinkResponse> activeLinks = caregiverPatientLinkService.getPatientsByCaregiver(caregiverUser.getId());
    
    // Find the specific link for this patient
    Optional<CaregiverPatientLinkResponse> linkOpt = activeLinks.stream()
        .filter(link -> link.patientUserId().equals(patient.getUser().getId()))
        .findFirst();
    
    if (linkOpt.isEmpty()) {
        throw new AppException(HttpStatus.FORBIDDEN, "Caregiver has no active link to this patient");
    }
    
    // Build summary DTO for consistent API response
    PatientSummaryDTO summary = PatientSummaryDTO.builder()
        .id(patient.getId())
        .firstName(patient.getFirstName())
        .lastName(patient.getLastName())
        .email(patient.getEmail())
        .phone(patient.getPhone())
        .dob(patient.getDob())
        .gender(patient.getGender())
        .address(patient.getAddress())
        .relationship(patient.getRelationship())
        .build();
    List<PatientRiskResponseDto> risks = patientRiskService.getFlaggedRisksForPatient(patientId).stream()
        .map(PatientRiskResponseDto::from)
        .toList();
    return new PatientWithLinkDto(summary, linkOpt.get(), risks);
}
/**
     * Grant feature access for a caregiver across all active patient links (WBS 3.10.1 / Ticket 505)
     */
    public void grantPermission(Long caregiverId, String permission) {
        Caregiver caregiver = caregiverRepository.findById(caregiverId)
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Caregiver not found"));

        List<CaregiverPatientLinkResponse> activeLinks = 
                caregiverPatientLinkService.getPatientsByCaregiver(caregiver.getUser().getId());

        for (CaregiverPatientLinkResponse link : activeLinks) {
            caregiverPatientLinkService.grantPermission(link.id(), permission, caregiver.getUser().getId());
        }
    }

    /**
     * Revoke feature access for a caregiver across all active patient links (WBS 3.10.1 / Ticket 505)
     */
    public void revokePermission(Long caregiverId, String permission) {
        Caregiver caregiver = caregiverRepository.findById(caregiverId)
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Caregiver not found"));

        List<CaregiverPatientLinkResponse> activeLinks = 
                caregiverPatientLinkService.getPatientsByCaregiver(caregiver.getUser().getId());

        for (CaregiverPatientLinkResponse link : activeLinks) {
            caregiverPatientLinkService.revokePermission(link.id(), permission, caregiver.getUser().getId());
        }
    }
}