package com.careconnect.service;

import com.careconnect.dto.CreateProfileShareRequest;
import com.careconnect.dto.CreateProfileShareResponse;
import com.careconnect.dto.PublicProfileShareDto;
import com.careconnect.exception.AppException;
import com.careconnect.model.Patient;
import com.careconnect.model.ProfileShareToken;
import com.careconnect.model.User;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.ProfileShareTokenRepository;
import com.careconnect.security.Role;
import com.careconnect.security.TokenHashService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.Mock;
import org.mockito.MockitoAnnotations;
import org.springframework.http.HttpStatus;
import org.springframework.test.util.ReflectionTestUtils;

import java.time.LocalDateTime;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

class ProfileShareTokenServiceTest {

    @Mock private ProfileShareTokenRepository tokenRepository;
    @Mock private PatientRepository patientRepository;
    @Mock private TokenHashService tokenHashService;

    private ProfileShareTokenService service;

    private User patientUser;
    private Patient patient;

    @BeforeEach
    void setUp() {
        MockitoAnnotations.openMocks(this);
        service = new ProfileShareTokenService(tokenRepository, patientRepository, tokenHashService);
        ReflectionTestUtils.setField(service, "shareBaseUrl", "https://app.careconnect.io/p");
        ReflectionTestUtils.setField(service, "defaultTtlHours", 168);
        ReflectionTestUtils.setField(service, "maxTtlHours", 720);

        patientUser = new User();
        patientUser.setId(99L);
        patientUser.setEmail("patient@test.com");
        patientUser.setRole(Role.PATIENT);

        patient = new Patient();
        patient.setId(7L);
        patient.setFirstName("Ada");
        patient.setLastName("Lovelace");
        patient.setPreferredCommunicationMethod("verbal");
        patient.setUser(patientUser);
    }

    private ProfileShareToken activeToken(String rawPrefix) {
        ProfileShareToken t = new ProfileShareToken();
        t.setId(1L);
        t.setTokenLookup(rawPrefix.substring(0, 16));
        t.setTokenHash("hashed");
        t.setPatientUserId(99L);
        t.setPatientId(7L);
        t.setStatus(ProfileShareToken.Status.ACTIVE);
        t.setCreatedByUserId(99L);
        t.setExpiresAt(LocalDateTime.now().plusHours(48));
        t.setCreatedAt(LocalDateTime.now());
        return t;
    }

    @Test
    @DisplayName("create: happy path returns opaque token + share URL without patient id")
    void create_happyPath() {
        when(patientRepository.findByUser(patientUser)).thenReturn(Optional.of(patient));
        when(tokenRepository.existsActiveToken(eq(99L), any())).thenReturn(false);
        when(tokenHashService.hashToken(anyString())).thenReturn("hashed");
        when(tokenRepository.saveAndFlush(any(ProfileShareToken.class))).thenAnswer(inv -> {
            ProfileShareToken t = inv.getArgument(0);
            t.setId(42L);
            t.setCreatedAt(LocalDateTime.now());
            return t;
        });

        CreateProfileShareResponse resp = service.create(new CreateProfileShareRequest(48), patientUser);

        assertEquals(42L, resp.tokenId());
        assertEquals("ACTIVE", resp.status());
        assertNotNull(resp.token());
        assertTrue(resp.shareUrl().startsWith("https://app.careconnect.io/p/"));
        assertEquals("https://app.careconnect.io/p/" + resp.token(), resp.shareUrl());
        assertFalse(resp.shareUrl().contains("/patients/"));
        verify(tokenHashService).hashToken(resp.token());
    }

    @Test
    @DisplayName("create: active token exists -> 409")
    void create_conflict() {
        when(patientRepository.findByUser(patientUser)).thenReturn(Optional.of(patient));
        when(tokenRepository.existsActiveToken(eq(99L), any())).thenReturn(true);

        AppException ex = assertThrows(AppException.class,
                () -> service.create(null, patientUser));
        assertEquals(HttpStatus.CONFLICT, ex.getStatus());
        verify(tokenRepository, never()).saveAndFlush(any());
    }

    @Test
    @DisplayName("create: caregiver role -> 403")
    void create_forbiddenForCaregiver() {
        User caregiver = new User();
        caregiver.setId(5L);
        caregiver.setRole(Role.CAREGIVER);

        AppException ex = assertThrows(AppException.class,
                () -> service.create(null, caregiver));
        assertEquals(HttpStatus.FORBIDDEN, ex.getStatus());
    }

