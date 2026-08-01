package com.careconnect.service;

import com.careconnect.dto.*;
import com.careconnect.exception.AppException;
import com.careconnect.model.FamilyMemberLink;
import com.careconnect.model.InviteToken;
import com.careconnect.model.User;
import com.careconnect.repository.*;
import com.careconnect.security.Role;
import com.careconnect.security.TokenHashService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.*;
import org.springframework.http.HttpStatus;
import org.springframework.test.util.ReflectionTestUtils;

import java.time.LocalDateTime;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

/**
 * Unit tests for {@link InviteTokenService}.
 */
class InviteTokenServiceTest {

    @Mock private InviteTokenRepository tokenRepository;
    @Mock private InviteAuditService auditService;
    @Mock private FamilyMemberLinkRepository linkRepository;
    @Mock private UserRepository userRepository;
    @Mock private PatientRepository patientRepository;
    @Mock private TokenHashService tokenHashService;

    private InviteTokenService service;

    private User creator;
    private User patientUser;
    private FamilyMemberLink link;

    @BeforeEach
    void setUp() {
        MockitoAnnotations.openMocks(this);

        service = new InviteTokenService(
                tokenRepository, auditService, linkRepository,
                userRepository, patientRepository, tokenHashService);

        ReflectionTestUtils.setField(service, "inviteBaseUrl", "https://app.careconnect.io/invite");
        ReflectionTestUtils.setField(service, "defaultTtlHours", 72);
        ReflectionTestUtils.setField(service, "maxTtlHours", 168);

        creator = new User();
        creator.setId(10L);
        creator.setEmail("creator@test.com");
        creator.setRole(Role.PATIENT);

        patientUser = new User();
        patientUser.setId(99L);
        patientUser.setEmail("patient@test.com");
        patientUser.setRole(Role.PATIENT);

        link = new FamilyMemberLink();
        link.setId(5L);
        link.setPatientUser(patientUser);
        link.setGrantedBy(creator); // <--- FIX: Ensures creator passes canManageLink check
        link.setStatus(FamilyMemberLink.LinkStatus.ACTIVE);
        link.setLinkType(FamilyMemberLink.LinkType.PERMANENT);
    }

    private InviteToken pendingToken() {
        InviteToken t = new InviteToken();
        t.setId(1L);
        t.setTokenLookup("abcdef0123456789");
        t.setTokenHash("hashed");
        t.setLinkId(5L);
        t.setLinkType(FamilyMemberLink.LinkType.PERMANENT);
        t.setStatus(InviteToken.Status.PENDING);
        t.setCreatedByUserId(10L);
        t.setExpiresAt(LocalDateTime.now().plusHours(48));
        t.setCreatedAt(LocalDateTime.now());
        return t;
    }

    // ---------------------------------------------------------------- create

    @Test
    @DisplayName("createInvite: happy path returns raw token + share URL")
    void createInvite_happyPath() {
        when(linkRepository.findById(5L)).thenReturn(Optional.of(link));
        when(tokenRepository.findActivePendingToken(eq(5L), any())).thenReturn(Optional.empty());
        when(tokenHashService.hashToken(anyString())).thenReturn("hashed");
        when(tokenRepository.saveAndFlush(any(InviteToken.class))).thenAnswer(inv -> {
            InviteToken t = inv.getArgument(0);
            t.setId(42L);
            t.setCreatedAt(LocalDateTime.now());
            return t;
        });

        CreateInviteRequest req = new CreateInviteRequest("bob@test.com", "Please join", 48);
        CreateInviteResponse resp = service.createInvite(5L, req, creator, "1.2.3.4");

        assertEquals(5L, resp.linkId());
        assertEquals("PERMANENT", resp.linkType());
        assertEquals("PENDING", resp.status());
        assertNotNull(resp.token());
        assertTrue(resp.inviteUrl().startsWith("https://app.careconnect.io/invite/"));
        verify(auditService).record(anyLong(), eq("CREATED"), any(), any(), any());
    }

