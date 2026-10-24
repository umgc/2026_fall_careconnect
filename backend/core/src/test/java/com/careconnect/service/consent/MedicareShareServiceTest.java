package com.careconnect.service.consent;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import com.careconnect.exception.AppException;
import com.careconnect.model.ConsentGrant;
import com.careconnect.model.User;
import com.careconnect.dto.MedicareSharedWithMeResponse;
import com.careconnect.model.Patient;
import com.careconnect.repository.ConsentGrantRepository;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.UserRepository;
import com.careconnect.security.Role;
import com.careconnect.service.EmailService;

import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.Optional;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;

@ExtendWith(MockitoExtension.class)
@DisplayName("MedicareShareService Tests")
class MedicareShareServiceTest {

    private static final Long PATIENT_USER_ID = 10L;
    private static final Long RECIPIENT_USER_ID = 30L;
    private static final String RECIPIENT_EMAIL = "friend@example.com";

    @Mock
    private ConsentGrantRepository consentGrantRepository;
    @Mock
    private UserRepository userRepository;
    @Mock
    private PatientRepository patientRepository;
    @Mock
    private EmailService emailService;

    private MedicareShareService service;
    private User patient;
    private User recipient;

    @BeforeEach
    void setUp() {
        service = new MedicareShareService(
                consentGrantRepository, userRepository, patientRepository, emailService);
        patient = user(PATIENT_USER_ID, Role.PATIENT, "patient@example.com", "Pat Patient");
        recipient = user(RECIPIENT_USER_ID, Role.FAMILY_MEMBER, RECIPIENT_EMAIL, "Fran Friend");
    }

    private static User user(final long id, final Role role, final String email, final String name) {
        final User user = new User();
        user.setId(id);
        user.setRole(role);
        user.setEmail(email);
        user.setName(name);
        return user;
    }

    private void recipientIsRegistered() {
        when(userRepository.findByEmail(RECIPIENT_EMAIL)).thenReturn(Optional.of(recipient));
    }

    private void saveReturnsArgumentWithId() {
        when(consentGrantRepository.save(any(ConsentGrant.class))).thenAnswer(inv -> {
            final ConsentGrant grant = inv.getArgument(0);
            grant.setId(99L);
            return grant;
        });
    }

    @Test
    @DisplayName("TC-CONSENT-047 CR-2: sharing saves a 90-day MEDICARE_VIEW grant held by a SHARE_RECIPIENT")
    void share_savesNinetyDayShareRecipientGrant() {
        recipientIsRegistered();
        saveReturnsArgumentWithId();
        final Instant before = Instant.now();

        final MedicareShareService.ShareResult result =
                service.shareMedicareRecords(patient, RECIPIENT_EMAIL);

        final ArgumentCaptor<ConsentGrant> saved = ArgumentCaptor.forClass(ConsentGrant.class);
        verify(consentGrantRepository).save(saved.capture());
        final ConsentGrant grant = saved.getValue();
        assertThat(grant.getPatientUserId()).isEqualTo(PATIENT_USER_ID);
        assertThat(grant.getGranteeUserId()).isEqualTo(RECIPIENT_USER_ID);
        assertThat(grant.getScope()).isEqualTo(ConsentGrant.SCOPE_MEDICARE_VIEW);
        assertThat(grant.getGranteeRole()).isEqualTo(ConsentGrant.GRANTEE_ROLE_SHARE_RECIPIENT);
        assertThat(grant.getStatus()).isEqualTo(ConsentGrant.STATUS_ACTIVE);
        assertThat(Duration.between(grant.getGrantedAt(), grant.getExpiresAt()))
                .isEqualTo(Duration.ofDays(90));
        assertThat(grant.getGrantedAt()).isAfterOrEqualTo(before);
        assertThat(result.grant().getId()).isEqualTo(99L);
        assertThat(result.recipient()).isSameAs(recipient);
        assertThat(result.emailSent()).isTrue();
    }