    @Test
    @DisplayName("create: TTL capped at max")
    void create_ttlCapped() {
        when(patientRepository.findByUser(patientUser)).thenReturn(Optional.of(patient));
        when(tokenRepository.existsActiveToken(eq(99L), any())).thenReturn(false);
        when(tokenHashService.hashToken(anyString())).thenReturn("hashed");
        when(tokenRepository.saveAndFlush(any(ProfileShareToken.class))).thenAnswer(inv -> {
            ProfileShareToken t = inv.getArgument(0);
            t.setId(1L);
            t.setCreatedAt(LocalDateTime.now());
            return t;
        });

        CreateProfileShareResponse resp = service.create(new CreateProfileShareRequest(9999), patientUser);
        assertTrue(resp.expiresAt().isBefore(LocalDateTime.now().plusHours(721)));
        assertTrue(resp.expiresAt().isAfter(LocalDateTime.now().plusHours(719)));
    }

    @Test
    @DisplayName("revoke: marks ACTIVE token REVOKED")
    void revoke_happyPath() {
        ProfileShareToken token = activeToken("abcdef0123456789xxxx");
        when(tokenRepository.findById(1L)).thenReturn(Optional.of(token));
        when(patientRepository.findByUser(patientUser)).thenReturn(Optional.of(patient));

        service.revoke(1L, null, patientUser);

        assertEquals(ProfileShareToken.Status.REVOKED, token.getStatus());
        assertEquals(99L, token.getRevokedByUserId());
        verify(tokenRepository).save(token);
    }

    @Test
    @DisplayName("revoke: already revoked is idempotent")
    void revoke_idempotent() {
        ProfileShareToken token = activeToken("abcdef0123456789xxxx");
        token.setStatus(ProfileShareToken.Status.REVOKED);
        when(tokenRepository.findById(1L)).thenReturn(Optional.of(token));
        when(patientRepository.findByUser(patientUser)).thenReturn(Optional.of(patient));

        service.revoke(1L, null, patientUser);
        verify(tokenRepository, never()).save(any());
    }

    @Test
    @DisplayName("resolve: valid token returns limited public DTO")
    void resolve_valid() {
        String raw = "abcdef0123456789ABCDEFGHIJKLMNOPQRSTUV";
        ProfileShareToken token = activeToken(raw);
        when(tokenRepository.findByTokenLookup(raw.substring(0, 16))).thenReturn(Optional.of(token));
        when(tokenHashService.verifyToken(raw, "hashed")).thenReturn(true);
        when(patientRepository.findById(7L)).thenReturn(Optional.of(patient));

        PublicProfileShareDto dto = service.resolve(raw);

        assertEquals("ACTIVE", dto.status());
        assertEquals("Ada", dto.firstName());
        assertEquals("Lovelace", dto.lastName());
        assertEquals("verbal", dto.preferredCommunicationMethod());
        assertNull(dto.message());
    }

    @Test
    @DisplayName("resolve: unknown token -> INVALID without leaking existence")
    void resolve_unknown() {
        when(tokenRepository.findByTokenLookup(anyString())).thenReturn(Optional.empty());

        PublicProfileShareDto dto = service.resolve("abcdef0123456789notreal");
        assertEquals("INVALID", dto.status());
        assertNull(dto.firstName());
    }

    @Test
    @DisplayName("resolve: hash mismatch -> INVALID")
    void resolve_hashMismatch() {
        String raw = "abcdef0123456789ABCDEFGHIJKLMNOPQRSTUV";
        ProfileShareToken token = activeToken(raw);
        when(tokenRepository.findByTokenLookup(raw.substring(0, 16))).thenReturn(Optional.of(token));
        when(tokenHashService.verifyToken(raw, "hashed")).thenReturn(false);

        PublicProfileShareDto dto = service.resolve(raw);
        assertEquals("INVALID", dto.status());
        verify(patientRepository, never()).findById(any());
    }

    @Test
    @DisplayName("resolve: revoked token -> REVOKED")
    void resolve_revoked() {
        String raw = "abcdef0123456789ABCDEFGHIJKLMNOPQRSTUV";
        ProfileShareToken token = activeToken(raw);
        token.setStatus(ProfileShareToken.Status.REVOKED);
        when(tokenRepository.findByTokenLookup(raw.substring(0, 16))).thenReturn(Optional.of(token));
        when(tokenHashService.verifyToken(raw, "hashed")).thenReturn(true);

        PublicProfileShareDto dto = service.resolve(raw);
        assertEquals("REVOKED", dto.status());
    }
}
