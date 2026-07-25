package com.careconnect.service;

import com.careconnect.dto.CreateProfileShareRequest;
import com.careconnect.dto.CreateProfileShareResponse;
import com.careconnect.dto.PublicProfileShareDto;
import com.careconnect.dto.RevokeProfileShareRequest;
import com.careconnect.exception.AppException;
import com.careconnect.model.Patient;
import com.careconnect.model.ProfileShareToken;
import com.careconnect.model.User;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.ProfileShareTokenRepository;
import com.careconnect.security.Role;
import com.careconnect.security.TokenHashService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.security.SecureRandom;
import java.time.LocalDateTime;
import java.util.Base64;
import java.util.Optional;

/**
 * Lifecycle for opaque patient profile-share tokens.
 *
 * Create / revoke are authenticated (patient or admin). Resolve is public and
 * returns a limited DTO — never embeds the patient id in the share URL.
 */
@Service
@Transactional
public class ProfileShareTokenService {

    private static final Logger log = LoggerFactory.getLogger(ProfileShareTokenService.class);
    private static final SecureRandom RANDOM = new SecureRandom();
    private static final int LOOKUP_LENGTH = 16;

    private final ProfileShareTokenRepository tokenRepository;
    private final PatientRepository patientRepository;
    private final TokenHashService tokenHashService;

    @Value("${careconnect.profile-share.base-url:https://app.careconnect.io/p}")
    private String shareBaseUrl;

    @Value("${careconnect.profile-share.default-ttl-hours:168}")
    private int defaultTtlHours;

    @Value("${careconnect.profile-share.max-ttl-hours:720}")
    private int maxTtlHours;

    public ProfileShareTokenService(ProfileShareTokenRepository tokenRepository,
                                    PatientRepository patientRepository,
                                    TokenHashService tokenHashService) {
        this.tokenRepository = tokenRepository;
        this.patientRepository = patientRepository;
        this.tokenHashService = tokenHashService;
    }

    public CreateProfileShareResponse create(CreateProfileShareRequest request, User actor) {
        Patient patient = resolvePatientForActor(actor);

        if (tokenRepository.existsActiveToken(patient.getUser().getId(), LocalDateTime.now())) {
            throw new AppException(HttpStatus.CONFLICT,
                    "An active profile share link already exists. Revoke it before creating a new one.");
        }

        int ttl = resolveTtl(request != null ? request.ttlHours() : null);
        String rawToken = generateRawToken();
        String lookup = rawToken.substring(0, LOOKUP_LENGTH);

        ProfileShareToken token = new ProfileShareToken();
        token.setTokenLookup(lookup);
        token.setTokenHash(tokenHashService.hashToken(rawToken));
        token.setPatientUserId(patient.getUser().getId());
        token.setPatientId(patient.getId());
        token.setStatus(ProfileShareToken.Status.ACTIVE);
        token.setCreatedByUserId(actor.getId());
        token.setExpiresAt(LocalDateTime.now().plusHours(ttl));

        try {
            token = tokenRepository.saveAndFlush(token);
        } catch (org.springframework.dao.DataIntegrityViolationException e) {
            throw new AppException(HttpStatus.CONFLICT,
                    "An active profile share link already exists. Revoke it before creating a new one.");
        }

        log.info("Profile share token created: tokenId={}, patientUserId={}, createdBy={}",
                token.getId(), token.getPatientUserId(), actor.getId());

        return new CreateProfileShareResponse(
                token.getId(),
                rawToken,
                buildShareUrl(rawToken),
                token.getStatus().name(),
                token.getExpiresAt(),
                token.getCreatedAt()
        );
    }

