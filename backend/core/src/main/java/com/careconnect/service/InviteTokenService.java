package com.careconnect.service;

import com.careconnect.dto.*;
import com.careconnect.exception.AppException;
import com.careconnect.model.FamilyMemberLink;
import com.careconnect.model.InviteToken;
import com.careconnect.model.InviteTokenAudit;
import com.careconnect.model.Patient;
import com.careconnect.model.User;
import com.careconnect.repository.FamilyMemberLinkRepository;
import com.careconnect.repository.InviteTokenRepository;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.UserRepository;
import com.careconnect.security.TokenHashService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.security.SecureRandom;
import java.time.LocalDateTime;
import java.util.Base64;
import java.util.Optional;

/**
 * Service implementing the care-circle invite-token lifecycle (issue #53).
 *
 * Lifecycle: PENDING -> ACCEPTED | EXPIRED | REVOKED.
 *
 * Token strategy — opaque, DB-stored, hashed:
 *   * The raw token is a 256-bit URL-safe random string. It is returned exactly
 *     once (create response / share URL) and never persisted in plaintext.
 *   * We store a non-secret lookup prefix + a one-way BCrypt hash (reusing the
 *     existing {@link TokenHashService}). Lookup is O(1) by prefix, then we
 *     verify the hash. This gives revocability and full auditability that a
 *     stateless JWT cannot.
 *
 * All mutating operations are audited via {@link #audit}.
 */
@Service
@Transactional
public class InviteTokenService {

    private static final Logger log = LoggerFactory.getLogger(InviteTokenService.class);
    private static final SecureRandom RANDOM = new SecureRandom();
    private static final int LOOKUP_LENGTH = 16; // chars of the prefix used as the index key

    private final InviteTokenRepository tokenRepository;
    private final InviteAuditService auditService;
    private final FamilyMemberLinkRepository linkRepository;
    private final UserRepository userRepository;
    private final PatientRepository patientRepository;
    private final TokenHashService tokenHashService;

    @Value("${careconnect.invite.base-url:https://app.careconnect.io/invite}")
    private String inviteBaseUrl;

    @Value("${careconnect.invite.default-ttl-hours:72}")
    private int defaultTtlHours;

    @Value("${careconnect.invite.max-ttl-hours:168}")
    private int maxTtlHours;

    public InviteTokenService(InviteTokenRepository tokenRepository,
                              InviteAuditService auditService,
                              FamilyMemberLinkRepository linkRepository,
                              UserRepository userRepository,
                              PatientRepository patientRepository,
                              TokenHashService tokenHashService) {
        this.tokenRepository = tokenRepository;
        this.auditService = auditService;
        this.linkRepository = linkRepository;
        this.userRepository = userRepository;
        this.patientRepository = patientRepository;
        this.tokenHashService = tokenHashService;
    }

    // =====================================================================
    // CREATE  — POST /care-circle/{linkId}/invite
    // =====================================================================

    /**
     * Issue a unique invite token for an existing care-circle link.
     *
     * @param linkId        the family_member_link this invite is scoped to
     * @param request       optional email, reason, ttl
     * @param createdByUser the authenticated creator (already permission-checked
     *                      by the controller)
     * @param actorIp       caller IP for audit
     */
    public CreateInviteResponse createInvite(Long linkId,
                                             CreateInviteRequest request,
                                             User createdByUser,
                                             String actorIp) {

        FamilyMemberLink link = linkRepository.findById(linkId)
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Care-circle link not found"));

        // Only links that are currently usable should spawn invites.
        if (link.getStatus() == FamilyMemberLink.LinkStatus.REVOKED
                || link.getStatus() == FamilyMemberLink.LinkStatus.EXPIRED) {
            throw new AppException(HttpStatus.CONFLICT,
                    "Cannot create an invite for a " + link.getStatus() + " link");
        }

        // One active token per link — prevents ambiguous duplicate invites.
        if (tokenRepository.existsActivePendingToken(linkId, LocalDateTime.now())) {
            throw new AppException(HttpStatus.CONFLICT,
                    "An active invite already exists for this link. Revoke it before creating a new one.");
        }

        int ttl = resolveTtl(request != null ? request.ttlHours() : null);
        String rawToken = generateRawToken();
        String lookup = rawToken.substring(0, LOOKUP_LENGTH);

        InviteToken token = new InviteToken();
        token.setTokenLookup(lookup);
        token.setTokenHash(tokenHashService.hashToken(rawToken));
        token.setLinkId(linkId);
        token.setLinkType(link.getLinkType());
        token.setStatus(InviteToken.Status.PENDING);
        token.setInvitedEmail(request != null ? request.invitedEmail() : null);
        token.setInviteReason(request != null ? request.inviteReason() : null);
        token.setCreatedByUserId(createdByUser.getId());
        token.setExpiresAt(LocalDateTime.now().plusHours(ttl));

        try {
            // saveAndFlush forces the INSERT now so a unique-index violation
            // (idx_invite_token_one_pending_per_link) surfaces here and can be
            // mapped to 409, rather than leaking as a 500 at commit time.
            token = tokenRepository.saveAndFlush(token);
        } catch (org.springframework.dao.DataIntegrityViolationException e) {
            // A concurrent create inserted a PENDING token for this link first.
            throw new AppException(HttpStatus.CONFLICT,
                    "An active invite already exists for this link. Revoke it before creating a new one.");
        }

        auditService.record(token.getId(), InviteTokenAudit.EVENT_CREATED, createdByUser.getId(), actorIp,
                "linkId=" + linkId + ", ttlHours=" + ttl
                        + ", invitedEmail=" + (token.getInvitedEmail() != null ? token.getInvitedEmail() : "none"));

        log.info("Invite token created: tokenId={}, linkId={}, createdBy={}",
                token.getId(), linkId, createdByUser.getId());

        return new CreateInviteResponse(
                token.getId(),
                rawToken,
                buildInviteUrl(rawToken),
                linkId,
                link.getLinkType().name(),
                token.getStatus().name(),
                token.getExpiresAt(),
                token.getCreatedAt()
        );
    }

