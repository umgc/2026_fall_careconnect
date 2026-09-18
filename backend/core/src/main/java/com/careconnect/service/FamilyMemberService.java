package com.careconnect.service;

import com.careconnect.dto.*;
import com.careconnect.model.Address;
import com.careconnect.model.FamilyMember;
import com.careconnect.model.FamilyMemberLink;
import com.careconnect.model.Patient;
import com.careconnect.model.User;
import com.careconnect.repository.*;
import com.careconnect.security.Role;
import com.careconnect.exception.AppException;
import lombok.RequiredArgsConstructor;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Period;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;
import java.util.stream.Collectors;

@Service
@Transactional
public class FamilyMemberService {

    private static final Logger log = LoggerFactory.getLogger(FamilyMemberService.class);
    private final GamificationService gamificationService;
    private final FamilyMemberRepository familyMemberRepository;
    private final FamilyMemberLinkRepository familyMemberLinkRepository;
    private final UserRepository userRepository;
    private final PatientRepository patientRepository;
    private final PasswordEncoder passwordEncoder;
    private final EmailService emailService;
    private final AnalyticsService analyticsService;

    public FamilyMemberService(FamilyMemberRepository familyMemberRepository,
                               FamilyMemberLinkRepository familyMemberLinkRepository,
                               UserRepository userRepository,
                               PatientRepository patientRepository,
                               PasswordEncoder passwordEncoder,
                               EmailService emailService,
                               AnalyticsService analyticsService,
                               GamificationService gamificationService) {
        this.familyMemberRepository = familyMemberRepository;
        this.familyMemberLinkRepository = familyMemberLinkRepository;
        this.userRepository = userRepository;
        this.patientRepository = patientRepository;
        this.passwordEncoder = passwordEncoder;
        this.emailService = emailService;
        this.analyticsService = analyticsService;
        this.gamificationService = gamificationService;

        log.debug("FamilyMemberService initialized - passwordEncoder is null: {}", passwordEncoder == null);
    }

