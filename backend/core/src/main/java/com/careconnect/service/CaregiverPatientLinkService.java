package com.careconnect.service;

import com.careconnect.dto.CaregiverPatientLinkResponse;
import com.careconnect.dto.CreateLinkRequest;
import com.careconnect.dto.UpdateLinkRequest;
import com.careconnect.exception.AppException;
import com.careconnect.model.*;
import com.careconnect.repository.*;
import com.careconnect.security.Role;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
@Transactional
public class CaregiverPatientLinkService {
    private static final String PATIENT_VIDEO_CALLS_DISABLED_TOKEN = "[PATIENT_VIDEO_CALLS=OFF]";
    private static final String PATIENT_MESSAGING_DISABLED_TOKEN   = "[PATIENT_MESSAGING=OFF]";

    private final CaregiverPatientLinkRepository caregiverPatientLinkRepository;
    private final UserRepository userRepository;
    private final PatientRepository patientRepository;
    private final CaregiverRepository caregiverRepository;

    /**
     * Create a new caregiver-patient link
     */
    public CaregiverPatientLinkResponse createLink(Long caregiverUserId, CreateLinkRequest request, Long createdByUserId) {
        User caregiverUser = userRepository.findById(caregiverUserId)
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Caregiver not found"));

        User patientUser = userRepository.findById(request.targetUserId())
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Patient not found"));

        User createdBy = userRepository.findById(createdByUserId)
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Creator user not found"));

        // Check if active link already exists
        if (caregiverPatientLinkRepository.existsByCaregiverUserAndPatientUserAndStatus(
                caregiverUser, patientUser, CaregiverPatientLink.LinkStatus.ACTIVE)) {
            throw new AppException(HttpStatus.CONFLICT, "Active link already exists between caregiver and patient");
        }

        CaregiverPatientLink link = new CaregiverPatientLink();
        link.setCaregiverUser(caregiverUser);
        link.setPatientUser(patientUser);
        link.setCreatedBy(createdBy);
        link.setLinkType(CaregiverPatientLink.LinkType.valueOf(request.linkType().toUpperCase()));
        link.setExpiresAt(request.expiresAt());
        link.setNotes(request.notes());

        caregiverPatientLinkRepository.save(link);
        return toCaregiverPatientLinkResponse(link);
    }

    /**
     * Update an existing link (suspend, reactivate, change type, etc.)
     */
    public CaregiverPatientLinkResponse updateLink(Long linkId, UpdateLinkRequest request, Long updatedByUserId) {
        CaregiverPatientLink link = caregiverPatientLinkRepository.findById(linkId)
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Link not found"));

        if (request.status() != null) {
            link.setStatus(CaregiverPatientLink.LinkStatus.valueOf(request.status().toUpperCase()));
        }
        if (request.linkType() != null) {
            link.setLinkType(CaregiverPatientLink.LinkType.valueOf(request.linkType().toUpperCase()));
        }
        if (request.expiresAt() != null) {
            link.setExpiresAt(request.expiresAt());
        }
        if (request.notes() != null) {
            link.setNotes(request.notes());
        }

        caregiverPatientLinkRepository.save(link);
        return toCaregiverPatientLinkResponse(link);
    }

    /**
     * Temporarily suspend a link
     */
//    public CaregiverPatientLinkResponse suspendLink(Long linkId, Long suspendedByUserId) {
//        CaregiverPatientLink link = caregiverPatientLinkRepository.findById(linkId)
//                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Link not found"));
//
//        link.setStatus(CaregiverPatientLink.LinkStatus.SUSPENDED);
//        caregiverPatientLinkRepository.save(link);
//
//        return toCaregiverPatientLinkResponse(link);
//    }