    // =====================================================================
    // PREVIEW  — GET /invite/{token}
    // =====================================================================

    /**
     * Sanitised preview of an invite for a pre-registration user. Returns the
     * link type, status, and expiration metadata. Expired/revoked/accepted/
     * unknown tokens are rejected with clear {@link AppException} errors.
     *
     * (Issue #59 layers richer "Who Invited Me?" context and non-enumerating
     * behaviour on top of this method.)
     */
    @Transactional(readOnly = true)
    public InvitePreviewResponse previewInvite(String rawToken, String actorIp) {
        // persistExpiry=false: this runs in a read-only tx, so we must NOT write.
        InviteToken token = resolveUsableToken(rawToken, false);

        FamilyMemberLink link = linkRepository.findById(token.getLinkId())
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Care-circle link not found"));

        String inviterName = displayNameForUserId(token.getCreatedByUserId());
        String patientName = link.getPatientUser() != null
                ? patientDisplayName(link.getPatientUser())
                : "the patient";

        auditService.recordInNewTransaction(token.getId(), InviteTokenAudit.EVENT_VIEWED, null, actorIp, "preview");

        return new InvitePreviewResponse(
                token.getLinkId(),
                token.getLinkType().name(),
                token.getStatus().name(),
                inviterName,
                patientName,
                token.getInviteReason(),
                token.getInvitedEmail(),
                token.getExpiresAt()
        );
    }

    // =====================================================================
    // ACCEPT  — POST /invite/{token}/accept
    // =====================================================================

    /**
     * Redeem an invite. The link is scoped by the token itself (not a path
     * variable), so a token for link A can never be redeemed against link B.
     *
     * @param acceptingUser the authenticated redeemer
     */
    public AcceptInviteResponse acceptInvite(String rawToken, User acceptingUser, String actorIp) {
        // persistExpiry=true: accept runs in a read-write tx, so lazily
        // flipping an expired token to EXPIRED is safe and useful here.
        InviteToken token = resolveUsableToken(rawToken, true);

        // If the invite named an email, the redeemer must match it.
        if (token.getInvitedEmail() != null && !token.getInvitedEmail().isBlank()) {
            if (acceptingUser.getEmail() == null
                    || !token.getInvitedEmail().equalsIgnoreCase(acceptingUser.getEmail())) {
                auditService.record(token.getId(), "ACCEPT_DENIED", acceptingUser.getId(), actorIp, "email mismatch");
                throw new AppException(HttpStatus.FORBIDDEN,
                        "This invite was issued to a different email address.");
            }
        }

        FamilyMemberLink link = linkRepository.findById(token.getLinkId())
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Care-circle link not found"));

        token.setStatus(InviteToken.Status.ACCEPTED);
        token.setAcceptedByUserId(acceptingUser.getId());
        token.setAcceptedAt(LocalDateTime.now());
        try {
            // saveAndFlush forces the UPDATE now so an optimistic-lock conflict
            // surfaces here (not later at commit) and can be mapped to 409.
            tokenRepository.saveAndFlush(token);
        } catch (org.springframework.orm.ObjectOptimisticLockingFailureException e) {
            // A concurrent request accepted this same token first. Treat the
            // loser of the race exactly like an already-accepted invite.
            throw new AppException(HttpStatus.CONFLICT, "This invite has already been accepted.");
        }

        auditService.record(token.getId(), InviteTokenAudit.EVENT_ACCEPTED, acceptingUser.getId(), actorIp,
                "linkId=" + token.getLinkId());

        log.info("Invite accepted: tokenId={}, linkId={}, acceptedBy={}",
                token.getId(), token.getLinkId(), acceptingUser.getId());

        String patientName = link.getPatientUser() != null
                ? patientDisplayName(link.getPatientUser())
                : "the patient";

        return new AcceptInviteResponse(
                token.getLinkId(),
                token.getLinkType().name(),
                link.getPatientUser() != null ? link.getPatientUser().getId() : null,
                patientName,
                "Invite accepted. You are now connected to this care circle."
        );
    }