    @Test
    @DisplayName("createInvite: link not found -> 404")
    void createInvite_linkNotFound() {
        when(linkRepository.findById(5L)).thenReturn(Optional.empty());

        AppException ex = assertThrows(AppException.class,
                () -> service.createInvite(5L, null, creator, "1.2.3.4"));
        assertEquals(HttpStatus.NOT_FOUND, ex.getStatus());
    }

    @Test
    @DisplayName("createInvite: active token exists -> automatically rotates prior token")
    void createInvite_conflictActiveToken() {
        when(linkRepository.findById(5L)).thenReturn(Optional.of(link));
        InviteToken existing = pendingToken();
        when(tokenRepository.findActivePendingToken(eq(5L), any())).thenReturn(Optional.of(existing));
        when(tokenHashService.hashToken(anyString())).thenReturn("hashed");
        when(tokenRepository.saveAndFlush(any(InviteToken.class))).thenAnswer(inv -> {
            InviteToken t = inv.getArgument(0);
            t.setId(42L);
            t.setCreatedAt(LocalDateTime.now());
            return t;
        });

        CreateInviteResponse resp = service.createInvite(5L, null, creator, "1.2.3.4");

        assertNotNull(resp);
        assertEquals(InviteToken.Status.REVOKED, existing.getStatus());
        verify(tokenRepository).save(existing);
        verify(auditService).record(eq(1L), eq("REVOKED"), any(), any(), any());
    }

    @Test
    @DisplayName("createInvite: revoked link -> 409")
    void createInvite_revokedLink() {
        link.setStatus(FamilyMemberLink.LinkStatus.REVOKED);
        when(linkRepository.findById(5L)).thenReturn(Optional.of(link));

        AppException ex = assertThrows(AppException.class,
                () -> service.createInvite(5L, null, creator, "1.2.3.4"));
        assertEquals(HttpStatus.CONFLICT, ex.getStatus());
    }

    @Test
    @DisplayName("createInvite: TTL capped at max")
    void createInvite_ttlCapped() {
        when(linkRepository.findById(5L)).thenReturn(Optional.of(link));
        when(tokenRepository.findActivePendingToken(eq(5L), any())).thenReturn(Optional.empty());
        when(tokenHashService.hashToken(anyString())).thenReturn("hashed");
        ArgumentCaptor<InviteToken> captor = ArgumentCaptor.forClass(InviteToken.class);
        when(tokenRepository.saveAndFlush(captor.capture())).thenAnswer(inv -> {
            InviteToken t = inv.getArgument(0); t.setId(1L); t.setCreatedAt(LocalDateTime.now()); return t;
        });

        service.createInvite(5L, new CreateInviteRequest(null, null, 9999), creator, "1.2.3.4");

        LocalDateTime expires = captor.getValue().getExpiresAt();
        assertTrue(expires.isBefore(LocalDateTime.now().plusHours(169)));
    }

    @Test
    @DisplayName("createInvite: concurrent duplicate PENDING -> 409 via unique index")
    void createInvite_duplicatePendingConflict() {
        when(linkRepository.findById(5L)).thenReturn(Optional.of(link));
        when(tokenRepository.findActivePendingToken(eq(5L), any())).thenReturn(Optional.empty());
        when(tokenHashService.hashToken(anyString())).thenReturn("hashed");
        when(tokenRepository.saveAndFlush(any(InviteToken.class)))
                .thenThrow(new org.springframework.dao.DataIntegrityViolationException(
                        "duplicate key value violates unique constraint "
                                + "\"idx_invite_token_one_pending_per_link\""));

        AppException ex = assertThrows(AppException.class,
                () -> service.createInvite(5L, null, creator, "1.2.3.4"));
        assertEquals(HttpStatus.CONFLICT, ex.getStatus());
    }

    // --------------------------------------------------------------- preview