    @Test
    @DisplayName("TC-CONSENT-048 CR-2: the recipient gets a notice email naming the patient and the expiry")
    void share_sendsNoticeEmail() {
        recipientIsRegistered();
        saveReturnsArgumentWithId();

        final MedicareShareService.ShareResult result =
                service.shareMedicareRecords(patient, RECIPIENT_EMAIL);

        verify(emailService).sendMedicareShareNoticeEmail(
                RECIPIENT_EMAIL, "Fran Friend", "Pat Patient", result.grant().getExpiresAt());
    }

    @Test
    @DisplayName("TC-CONSENT-049 CR-2: a failed notice email keeps the share and reports emailSent=false")
    void share_emailFailureKeepsGrant() {
        recipientIsRegistered();
        saveReturnsArgumentWithId();
        doThrow(new RuntimeException("smtp down")).when(emailService)
                .sendMedicareShareNoticeEmail(anyString(), anyString(), anyString(), any());

        final MedicareShareService.ShareResult result =
                service.shareMedicareRecords(patient, RECIPIENT_EMAIL);

        assertThat(result.emailSent()).isFalse();
        verify(consentGrantRepository).save(any(ConsentGrant.class));
    }

    @Test
    @DisplayName("TC-CONSENT-050 CR-2: a blank email is 400 and touches nothing")
    void share_blankEmailIsBadRequest() {
        assertThatThrownBy(() -> service.shareMedicareRecords(patient, "  "))
                .isInstanceOf(AppException.class)
                .extracting(e -> ((AppException) e).getStatus())
                .isEqualTo(HttpStatus.BAD_REQUEST);
        assertThatThrownBy(() -> service.shareMedicareRecords(patient, null))
                .isInstanceOf(AppException.class);
        verifyNoInteractions(userRepository, consentGrantRepository, emailService);
    }

