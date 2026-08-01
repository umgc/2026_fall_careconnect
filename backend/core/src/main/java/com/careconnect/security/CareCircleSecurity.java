package com.careconnect.security;

import java.time.LocalDateTime;
import java.util.Optional;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.stereotype.Component;

import com.careconnect.model.User;
import com.careconnect.repository.CaregiverPatientLinkRepository;
import com.careconnect.repository.UserRepository; // Assuming you have a UserRepository to look up Users by email/ID

@Component("careCircleSecurity")
public class CareCircleSecurity {

    private final CaregiverPatientLinkRepository linkRepository;
    private final UserRepository userRepository;

    @Autowired
    public CareCircleSecurity(CaregiverPatientLinkRepository linkRepository, UserRepository userRepository) {
        this.linkRepository = linkRepository;
        this.userRepository = userRepository;
    }

    /**
     * Secures endpoints by verifying if an active, non-expired care-circle link
     * exists between the authenticated caregiver and the target patient.
     */
    public boolean isCaregiverForPatient(Authentication authentication, Long patientId) {
        if (authentication == null || !authentication.isAuthenticated()) {
            return false;
        }

        // 1. Admins bypass the check
        if (authentication.getAuthorities().contains(new SimpleGrantedAuthority("ROLE_ADMIN"))) {
            return true;
        }

        // 2. Ensure the user has the CAREGIVER role
        if (!authentication.getAuthorities().contains(new SimpleGrantedAuthority("ROLE_CAREGIVER"))) {
            return false;
        }

        // 3. Resolve the Caregiver User entity by email/username
        String caregiverEmail = authentication.getName();
        Optional<User> caregiverOpt = userRepository.findByEmail(caregiverEmail); // Adjust findByEmail if yours is named differently
        if (caregiverOpt.isEmpty()) {
            return false;
        }

        // 4. Resolve the Patient User entity by ID
        Optional<User> patientOpt = userRepository.findById(patientId);
        if (patientOpt.isEmpty()) {
            return false;
        }

        try {
            // 5. Query your repository using the precise method you defined
            return linkRepository.existsActiveNonExpiredLink(
                caregiverOpt.get(), 
                patientOpt.get(), 
                LocalDateTime.now()
            );
        } catch (Exception e) {
            // Secure by default on system errors
            return false;
        }
    }
}