    public void revoke(Long tokenId, RevokeProfileShareRequest request, User actor) {
        ProfileShareToken token = tokenRepository.findById(tokenId)
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Profile share token not found"));

        Patient patient = resolvePatientForActor(actor);
        if (!token.getPatientUserId().equals(patient.getUser().getId())
                && actor.getRole() != Role.ADMIN) {
            throw new AppException(HttpStatus.FORBIDDEN, "Token does not belong to this patient");
        }

        if (token.getStatus() != ProfileShareToken.Status.ACTIVE) {
            log.info("Revoke no-op: profile share token {} already in status {}", tokenId, token.getStatus());
            return;
        }

        token.setStatus(ProfileShareToken.Status.REVOKED);
        token.setRevokedByUserId(actor.getId());
        token.setRevokedAt(LocalDateTime.now());
        token.setRevokeReason(request != null ? request.reason() : null);
        tokenRepository.save(token);

        log.info("Profile share revoked: tokenId={}, revokedBy={}", tokenId, actor.getId());
    }

    /**
     * Public resolve. Non-enumerating for unknown / hash-mismatch tokens
     * (collapsed to INVALID). Usable tokens return a limited profile DTO.
     */
    @Transactional(readOnly = true)
    public PublicProfileShareDto resolve(String rawToken) {
        Optional<ProfileShareToken> maybe = resolveTokenQuietly(rawToken);
        if (maybe.isEmpty()) {
            return PublicProfileShareDto.invalid("INVALID", "This share link is not valid.");
        }

        ProfileShareToken token = maybe.get();
        switch (token.getStatus()) {
            case REVOKED -> {
                return PublicProfileShareDto.invalid("REVOKED", "This share link has been revoked.");
            }
            case EXPIRED -> {
                return PublicProfileShareDto.invalid("EXPIRED", "This share link has expired.");
            }
            case ACTIVE -> {
                if (token.isExpired()) {
                    return PublicProfileShareDto.invalid("EXPIRED", "This share link has expired.");
                }
            }
            default -> {
                return PublicProfileShareDto.invalid("INVALID", "This share link is not valid.");
            }
        }

        Patient patient = patientRepository.findById(token.getPatientId()).orElse(null);
        if (patient == null) {
            return PublicProfileShareDto.invalid("INVALID", "This share link is not valid.");
        }

        return new PublicProfileShareDto(
                "ACTIVE",
                patient.getFirstName(),
                patient.getLastName(),
                patient.getPreferredCommunicationMethod(),
                null
        );
    }

    private Patient resolvePatientForActor(User actor) {
        if (actor.getRole() == Role.PATIENT) {
            return patientRepository.findByUser(actor)
                    .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Patient profile not found"));
        }
        if (actor.getRole() == Role.ADMIN) {
            // Admin creating on behalf of self is unsupported without a patient target;
            // require the actor to also have a patient profile, otherwise 403.
            return patientRepository.findByUser(actor)
                    .orElseThrow(() -> new AppException(HttpStatus.FORBIDDEN,
                            "Only patients (or admins with a patient profile) can create profile share links"));
        }
        throw new AppException(HttpStatus.FORBIDDEN, "Only patients or admins can manage profile share links");
    }

    private Optional<ProfileShareToken> resolveTokenQuietly(String rawToken) {
        if (rawToken == null || rawToken.length() < LOOKUP_LENGTH) {
            return Optional.empty();
        }
        String lookup = rawToken.substring(0, LOOKUP_LENGTH);
        Optional<ProfileShareToken> maybe = tokenRepository.findByTokenLookup(lookup);
        if (maybe.isEmpty()) {
            return Optional.empty();
        }
        if (!tokenHashService.verifyToken(rawToken, maybe.get().getTokenHash())) {
            return Optional.empty();
        }
        return maybe;
    }

    private int resolveTtl(Integer requested) {
        if (requested == null || requested <= 0) return defaultTtlHours;
        return Math.min(requested, maxTtlHours);
    }

    private String generateRawToken() {
        byte[] bytes = new byte[32];
        RANDOM.nextBytes(bytes);
        return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
    }

    private String buildShareUrl(String rawToken) {
        String base = shareBaseUrl.endsWith("/")
                ? shareBaseUrl.substring(0, shareBaseUrl.length() - 1)
                : shareBaseUrl;
        return base + "/" + rawToken;
    }
}