    // =====================================================================
    // REVOKE  — DELETE /care-circle/{linkId}/invite/{tokenId}
    // =====================================================================

    /** Idempotent: revoking an already-terminal token is a no-op. */
    public void revokeInvite(Long linkId, Long tokenId, RevokeInviteRequest request,
                             User revokingUser, String actorIp) {

        InviteToken token = tokenRepository.findById(tokenId)
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Invite token not found"));

        // Cross-link guard: the token must belong to the link in the path.
        if (!token.getLinkId().equals(linkId)) {
            throw new AppException(HttpStatus.FORBIDDEN,
                    "Token " + tokenId + " does not belong to link " + linkId);
        }

        if (token.getStatus() != InviteToken.Status.PENDING) {
            log.info("Revoke no-op: token {} already in status {}", tokenId, token.getStatus());
            return;
        }

        String reason = request != null ? request.reason() : null;
        token.setStatus(InviteToken.Status.REVOKED);
        token.setRevokedByUserId(revokingUser.getId());
        token.setRevokedAt(LocalDateTime.now());
        token.setRevokeReason(reason);
        tokenRepository.save(token);

        auditService.record(token.getId(), InviteTokenAudit.EVENT_REVOKED, revokingUser.getId(), actorIp,
                "reason=" + (reason != null ? reason : "none"));

        log.info("Invite revoked: tokenId={}, linkId={}, revokedBy={}",
                tokenId, linkId, revokingUser.getId());
    }

    // =====================================================================
    // EXPIRY SWEEP — scheduled
    // =====================================================================

    @Scheduled(fixedDelayString = "${careconnect.invite.sweep-interval-ms:900000}")
    @Transactional
    public void expireOverdueTokens() {
        int expired = tokenRepository.expireOverdueTokens(LocalDateTime.now());
        if (expired > 0) {
            log.info("Invite expiry sweep marked {} token(s) EXPIRED", expired);
        }
    }

    // =====================================================================
    // Helpers
    // =====================================================================

    /**
     * Resolve and validate a raw token to a usable entity, throwing deterministic
     * {@link AppException}s for each terminal/invalid state (issue #53: "Expired
     * or revoked links are rejected with clear API errors").
     *
     * @param persistExpiry when true, a PENDING-but-past-TTL token is lazily
     *                      flipped to EXPIRED and saved. Callers running in a
     *                      READ-ONLY transaction (e.g. previewInvite) MUST pass
     *                      false: writing inside a read-only tx fails on
     *                      PostgreSQL and would turn the intended 410 into a 500.
     *                      The scheduled sweep will mark such tokens EXPIRED.
     */
    private InviteToken resolveUsableToken(String rawToken, boolean persistExpiry) {
        if (rawToken == null || rawToken.length() < LOOKUP_LENGTH) {
            throw new AppException(HttpStatus.NOT_FOUND, "Invite token not found");
        }
        String lookup = rawToken.substring(0, LOOKUP_LENGTH);

        InviteToken token = tokenRepository.findByTokenLookup(lookup)
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Invite token not found"));

        // Constant-cost hash verification — guards against prefix collisions/guessing.
        if (!tokenHashService.verifyToken(rawToken, token.getTokenHash())) {
            throw new AppException(HttpStatus.NOT_FOUND, "Invite token not found");
        }

        switch (token.getStatus()) {
            case ACCEPTED -> throw new AppException(HttpStatus.CONFLICT,
                    "This invite has already been accepted.");
            case REVOKED -> throw new AppException(HttpStatus.GONE,
                    "This invite has been revoked.");
            case EXPIRED -> throw new AppException(HttpStatus.GONE,
                    "This invite has expired.");
            case PENDING -> {
                if (token.isExpired()) {
                    // Only persist the flip from a read-write caller. In a
                    // read-only tx (preview) we skip the write and let the
                    // scheduled sweep reconcile the status later.
                    if (persistExpiry) {
                        token.setStatus(InviteToken.Status.EXPIRED);
                        tokenRepository.save(token);
                    }
                    throw new AppException(HttpStatus.GONE, "This invite has expired.");
                }
            }
        }
        return token;
    }

    private int resolveTtl(Integer requested) {
        if (requested == null || requested <= 0) return defaultTtlHours;
        return Math.min(requested, maxTtlHours);
    }

    private String generateRawToken() {
        byte[] bytes = new byte[32]; // 256 bits
        RANDOM.nextBytes(bytes);
        return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
    }

    private String buildInviteUrl(String rawToken) {
        return inviteBaseUrl + "/" + rawToken;
    }

    private String displayNameForUserId(Long userId) {
        if (userId == null) return "A CareConnect user";
        return userRepository.findById(userId)
                .map(u -> u.getName() != null && !u.getName().isBlank() ? u.getName() : u.getEmail())
                .orElse("A CareConnect user");
    }

    private String patientDisplayName(User patientUser) {
        Optional<Patient> patient = patientRepository.findByUser(patientUser);
        return patient.map(p -> p.getFirstName() + " " + p.getLastName())
                .orElse(patientUser.getEmail());
    }
}