    @Test
    @DisplayName("previewInvite: valid token returns context + ACCEPT action")
    void previewInvite_happyPath() {
        InviteToken token = pendingToken();
        token.setInviteReason("Join my care circle");
        when(tokenRepository.findByTokenLookup("abcdef0123456789")).thenReturn(Optional.of(token));
        when(tokenHashService.verifyToken(anyString(), eq("hashed"))).thenReturn(true);
        when(linkRepository.findById(5L)).thenReturn(Optional.of(link));
        when(userRepository.findById(10L)).thenReturn(Optional.of(creator));
        when(patientRepository.findByUser(patientUser)).thenReturn(Optional.empty());

        InvitePreviewResponse resp = service.previewInvite("abcdef0123456789ZZZ", "1.2.3.4");

        assertTrue(resp.valid());
        assertEquals("VALID", resp.status());
        assertEquals("ACCEPT", resp.nextAction());
        assertEquals(5L, resp.linkId());
        assertEquals("Join my care circle", resp.inviteReason());
    }

    @Test
    @DisplayName("previewInvite: email-scoped valid token -> SIGN_IN next action")
    void previewInvite_emailScopedRequiresSignIn() {
        InviteToken token = pendingToken();
        token.setInvitedEmail("bob@test.com");
        when(tokenRepository.findByTokenLookup("abcdef0123456789")).thenReturn(Optional.of(token));
        when(tokenHashService.verifyToken(anyString(), anyString())).thenReturn(true);
        when(linkRepository.findById(5L)).thenReturn(Optional.of(link));
        when(userRepository.findById(10L)).thenReturn(Optional.of(creator));
        when(patientRepository.findByUser(patientUser)).thenReturn(Optional.empty());

        InvitePreviewResponse resp = service.previewInvite("abcdef0123456789ZZZ", "1.2.3.4");

        assertTrue(resp.valid());
        assertEquals("SIGN_IN", resp.nextAction());
    }

    @Test
    @DisplayName("previewInvite: unknown lookup -> non-enumerating INVALID (no throw, no context)")
    void previewInvite_unknownIsInvalid() {
        when(tokenRepository.findByTokenLookup(anyString())).thenReturn(Optional.empty());

        InvitePreviewResponse resp = service.previewInvite("abcdef0123456789XYZ", "1.2.3.4");

        assertFalse(resp.valid());
        assertEquals("INVALID", resp.status());
        assertNull(resp.linkId());
        assertNull(resp.inviterName());
    }

    @Test
    @DisplayName("previewInvite: hash mismatch is indistinguishable from unknown (INVALID)")
    void previewInvite_hashMismatchIsInvalid() {
        when(tokenRepository.findByTokenLookup("abcdef0123456789")).thenReturn(Optional.of(pendingToken()));
        when(tokenHashService.verifyToken(anyString(), anyString())).thenReturn(false);

        InvitePreviewResponse resp = service.previewInvite("abcdef0123456789BAD", "1.2.3.4");

        assertFalse(resp.valid());
        assertEquals("INVALID", resp.status());
    }

    @Test
    @DisplayName("previewInvite: revoked token -> REVOKED status, REQUEST_NEW, no context")
    void previewInvite_revoked() {
        InviteToken token = pendingToken();
        token.setStatus(InviteToken.Status.REVOKED);
        when(tokenRepository.findByTokenLookup("abcdef0123456789")).thenReturn(Optional.of(token));
        when(tokenHashService.verifyToken(anyString(), anyString())).thenReturn(true);

        InvitePreviewResponse resp = service.previewInvite("abcdef0123456789RVK", "1.2.3.4");

        assertFalse(resp.valid());
        assertEquals("REVOKED", resp.status());
        assertEquals("REQUEST_NEW", resp.nextAction());
        assertNull(resp.inviterName());
    }

    @Test
    @DisplayName("previewInvite: already accepted -> ACCEPTED status, SIGN_IN")
    void previewInvite_accepted() {
        InviteToken token = pendingToken();
        token.setStatus(InviteToken.Status.ACCEPTED);
        when(tokenRepository.findByTokenLookup("abcdef0123456789")).thenReturn(Optional.of(token));
        when(tokenHashService.verifyToken(anyString(), anyString())).thenReturn(true);

        InvitePreviewResponse resp = service.previewInvite("abcdef0123456789ACC", "1.2.3.4");

        assertFalse(resp.valid());
        assertEquals("ACCEPTED", resp.status());
        assertEquals("SIGN_IN", resp.nextAction());
    }