    public CaregiverPatientLinkResponse suspendLink(Long linkId, String suspendedByIdentifier) {
        CaregiverPatientLink link = caregiverPatientLinkRepository.findById(linkId)
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Link not found"));

        User suspendedBy;
        try {
            // Try to parse as Long (user ID)
            Long userId = Long.parseLong(suspendedByIdentifier);
            suspendedBy = userRepository.findById(userId)
                    .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "User not found"));
        } catch (NumberFormatException e) {
            // Fallback to email
            suspendedBy = userRepository.findByEmail(suspendedByIdentifier)
                    .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "User not found"));
        }

        // Optionally check role here if needed
        link.setStatus(CaregiverPatientLink.LinkStatus.SUSPENDED);
        caregiverPatientLinkRepository.save(link);

        return toCaregiverPatientLinkResponse(link);
    }
    /**
     * Reactivate a suspended link
     */
    public CaregiverPatientLinkResponse reactivateLink(Long linkId, Long reactivatedByUserId) {
        CaregiverPatientLink link = caregiverPatientLinkRepository.findById(linkId)
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Link not found"));

        if (link.getStatus() != CaregiverPatientLink.LinkStatus.SUSPENDED) {
            throw new AppException(HttpStatus.BAD_REQUEST, "Only suspended links can be reactivated");
        }

        link.setStatus(CaregiverPatientLink.LinkStatus.ACTIVE);
        caregiverPatientLinkRepository.save(link);

        return toCaregiverPatientLinkResponse(link);
    }

    /**
     * Permanently revoke a link
     */
    public void revokeLink(Long linkId, Long revokedByUserId) {
        CaregiverPatientLink link = caregiverPatientLinkRepository.findById(linkId)
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Link not found"));

        link.setStatus(CaregiverPatientLink.LinkStatus.REVOKED);
        caregiverPatientLinkRepository.save(link);
    }

    /**
     * Get all patients linked to a caregiver
     */
    @Transactional(readOnly = true)
    public List<CaregiverPatientLinkResponse> getPatientsByCaregiver(Long caregiverUserId) {
        User caregiverUser = userRepository.findById(caregiverUserId)
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Caregiver not found"));

        List<CaregiverPatientLink> links = caregiverPatientLinkRepository.findActivePatientsByCaregiver(caregiverUser, LocalDateTime.now());
        return links.stream()
                .map(this::toCaregiverPatientLinkResponse)
                .collect(Collectors.toList());
    }

    /**
     * Get all caregivers linked to a patient
     */
    @Transactional(readOnly = true)
    public List<CaregiverPatientLinkResponse> getCaregiversByPatient(Long patientUserId) {
        User patientUser = userRepository.findById(patientUserId)
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Patient not found"));

        List<CaregiverPatientLink> links = caregiverPatientLinkRepository.findActiveCaregiversByPatient(patientUser, LocalDateTime.now());
        return links.stream()
                .map(this::toCaregiverPatientLinkResponse)
                .collect(Collectors.toList());
    }

    /**
     * Check if caregiver has access to patient (ACTIVE and not expired)
     */
    @Transactional(readOnly = true)
    public boolean hasAccessToPatient(Long caregiverUserId, Long patientUserId) {
        User caregiverUser = userRepository.findById(caregiverUserId).orElse(null);
        User patientUser = userRepository.findById(patientUserId).orElse(null);

        if (caregiverUser == null || patientUser == null) {
            return false;
        }

        return caregiverPatientLinkRepository.existsActiveNonExpiredLink(caregiverUser, patientUser, LocalDateTime.now());
    }

    @Transactional(readOnly = true)
    public boolean isPatientVideoCallsEnabled(Long caregiverUserId, Long patientUserId) {
        User caregiverUser = userRepository.findById(caregiverUserId).orElse(null);
        User patientUser = userRepository.findById(patientUserId).orElse(null);
        if (caregiverUser == null || patientUser == null) {
            return false;
        }

        Optional<CaregiverPatientLink> link = caregiverPatientLinkRepository
                .findTopByCaregiverUserAndPatientUserAndStatusOrderByUpdatedAtDesc(
                        caregiverUser,
                        patientUser,
                        CaregiverPatientLink.LinkStatus.ACTIVE
                );

        return link.map(this::isPatientVideoCallsEnabledInternal).orElse(false);
    }

    public CaregiverPatientLinkResponse setPatientVideoCallsEnabled(
            Long linkId,
            boolean enabled,
            Long actorUserId,
            Role actorRole
    ) {
        CaregiverPatientLink link = caregiverPatientLinkRepository.findById(linkId)
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Link not found"));

        boolean isAdmin = actorRole == Role.ADMIN;
        boolean isOwningCaregiver = actorRole == Role.CAREGIVER
                && link.getCaregiverUser() != null
                && actorUserId.equals(link.getCaregiverUser().getId());

        if (!isAdmin && !isOwningCaregiver) {
            throw new AppException(HttpStatus.FORBIDDEN, "Access denied");
        }

        if (link.getStatus() != CaregiverPatientLink.LinkStatus.ACTIVE || link.isExpired()) {
            throw new AppException(HttpStatus.BAD_REQUEST, "Only active links can be updated");
        }

        link.setNotes(updatePatientVideoCallToken(link.getNotes(), enabled));
        caregiverPatientLinkRepository.save(link);
        return toCaregiverPatientLinkResponse(link);
    }

    @Transactional(readOnly = true)
    public boolean isPatientMessagingEnabled(Long caregiverUserId, Long patientUserId) {
        User caregiverUser = userRepository.findById(caregiverUserId).orElse(null);
        User patientUser   = userRepository.findById(patientUserId).orElse(null);
        if (caregiverUser == null || patientUser == null) return false;

        Optional<CaregiverPatientLink> link = caregiverPatientLinkRepository
                .findTopByCaregiverUserAndPatientUserAndStatusOrderByUpdatedAtDesc(
                        caregiverUser, patientUser, CaregiverPatientLink.LinkStatus.ACTIVE);
        return link.map(this::isPatientMessagingEnabledInternal).orElse(false);
    }

    public CaregiverPatientLinkResponse setPatientMessagingEnabled(
            Long linkId,
            boolean enabled,
            Long actorUserId,
            Role actorRole
    ) {
        CaregiverPatientLink link = caregiverPatientLinkRepository.findById(linkId)
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Link not found"));

        boolean isAdmin = actorRole == Role.ADMIN;
        boolean isOwningCaregiver = actorRole == Role.CAREGIVER
                && link.getCaregiverUser() != null
                && actorUserId.equals(link.getCaregiverUser().getId());

        if (!isAdmin && !isOwningCaregiver) {
            throw new AppException(HttpStatus.FORBIDDEN, "Access denied");
        }

        if (link.getStatus() != CaregiverPatientLink.LinkStatus.ACTIVE || link.isExpired()) {
            throw new AppException(HttpStatus.BAD_REQUEST, "Only active links can be updated");
        }

        link.setNotes(updatePatientMessagingToken(link.getNotes(), enabled));
        caregiverPatientLinkRepository.save(link);
        return toCaregiverPatientLinkResponse(link);
    }

    /**
     * Get all links (for admin purposes)
     */
    @Transactional(readOnly = true)
    public List<CaregiverPatientLinkResponse> getAllLinks() {
        return caregiverPatientLinkRepository.findAll().stream()
                .map(this::toCaregiverPatientLinkResponse)
                .collect(Collectors.toList());
    }

    /**
     * Cleanup expired links (should be run periodically)
     */
    public void cleanupExpiredLinks() {
        List<CaregiverPatientLink> expiredLinks = caregiverPatientLinkRepository.findExpiredActiveLinks(LocalDateTime.now());
        expiredLinks.forEach(link -> {
            link.setStatus(CaregiverPatientLink.LinkStatus.EXPIRED);
            caregiverPatientLinkRepository.save(link);
        });
    }

    /**
     * Create a permanent caregiver-patient link (used for patient registration)
     */
    public void createPermanentLink(Long caregiverUserId, Long patientUserId, String notes) {
        User caregiverUser = userRepository.findById(caregiverUserId)
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Caregiver not found"));

        User patientUser = userRepository.findById(patientUserId)
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Patient not found"));

        // Check if active link already exists
        if (caregiverPatientLinkRepository.existsActiveNonExpiredLink(caregiverUser, patientUser, LocalDateTime.now())) {
            return; // Link already exists, no need to create another one
        }

        CaregiverPatientLink link = new CaregiverPatientLink();
        link.setCaregiverUser(caregiverUser);
        link.setPatientUser(patientUser);
        link.setCreatedBy(caregiverUser); // Caregiver creates the link
        link.setLinkType(CaregiverPatientLink.LinkType.PERMANENT);
        link.setNotes(notes);

        caregiverPatientLinkRepository.save(link);
    }

    // Helper methods
    private CaregiverPatientLinkResponse toCaregiverPatientLinkResponse(CaregiverPatientLink link) {
        String caregiverName = getCaregiverName(link.getCaregiverUser());
        String patientName = getPatientName(link.getPatientUser());
        String createdByName = link.getCreatedBy() != null ? getUserName(link.getCreatedBy()) : "System";

        return new CaregiverPatientLinkResponse(
                link.getId(),
                link.getCaregiverUser().getId(),
                caregiverName,
                link.getCaregiverUser().getEmail(),
                link.getPatientUser().getId(),
                patientName,
                link.getPatientUser().getEmail(),
                link.getStatus().name(),
                link.getLinkType().name(),
                isPatientVideoCallsEnabledInternal(link),
                isPatientMessagingEnabledInternal(link),
                link.getCreatedAt(),
                link.getExpiresAt(),
                link.getNotes(),
                createdByName,
                link.isActive(),
                link.isExpired()
        );
    }

    private boolean isPatientVideoCallsEnabledInternal(CaregiverPatientLink link) {
        String notes = link.getNotes();
        if (notes == null || notes.isBlank()) {
            return true;
        }
        return !notes.contains(PATIENT_VIDEO_CALLS_DISABLED_TOKEN);
    }

    private boolean isPatientMessagingEnabledInternal(CaregiverPatientLink link) {
        String notes = link.getNotes();
        if (notes == null || notes.isBlank()) {
            return true;
        }
        return !notes.contains(PATIENT_MESSAGING_DISABLED_TOKEN);
    }

    private String updatePatientVideoCallToken(String notes, boolean enabled) {
        String base = notes == null ? "" : notes;
        base = base.replace(PATIENT_VIDEO_CALLS_DISABLED_TOKEN, "").trim();
        if (enabled) {
            return base.isBlank() ? null : base;
        }
        if (base.isBlank()) {
            return PATIENT_VIDEO_CALLS_DISABLED_TOKEN;
        }
        return base + " " + PATIENT_VIDEO_CALLS_DISABLED_TOKEN;
    }

    private String updatePatientMessagingToken(String notes, boolean enabled) {
        String base = notes == null ? "" : notes;
        base = base.replace(PATIENT_MESSAGING_DISABLED_TOKEN, "").trim();
        if (enabled) {
            return base.isBlank() ? null : base;
        }
        if (base.isBlank()) {
            return PATIENT_MESSAGING_DISABLED_TOKEN;
        }
        return base + " " + PATIENT_MESSAGING_DISABLED_TOKEN;
    }

    private String getCaregiverName(User caregiverUser) {
        return caregiverRepository.findByUser(caregiverUser)
                .map(c -> c.getFirstName() + " " + c.getLastName())
                .orElse(caregiverUser.getEmail());
    }

    private String getPatientName(User patientUser) {
        return patientRepository.findByUser(patientUser)
                .map(p -> p.getFirstName() + " " + p.getLastName())
                .orElse(patientUser.getEmail());
    }

    private String getUserName(User user) {
        switch (user.getRole()) {
            case PATIENT:
                return getPatientName(user);
            case CAREGIVER:
                return getCaregiverName(user);
            default:
                return user.getEmail();
        }
    }

    public boolean hasActiveLink(Long caregiverUserId, Long patientUserId) {
        User caregiverUser = userRepository.findById(caregiverUserId)
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Caregiver user not found"));

        User patientUser = userRepository.findById(patientUserId)
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Patient user not found"));

        return caregiverPatientLinkRepository.existsByCaregiverUserAndPatientUserAndStatus(
                caregiverUser, patientUser, CaregiverPatientLink.LinkStatus.ACTIVE);
    }
    public CaregiverPatientLinkResponse grantPermission(Long linkId, String feature, Long userId) {
        CaregiverPatientLink link = caregiverPatientLinkRepository.findById(linkId)
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Link not found"));

        String token = "[" + feature.trim().toUpperCase() + "=OFF]";
        String base = link.getNotes() == null ? "" : link.getNotes();
        base = base.replace(token, "").trim();
        link.setNotes(base.isBlank() ? null : base);

        caregiverPatientLinkRepository.save(link);
        return toCaregiverPatientLinkResponse(link);
    }

    public CaregiverPatientLinkResponse revokePermission(Long linkId, String feature, Long userId) {
        CaregiverPatientLink link = caregiverPatientLinkRepository.findById(linkId)
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Link not found"));

        String token = "[" + feature.trim().toUpperCase() + "=OFF]";
        String base = link.getNotes() == null ? "" : link.getNotes();
        base = base.replace(token, "").trim();
        link.setNotes(base.isBlank() ? token : base + " " + token);

        caregiverPatientLinkRepository.save(link);
        return toCaregiverPatientLinkResponse(link);
    }
}