    /**
     * Register a new family member and link them to a patient
     */
    public FamilyMemberLinkResponse registerFamilyMember(FamilyMemberRegistration registration, Long grantedByUserId) {
        log.debug("registerFamilyMember - registration: email={}, firstName={}, lastName={}, patientUserId={}, grantedByUserId={}",
                registration.email(), registration.firstName(), registration.lastName(),
                registration.patientUserId(), grantedByUserId);

        // Validate required fields
        if (registration.email() == null || registration.email().trim().isEmpty()) {
            throw new AppException(HttpStatus.BAD_REQUEST, "Email is required for family member registration");
        }

        if (registration.firstName() == null || registration.firstName().trim().isEmpty()) {
            throw new AppException(HttpStatus.BAD_REQUEST, "First name is required for family member registration");
        }

        if (registration.lastName() == null || registration.lastName().trim().isEmpty()) {
            throw new AppException(HttpStatus.BAD_REQUEST, "Last name is required for family member registration");
        }

        if (registration.relationship() == null || registration.relationship().trim().isEmpty()) {
            throw new AppException(HttpStatus.BAD_REQUEST, "Relationship is required for family member registration");
        }

        // Verify the patient exists
        User patientUser = userRepository.findById(registration.patientUserId())
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Patient not found"));

        User grantedByUser = userRepository.findById(grantedByUserId)
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Granter user not found"));

        log.debug("Found patientUser: id={}, email={}", patientUser.getId(), patientUser.getEmail());
        log.debug("Found grantedByUser: id={}, email={}", grantedByUser.getId(), grantedByUser.getEmail());

        // Check if this email is already linked to this specific patient
        Optional<User> existingFamilyUser = userRepository.findByEmail(registration.email());
        if (existingFamilyUser.isPresent()) {
            // Email exists - check if already linked to this patient
            boolean alreadyLinked = familyMemberLinkRepository.existsByFamilyUserAndPatientUserAndStatus(
                    existingFamilyUser.get(), patientUser, FamilyMemberLink.LinkStatus.ACTIVE);
            if (alreadyLinked) {
                throw new AppException(HttpStatus.CONFLICT,
                        "This family member is already linked to this patient");
            }

            // Email exists but not linked to this patient - create link with existing user
            User familyUser = existingFamilyUser.get();
            log.debug("Using existing family member user: id={}, email={}", familyUser.getId(), familyUser.getEmail());

            // Create family member link with existing user
            FamilyMemberLink link = new FamilyMemberLink(
                    familyUser, patientUser, grantedByUser, registration.relationship());

            // Set the denormalized patient_id for faster queries
            Patient patient = patientRepository.findByUser(patientUser)
                    .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Patient profile not found"));
            link.setPatientId(patient.getId());

            familyMemberLinkRepository.save(link);

            // Send access granted email to existing family member
            String patientName = getPatientName(patientUser);
            String familyMemberFirstName = getFamilyMemberFirstName(familyUser);
            emailService.sendFamilyMemberAccessGrantedEmail(
                    familyUser.getEmail(),
                    familyMemberFirstName,
                    patientName
            );

            log.debug("Sent access granted email to existing family member: {}", familyUser.getEmail());

            boolean isFirstLink = familyMemberLinkRepository
                    .findActiveFamilyMembersByPatient(patientUser.getId(), LocalDateTime.now())
                    .size() == 1;

            if (isFirstLink) {
                gamificationService.unlockAchievement(
                        patientUser.getId(),
                        "Added Family Member",
                        20
                );
            }

            return toFamilyMemberLinkResponse(link);
        }

        // Email doesn't exist - create new family member user and profile
        log.debug("Creating new family member user for email: {}", registration.email());

        // Generate password setup token
        String passwordSetupToken = java.util.UUID.randomUUID().toString();

        // Generate a random password (will be changed when user sets up via email)
        String randomPassword = java.util.UUID.randomUUID().toString();

        log.debug("Generated random password: {}, passwordEncoder is null: {}", randomPassword, passwordEncoder == null);

        // Create User account
        User familyUser = new User();
        familyUser.setEmail(registration.email());
        familyUser.setRole(Role.FAMILY_MEMBER);
        familyUser.setIsVerified(false);
        familyUser.setVerificationToken(passwordSetupToken);

        // Encode and set password
        if (passwordEncoder == null) {
            log.error("PasswordEncoder is null! Cannot encode password");
            throw new AppException(HttpStatus.INTERNAL_SERVER_ERROR, "Password encoder is not available");
        }

        if (randomPassword == null || randomPassword.trim().isEmpty()) {
            log.error("Generated password is null or empty!");
            throw new AppException(HttpStatus.INTERNAL_SERVER_ERROR, "Failed to generate password");
        }

        String encodedPassword = passwordEncoder.encode(randomPassword);
        if (encodedPassword == null || encodedPassword.trim().isEmpty()) {
            log.error("Encoded password is null or empty!");
            throw new AppException(HttpStatus.INTERNAL_SERVER_ERROR, "Failed to encode password");
        }

        familyUser.setPassword(encodedPassword);
        familyUser.setPasswordHash(encodedPassword);

        log.debug("About to save familyUser: email={}, role={}, verified={}, hasPassword={}, encodedPasswordLength={}, hasPasswordHash={}, encodedPasswordHashLength={}",
                familyUser.getEmail(), familyUser.getRole(), familyUser.getIsVerified(),
                familyUser.getPassword() != null, familyUser.getPassword() != null ? familyUser.getPassword().length() : 0,
                familyUser.getPasswordHash() != null, familyUser.getPasswordHash() != null ? familyUser.getPasswordHash().length() : 0);

        userRepository.save(familyUser);

        // Create FamilyMember profile
        Address address = null;
        if (registration.address() != null) {
            address = Address.builder()
                    .line1(registration.address().line1())
                    .line2(registration.address().line2())
                    .city(registration.address().city())
                    .state(registration.address().state())
                    .zip(registration.address().zip())
                    .build();
        }

        FamilyMember familyMember = FamilyMember.builder()
                .user(familyUser)
                .firstName(registration.firstName())
                .lastName(registration.lastName())
                .email(registration.email())
                .phone(registration.phone())
                .address(address)
                .build();
        familyMemberRepository.save(familyMember);

        // Create family member link
        FamilyMemberLink link = new FamilyMemberLink(
                familyUser, patientUser, grantedByUser, registration.relationship());

        // Set the denormalized patient_id for faster queries
        Patient patient = patientRepository.findByUser(patientUser)
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Patient profile not found"));
        link.setPatientId(patient.getId());

        familyMemberLinkRepository.save(link);

        // Send password setup email with credentials
        emailService.sendPasswordSetupEmailWithCredentials(
                registration.email(),
                passwordSetupToken,
                registration.firstName(),
                registration.email(), // username is email
                randomPassword
        );

        return toFamilyMemberLinkResponse(link);
    }

    /**
     * Get all patients accessible to a family member
     */
    @Transactional(readOnly = true)
    public List<PatientDataResponse> getAccessiblePatients(Long familyUserId) {
        List<FamilyMemberLink> links = familyMemberLinkRepository.findActivePatientsByFamilyMember(familyUserId, LocalDateTime.now());

        return links.stream()
                .map(this::toPatientDataResponse)
                .collect(Collectors.toList());
    }