    @Test
    @DisplayName("previewInvite: pending past TTL -> EXPIRED status, no write (read-only safe)")
    void previewInvite_expiredDoesNotWrite() {
        InviteToken token = pendingToken();
        token.setExpiresAt(LocalDateTime.now().minusHours(1));
        when(tokenRepository.findByTokenLookup("abcdef0123456789")).thenReturn(Optional.of(token));
        when(tokenHashService.verifyToken(anyString(), anyString())).thenReturn(true);

        InvitePreviewResponse resp = service.previewInvite("abcdef0123456789EXP", "1.2.3.4");

        assertFalse(resp.valid());
        assertEquals("EXPIRED", resp.status());
        assertEquals("REQUEST_NEW", resp.nextAction());
        verify(tokenRepository, never()).save(any());
        verify(tokenRepository, never()).saveAndFlush(any());
    }

    @Test
    @DisplayName("acceptInvite: pending past TTL -> 410 AND lazily persists EXPIRED")
    void acceptInvite_expiredPersists() {
        InviteToken token = pendingToken();
        token.setExpiresAt(LocalDateTime.now().minusHours(1));
        when(tokenRepository.findByTokenLookup("abcdef0123456789")).thenReturn(Optional.of(token));
        when(tokenHashService.verifyToken(anyString(), anyString())).thenReturn(true);
        when(tokenRepository.save(any())).thenAnswer(inv -> inv.getArgument(0));

        User redeemer = new User();
        redeemer.setId(77L);
        redeemer.setEmail("redeemer@test.com");

        AppException ex = assertThrows(AppException.class,
                () -> service.acceptInvite("abcdef0123456789EXP", redeemer, "1.2.3.4"));
        assertEquals(HttpStatus.GONE, ex.getStatus());
        verify(tokenRepository).save(argThat(t -> t.getStatus() == InviteToken.Status.EXPIRED));
    }

    // ---------------------------------------------------------------- accept

    @Test
    @DisplayName("acceptInvite: open invite accepted by any authenticated user")
    void acceptInvite_happyPath() {
        InviteToken token = pendingToken();
        when(tokenRepository.findByTokenLookup("abcdef0123456789")).thenReturn(Optional.of(token));
        when(tokenHashService.verifyToken(anyString(), anyString())).thenReturn(true);
        when(linkRepository.findById(5L)).thenReturn(Optional.of(link));
        when(patientRepository.findByUser(patientUser)).thenReturn(Optional.empty());
        when(tokenRepository.saveAndFlush(any())).thenAnswer(inv -> inv.getArgument(0));

        User redeemer = new User();
        redeemer.setId(77L);
        redeemer.setEmail("redeemer@test.com");

        AcceptInviteResponse resp = service.acceptInvite("abcdef0123456789ABC", redeemer, "1.2.3.4");

        assertEquals(5L, resp.linkId());
        assertEquals(99L, resp.patientUserId());
        verify(tokenRepository).saveAndFlush(argThat(t ->
                t.getStatus() == InviteToken.Status.ACCEPTED && t.getAcceptedByUserId().equals(77L)));
        verify(auditService).record(anyLong(), eq("ACCEPTED"), any(), any(), any());
    }

    @Test
    @DisplayName("acceptInvite: concurrent double-accept -> loser gets 409 (optimistic lock)")
    void acceptInvite_optimisticLockConflict() {
        InviteToken token = pendingToken();
        when(tokenRepository.findByTokenLookup("abcdef0123456789")).thenReturn(Optional.of(token));
        when(tokenHashService.verifyToken(anyString(), anyString())).thenReturn(true);
        when(linkRepository.findById(5L)).thenReturn(Optional.of(link));
        when(tokenRepository.saveAndFlush(any()))
                .thenThrow(new org.springframework.orm.ObjectOptimisticLockingFailureException(
                        InviteToken.class, 1L));

        User redeemer = new User();
        redeemer.setId(88L);
        redeemer.setEmail("redeemer2@test.com");

        AppException ex = assertThrows(AppException.class,
                () -> service.acceptInvite("abcdef0123456789ABC", redeemer, "1.2.3.4"));
        assertEquals(HttpStatus.CONFLICT, ex.getStatus());
    }