    @Test
    @DisplayName("TC-CONSENT-051 CR-2: an email with no registered user is 404 and saves no grant")
    void share_unknownEmailIsNotFound() {
        when(userRepository.findByEmail("nobody@example.com")).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.shareMedicareRecords(patient, "nobody@example.com"))
                .isInstanceOf(AppException.class)
                .extracting(e -> ((AppException) e).getStatus())
                .isEqualTo(HttpStatus.NOT_FOUND);
        verifyNoInteractions(consentGrantRepository, emailService);
    }

    @Test
    @DisplayName("TC-CONSENT-052 CR-2: the email is trimmed and matched case-insensitively")
    void share_matchesTrimmedLowercaseEmail() {
        when(userRepository.findByEmail("Friend@Example.com")).thenReturn(Optional.empty());
        recipientIsRegistered();
        saveReturnsArgumentWithId();

        final MedicareShareService.ShareResult result =
                service.shareMedicareRecords(patient, "  Friend@Example.com ");

        assertThat(result.recipient()).isSameAs(recipient);
    }

    @Test
    @DisplayName("TC-CONSENT-053 CR-2: sharing with yourself is 400")
    void share_withSelfIsBadRequest() {
        when(userRepository.findByEmail("patient@example.com")).thenReturn(Optional.of(patient));

        assertThatThrownBy(() -> service.shareMedicareRecords(patient, "patient@example.com"))
                .isInstanceOf(AppException.class)
                .extracting(e -> ((AppException) e).getStatus())
                .isEqualTo(HttpStatus.BAD_REQUEST);
        verifyNoInteractions(consentGrantRepository, emailService);
    }

    @Test
    @DisplayName("TC-CONSENT-054 CR-2: a recipient who already has an active grant is 409, and the grant is untouched")
    void share_existingActiveGrantIsConflict() {
        recipientIsRegistered();
        final ConsentGrant caregiverGrant = ConsentGrant.builder()
                .id(5L).patientUserId(PATIENT_USER_ID).granteeUserId(RECIPIENT_USER_ID)
                .granteeRole("CAREGIVER").scope(ConsentGrant.SCOPE_MEDICARE_VIEW)
                .status(ConsentGrant.STATUS_ACTIVE).build();
        when(consentGrantRepository.findActiveGrants(
                eq(PATIENT_USER_ID), eq(RECIPIENT_USER_ID),
                eq(ConsentGrant.SCOPE_MEDICARE_VIEW), any(Instant.class)))
                .thenReturn(List.of(caregiverGrant));

        assertThatThrownBy(() -> service.shareMedicareRecords(patient, RECIPIENT_EMAIL))
                .isInstanceOf(AppException.class)
                .extracting(e -> ((AppException) e).getStatus())
                .isEqualTo(HttpStatus.CONFLICT);
        verify(consentGrantRepository, never()).save(any(ConsentGrant.class));
        assertThat(caregiverGrant.getExpiresAt()).isNull();
        verifyNoInteractions(emailService);
    }

    @Test
    @DisplayName("TC-CONSENT-055 CR-2: a soft-expired ACTIVE row is revoked before the new share is saved")
    void share_revokesSoftExpiredRowFirst() {
        recipientIsRegistered();
        saveReturnsArgumentWithId();
        final ConsentGrant stale = ConsentGrant.builder()
                .id(7L).patientUserId(PATIENT_USER_ID).granteeUserId(RECIPIENT_USER_ID)
                .scope(ConsentGrant.SCOPE_MEDICARE_VIEW).status(ConsentGrant.STATUS_ACTIVE)
                .expiresAt(Instant.now().minusSeconds(60)).build();
        when(consentGrantRepository.findStatusActiveGrants(
                PATIENT_USER_ID, RECIPIENT_USER_ID, ConsentGrant.SCOPE_MEDICARE_VIEW))
                .thenReturn(List.of(stale));

        service.shareMedicareRecords(patient, RECIPIENT_EMAIL);

        assertThat(stale.getStatus()).isEqualTo(ConsentGrant.STATUS_REVOKED);
        assertThat(stale.getRevokedAt()).isNotNull();
        verify(consentGrantRepository).saveAll(List.of(stale));
    }

    @Test
    @DisplayName("TC-CONSENT-056 CR-2: a missing patient is rejected before any lookup")
    void share_requiresPatient() {
        assertThatThrownBy(() -> service.shareMedicareRecords(null, RECIPIENT_EMAIL))
                .isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> service.shareMedicareRecords(new User(), RECIPIENT_EMAIL))
                .isInstanceOf(IllegalArgumentException.class);
        verifyNoInteractions(userRepository, consentGrantRepository, emailService);
    }

    @Test
    @DisplayName("TC-CONSENT-057 CR-2: listing returns only SHARE_RECIPIENT grants, with the recipient")
    void list_returnsOnlyShares() {
        final ConsentGrant share = ConsentGrant.builder()
                .id(1L).patientUserId(PATIENT_USER_ID).granteeUserId(RECIPIENT_USER_ID)
                .granteeRole(ConsentGrant.GRANTEE_ROLE_SHARE_RECIPIENT)
                .scope(ConsentGrant.SCOPE_MEDICARE_VIEW).status(ConsentGrant.STATUS_ACTIVE).build();
        final ConsentGrant caregiver = ConsentGrant.builder()
                .id(2L).patientUserId(PATIENT_USER_ID).granteeUserId(20L)
                .granteeRole("CAREGIVER")
                .scope(ConsentGrant.SCOPE_MEDICARE_VIEW).status(ConsentGrant.STATUS_ACTIVE).build();
        when(consentGrantRepository.findActiveGrantsForPatient(
                eq(PATIENT_USER_ID), eq(ConsentGrant.SCOPE_MEDICARE_VIEW), any(Instant.class)))
                .thenReturn(List.of(share, caregiver));
        when(userRepository.findById(RECIPIENT_USER_ID)).thenReturn(Optional.of(recipient));

        final List<MedicareShareService.ShareResult> shares =
                service.listActiveShares(PATIENT_USER_ID);

        assertThat(shares).hasSize(1);
        assertThat(shares.get(0).grant()).isSameAs(share);
        assertThat(shares.get(0).recipient()).isSameAs(recipient);
    }

    private ConsentGrant activeShare() {
        return ConsentGrant.builder()
                .id(1L).patientUserId(PATIENT_USER_ID).granteeUserId(RECIPIENT_USER_ID)
                .granteeRole(ConsentGrant.GRANTEE_ROLE_SHARE_RECIPIENT)
                .scope(ConsentGrant.SCOPE_MEDICARE_VIEW).status(ConsentGrant.STATUS_ACTIVE).build();
    }

    @Test
    @DisplayName("TC-CONSENT-067 CR-2: revoking a share by id marks it REVOKED with a revoke time")
    void revoke_marksShareRevoked() {
        final ConsentGrant share = activeShare();
        when(consentGrantRepository.findById(1L)).thenReturn(Optional.of(share));
        when(consentGrantRepository.save(share)).thenReturn(share);
        when(userRepository.findById(RECIPIENT_USER_ID)).thenReturn(Optional.of(recipient));

        final MedicareShareService.ShareResult result = service.revokeShare(PATIENT_USER_ID, 1L);

        assertThat(share.getStatus()).isEqualTo(ConsentGrant.STATUS_REVOKED);
        assertThat(share.getRevokedAt()).isNotNull();
        assertThat(result.recipient()).isSameAs(recipient);
        verify(consentGrantRepository).save(share);
    }

    @Test
    @DisplayName("TC-CONSENT-068 CR-2: another patient's share is 404 and is left alone")
    void revoke_otherPatientsShareIsNotFound() {
        final ConsentGrant share = activeShare();
        when(consentGrantRepository.findById(1L)).thenReturn(Optional.of(share));

        assertThatThrownBy(() -> service.revokeShare(11L, 1L))
                .isInstanceOf(AppException.class)
                .extracting(e -> ((AppException) e).getStatus())
                .isEqualTo(HttpStatus.NOT_FOUND);
        assertThat(share.getStatus()).isEqualTo(ConsentGrant.STATUS_ACTIVE);
        verify(consentGrantRepository, never()).save(any(ConsentGrant.class));
    }

    @Test
    @DisplayName("TC-CONSENT-069 CR-2: a caregiver's MEDICARE_VIEW grant can't be revoked as a share")
    void revoke_caregiverGrantIsNotFound() {
        final ConsentGrant caregiverGrant = activeShare();
        caregiverGrant.setGranteeRole("CAREGIVER");
        when(consentGrantRepository.findById(1L)).thenReturn(Optional.of(caregiverGrant));

        assertThatThrownBy(() -> service.revokeShare(PATIENT_USER_ID, 1L))
                .isInstanceOf(AppException.class);
        assertThat(caregiverGrant.getStatus()).isEqualTo(ConsentGrant.STATUS_ACTIVE);
        verify(consentGrantRepository, never()).save(any(ConsentGrant.class));
    }

    @Test
    @DisplayName("TC-CONSENT-070 CR-2: a share in another scope, a missing id or a null id is 404")
    void revoke_wrongScopeOrMissingIsNotFound() {
        final ConsentGrant other = activeShare();
        other.setScope(ConsentGrant.SCOPE_AI_RETRIEVAL);
        when(consentGrantRepository.findById(1L)).thenReturn(Optional.of(other));
        when(consentGrantRepository.findById(2L)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.revokeShare(PATIENT_USER_ID, 1L)).isInstanceOf(AppException.class);
        assertThatThrownBy(() -> service.revokeShare(PATIENT_USER_ID, 2L)).isInstanceOf(AppException.class);
        assertThatThrownBy(() -> service.revokeShare(PATIENT_USER_ID, null)).isInstanceOf(AppException.class);
        verify(consentGrantRepository, never()).save(any(ConsentGrant.class));
    }

    @Test
    @DisplayName("TC-CONSENT-071 CR-2: revoking a share that already ended changes nothing")
    void revoke_alreadyRevokedIsNoOp() {
        final ConsentGrant share = activeShare();
        final Instant revokedAt = Instant.parse("2026-10-01T00:00:00Z");
        share.setStatus(ConsentGrant.STATUS_REVOKED);
        share.setRevokedAt(revokedAt);
        when(consentGrantRepository.findById(1L)).thenReturn(Optional.of(share));
        when(userRepository.findById(RECIPIENT_USER_ID)).thenReturn(Optional.empty());

        final MedicareShareService.ShareResult result = service.revokeShare(PATIENT_USER_ID, 1L);

        assertThat(result.grant().getRevokedAt()).isEqualTo(revokedAt);
        assertThat(result.recipient()).isNull();
        verify(consentGrantRepository, never()).save(any(ConsentGrant.class));
    }

    @Test
    @DisplayName("TC-CONSENT-077 CR-2: Shared with me lists received shares with the patient's record id and name")
    void sharedWithMe_listsReceivedShares() {
        final ConsentGrant share = activeShare();
        share.setGrantedAt(Instant.parse("2026-10-20T12:00:00Z"));
        share.setExpiresAt(Instant.parse("2027-01-18T12:00:00Z"));
        final ConsentGrant caregiverGrant = activeShare();
        caregiverGrant.setId(2L);
        caregiverGrant.setGranteeRole("CAREGIVER");
        when(consentGrantRepository.findActiveGrantsForGrantee(
                eq(RECIPIENT_USER_ID), eq(ConsentGrant.SCOPE_MEDICARE_VIEW), any(Instant.class)))
                .thenReturn(List.of(share, caregiverGrant));
        final Patient record = new Patient();
        record.setId(500L);
        record.setUser(patient);
        when(patientRepository.findByUserId(PATIENT_USER_ID)).thenReturn(Optional.of(record));

        final List<MedicareSharedWithMeResponse> received = service.listSharedWithMe(RECIPIENT_USER_ID);

        assertThat(received).containsExactly(new MedicareSharedWithMeResponse(
                1L, PATIENT_USER_ID, 500L, "Pat Patient",
                Instant.parse("2026-10-20T12:00:00Z"), Instant.parse("2027-01-18T12:00:00Z")));
    }

    @Test
    @DisplayName("TC-CONSENT-078 CR-2: a sharer with no patient record still appears, with a null patientId")
    void sharedWithMe_noPatientRecord() {
        when(consentGrantRepository.findActiveGrantsForGrantee(
                eq(RECIPIENT_USER_ID), eq(ConsentGrant.SCOPE_MEDICARE_VIEW), any(Instant.class)))
                .thenReturn(List.of(activeShare()));
        when(patientRepository.findByUserId(PATIENT_USER_ID)).thenReturn(Optional.empty());
        when(userRepository.findById(PATIENT_USER_ID)).thenReturn(Optional.of(patient));

        final List<MedicareSharedWithMeResponse> received = service.listSharedWithMe(RECIPIENT_USER_ID);

        assertThat(received).hasSize(1);
        assertThat(received.get(0).patientId()).isNull();
        assertThat(received.get(0).patientName()).isEqualTo("Pat Patient");
    }

    @Test
    @DisplayName("TC-CONSENT-079 CR-2: Shared with me with no user id is empty and queries nothing")
    void sharedWithMe_nullUserIsEmpty() {
        assertThat(service.listSharedWithMe(null)).isEmpty();
        verifyNoInteractions(consentGrantRepository, patientRepository, userRepository);
    }

    @Test
    @DisplayName("TC-CONSENT-058 CR-2: listing with no patient id is empty and queries nothing")
    void list_nullPatientIsEmpty() {
        assertThat(service.listActiveShares(null)).isEmpty();
        verifyNoInteractions(consentGrantRepository, userRepository);
        verify(consentGrantRepository, never()).saveAll(anyList());
    }
}