    /**
     * Get specific patient data if family member has access
     */
    @Transactional(readOnly = true)
    public PatientDataResponse getPatientData(Long familyUserId, Long patientUserId) {
        User familyUser = userRepository.findById(familyUserId)
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Family member not found"));

        User patientUser = userRepository.findById(patientUserId)
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Patient not found"));

        // Verify access
        FamilyMemberLink link = familyMemberLinkRepository
                .findByFamilyUserAndPatientUserAndStatus(familyUser, patientUser, FamilyMemberLink.LinkStatus.ACTIVE)
                .orElseThrow(() -> new AppException(HttpStatus.FORBIDDEN, "Access denied to patient data"));

        return toPatientDataResponse(link);
    }

    /**
     * Get all family members linked to a patient (by user ID)
     */
    @Transactional(readOnly = true)
    public List<FamilyMemberLinkResponse> getFamilyMembersByPatient(Long patientUserId) {
        List<FamilyMemberLink> links = familyMemberLinkRepository.findActiveFamilyMembersByPatient(patientUserId, LocalDateTime.now());

        return links.stream()
                .map(this::toFamilyMemberLinkResponse)
                .collect(Collectors.toList());
    }

    /**
     * Get all family members linked to a patient (by patient ID - optimized)
     */
    @Transactional(readOnly = true)
    public List<FamilyMemberLinkResponse> getFamilyMembersByPatientId(Long patientId) {
        List<FamilyMemberLink> links = familyMemberLinkRepository.findActiveFamilyMembersByPatientId(patientId, LocalDateTime.now());

        return links.stream()
                .map(this::toFamilyMemberLinkResponse)
                .collect(Collectors.toList());
    }

    /**
     * Get all patients linked to a family member
     */
    @Transactional(readOnly = true)
    public List<FamilyMemberLinkResponse> getPatientsByFamilyMember(Long familyUserId) {
        List<FamilyMemberLink> links = familyMemberLinkRepository.findActivePatientsByFamilyMember(familyUserId, LocalDateTime.now());

        return links.stream()
                .map(this::toFamilyMemberLinkResponse)
                .collect(Collectors.toList());
    }

    /**
     * Revoke family member access to a patient
     */
    public void revokeFamilyMemberAccess(Long linkId, Long revokedByUserId) {
        FamilyMemberLink link = familyMemberLinkRepository.findById(linkId)
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Family member link not found"));

        link.setStatus(FamilyMemberLink.LinkStatus.REVOKED);
        familyMemberLinkRepository.save(link);
    }

    /**
     * Check if family member has access to specific patient (ACTIVE and not expired)
     */
    @Transactional(readOnly = true)
    public boolean hasAccessToPatient(Long familyUserId, Long patientUserId) {
        User familyUser = userRepository.findById(familyUserId).orElse(null);
        User patientUser = userRepository.findById(patientUserId).orElse(null);

        if (familyUser == null || patientUser == null) {
            return false;
        }

        return familyMemberLinkRepository.existsActiveNonExpiredLink(familyUser, patientUser, LocalDateTime.now());
    }

    /**
     * Create a temporary family member link
     */
    public FamilyMemberLinkResponse createTemporaryLink(Long familyUserId, Long patientUserId, String relationship,
                                                        LocalDateTime expiresAt, String notes, Long grantedByUserId) {
        User familyUser = userRepository.findById(familyUserId)
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Family member not found"));

        User patientUser = userRepository.findById(patientUserId)
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Patient not found"));

        User grantedByUser = userRepository.findById(grantedByUserId)
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Granter user not found"));

        // Check if active link already exists
        if (familyMemberLinkRepository.existsByFamilyUserAndPatientUserAndStatus(
                familyUser, patientUser, FamilyMemberLink.LinkStatus.ACTIVE)) {
            throw new AppException(HttpStatus.CONFLICT, "Active link already exists");
        }

        FamilyMemberLink link = new FamilyMemberLink(familyUser, patientUser, grantedByUser, relationship,
                FamilyMemberLink.LinkType.TEMPORARY);
        link.setExpiresAt(expiresAt);
        link.setNotes(notes);

        // Set the denormalized patient_id for faster queries
        Patient patient = patientRepository.findByUser(patientUser)
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Patient profile not found"));
        link.setPatientId(patient.getId());

        familyMemberLinkRepository.save(link);

        return toFamilyMemberLinkResponse(link);
    }