    @Test
    @DisplayName("acceptInvite: email-scoped invite rejects mismatched user -> 403")
    void acceptInvite_emailMismatch() {
        InviteToken token = pendingToken();
        token.setInvitedEmail("intended@test.com");
        when(tokenRepository.findByTokenLookup("abcdef0123456789")).thenReturn(Optional.of(token));
        when(tokenHashService.verifyToken(anyString(), anyString())).thenReturn(true);

        User wrong = new User();
        wrong.setId(77L);
        wrong.setEmail("someone-else@test.com");

        AppException ex = assertThrows(AppException.class,
                () -> service.acceptInvite("abcdef0123456789ABC", wrong, "1.2.3.4"));
        assertEquals(HttpStatus.FORBIDDEN, ex.getStatus());
        verify(tokenRepository, never()).save(argThat(t -> t.getStatus() == InviteToken.Status.ACCEPTED));
    }

    @Test
    @DisplayName("acceptInvite: already accepted -> 409")
    void acceptInvite_alreadyAccepted() {
        InviteToken token = pendingToken();
        token.setStatus(InviteToken.Status.ACCEPTED);
        when(tokenRepository.findByTokenLookup("abcdef0123456789")).thenReturn(Optional.of(token));
        when(tokenHashService.verifyToken(anyString(), anyString())).thenReturn(true);

        User redeemer = new User();
        redeemer.setId(77L);
        redeemer.setEmail("redeemer@test.com");

        AppException ex = assertThrows(AppException.class,
                () -> service.acceptInvite("abcdef0123456789ABC", redeemer, "1.2.3.4"));
        assertEquals(HttpStatus.CONFLICT, ex.getStatus());
    }

    // ---------------------------------------------------------------- revoke

    @Test
    @DisplayName("revokeInvite: pending token revoked with reason")
    void revokeInvite_happyPath() {
        InviteToken token = pendingToken();
        when(tokenRepository.findById(1L)).thenReturn(Optional.of(token));
        when(linkRepository.findById(5L)).thenReturn(Optional.of(link)); // <--- FIX: Mocked link lookup
        when(tokenRepository.save(any())).thenAnswer(inv -> inv.getArgument(0));

        service.revokeInvite(5L, 1L, new RevokeInviteRequest("Sent to wrong person"), creator, "1.2.3.4");

        verify(tokenRepository).save(argThat(t ->
                t.getStatus() == InviteToken.Status.REVOKED
                        && "Sent to wrong person".equals(t.getRevokeReason())));
        verify(auditService).record(anyLong(), eq("REVOKED"), any(), any(), any());
    }

    @Test
    @DisplayName("revokeInvite: cross-link token rejected -> 403")
    void revokeInvite_crossLink() {
        InviteToken token = pendingToken();
        token.setLinkId(999L);
        when(tokenRepository.findById(1L)).thenReturn(Optional.of(token));

        AppException ex = assertThrows(AppException.class,
                () -> service.revokeInvite(5L, 1L, null, creator, "1.2.3.4"));
        assertEquals(HttpStatus.FORBIDDEN, ex.getStatus());
    }

    @Test
    @DisplayName("revokeInvite: already revoked is idempotent no-op")
    void revokeInvite_idempotent() {
        InviteToken token = pendingToken();
        token.setStatus(InviteToken.Status.REVOKED);
        when(tokenRepository.findById(1L)).thenReturn(Optional.of(token));
        when(linkRepository.findById(5L)).thenReturn(Optional.of(link)); // <--- FIX: Mocked link lookup

        assertDoesNotThrow(() -> service.revokeInvite(5L, 1L, null, creator, "1.2.3.4"));
        verify(tokenRepository, never()).save(any());
    }

    // ----------------------------------------------------------------- sweep

    @Test
    @DisplayName("expireOverdueTokens: delegates to bulk update")
    void expireSweep() {
        when(tokenRepository.expireOverdueTokens(any())).thenReturn(3);
        assertDoesNotThrow(() -> service.expireOverdueTokens());
        verify(tokenRepository).expireOverdueTokens(any());
    }
}