    /**
     * Update family member link (suspend, reactivate, extend expiration, etc.)
     */
    public FamilyMemberLinkResponse updateFamilyMemberLink(Long linkId, UpdateLinkRequest request, Long updatedByUserId) {
        FamilyMemberLink link = familyMemberLinkRepository.findById(linkId)
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Family member link not found"));

        if (request.status() != null) {
            link.setStatus(FamilyMemberLink.LinkStatus.valueOf(request.status().toUpperCase()));
        }
        if (request.linkType() != null) {
            link.setLinkType(FamilyMemberLink.LinkType.valueOf(request.linkType().toUpperCase()));
        }
        if (request.expiresAt() != null) {
            link.setExpiresAt(request.expiresAt());
        }
        if (request.notes() != null) {
            link.setNotes(request.notes());
        }

        familyMemberLinkRepository.save(link);
        return toFamilyMemberLinkResponse(link);
    }

    /**
     * Temporarily suspend family member access
     */
    public FamilyMemberLinkResponse suspendFamilyMemberAccess(Long linkId, Long suspendedByUserId) {
        FamilyMemberLink link = familyMemberLinkRepository.findById(linkId)
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Family member link not found"));

        link.setStatus(FamilyMemberLink.LinkStatus.SUSPENDED);
        familyMemberLinkRepository.save(link);

        return toFamilyMemberLinkResponse(link);
    }

    /**
     * Reactivate suspended family member access
     */
    public FamilyMemberLinkResponse reactivateFamilyMemberAccess(Long linkId, Long reactivatedByUserId) {
        FamilyMemberLink link = familyMemberLinkRepository.findById(linkId)
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Family member link not found"));

        if (link.getStatus() != FamilyMemberLink.LinkStatus.SUSPENDED) {
            throw new AppException(HttpStatus.BAD_REQUEST, "Only suspended links can be reactivated");
        }

        link.setStatus(FamilyMemberLink.LinkStatus.ACTIVE);
        familyMemberLinkRepository.save(link);

        return toFamilyMemberLinkResponse(link);
    }

    /**
     * Cleanup expired family member links
     */
    public void cleanupExpiredFamilyMemberLinks() {
        List<FamilyMemberLink> allLinks = familyMemberLinkRepository.findAll();
        allLinks.stream()
                .filter(link -> link.getStatus() == FamilyMemberLink.LinkStatus.ACTIVE && link.isExpired())
                .forEach(link -> {
                    link.setStatus(FamilyMemberLink.LinkStatus.EXPIRED);
                    familyMemberLinkRepository.save(link);
                });
    }

    // Helper methods
    private FamilyMemberLinkResponse toFamilyMemberLinkResponse(FamilyMemberLink link) {
        String familyMemberName = getFamilyMemberName(link.getFamilyUser());
        String patientName = getPatientName(link.getPatientUser());
        String grantedByName = link.getGrantedBy() != null ? getUserName(link.getGrantedBy()) : "System";

        return new FamilyMemberLinkResponse(
                link.getId(),
                link.getFamilyUser().getId(),
                familyMemberName,
                link.getFamilyUser().getEmail(),
                link.getPatientUser().getId(),
                patientName,
                link.getRelationship(),
                link.getStatus().name(),
                link.getCreatedAt(),
                grantedByName
        );
    }

    private PatientDataResponse toPatientDataResponse(FamilyMemberLink link) {
        User patientUser = link.getPatientUser();
        Patient patient = patientRepository.findByUser(patientUser).orElse(null);

        String patientName = patient != null ?
                patient.getFirstName() + " " + patient.getLastName() :
                patientUser.getEmail();

        // Get read-only patient data
        DashboardDTO dashboard = analyticsService.getDashboard(patientUser.getId(), Period.ofDays(30));
        List<VitalSampleDTO> recentVitals = analyticsService.getVitals(patientUser.getId(), Period.ofDays(7));

        return new PatientDataResponse(
                patientUser.getId(),
                patientName,
                patientUser.getEmail(),
                patient != null ? patient.getPhone() : null,
                link.getRelationship(),
                recentVitals,
                dashboard,
                "READ_ONLY"
        );
    }

    private String getFamilyMemberName(User familyUser) {
        return familyMemberRepository.findByUser(familyUser)
                .map(fm -> fm.getFirstName() + " " + fm.getLastName())
                .orElse(familyUser.getEmail());
    }

    private String getFamilyMemberFirstName(User familyUser) {
        return familyMemberRepository.findByUser(familyUser)
                .map(fm -> fm.getFirstName())
                .orElse(familyUser.getEmail());
    }

    private String getPatientName(User patientUser) {
        return patientRepository.findByUser(patientUser)
                .map(p -> p.getFirstName() + " " + p.getLastName())
                .orElse(patientUser.getEmail());
    }

    private String getUserName(User user) {
        // Try to get name from specific role tables
        switch (user.getRole()) {
            case PATIENT:
                return getPatientName(user);
            case FAMILY_MEMBER:
                return getFamilyMemberName(user);
            case CAREGIVER:
                // Add caregiver name lookup if needed
                return user.getEmail();
            default:
                return user.getEmail();
        }
    }
}
