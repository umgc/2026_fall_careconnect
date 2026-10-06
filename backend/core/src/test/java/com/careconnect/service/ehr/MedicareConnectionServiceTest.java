package com.careconnect.service.ehr;

import com.careconnect.model.Patient;
import com.careconnect.model.User;
import com.careconnect.model.ehr.EhrPatientCrosswalk;
import com.careconnect.model.ehr.EhrSource;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.ehr.EhrCoverageRecordRepository;
import com.careconnect.repository.ehr.EhrIdentityConflictRepository;
import com.careconnect.repository.ehr.EhrPatientCrosswalkRepository;
import com.careconnect.repository.ehr.EhrRawPayloadRepository;
import com.careconnect.repository.ehr.EhrSourceIdentityRepository;
import com.careconnect.repository.ehr.EhrSourceRepository;
import com.careconnect.repository.ehr.EhrVisitRecordRepository;
import com.careconnect.security.TokenCryptor;
import com.careconnect.service.ehr.MedicareConnectionService.LinkOutcome;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.InOrder;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.inOrder;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Starting, finishing and abandoning a Medicare link (WBS 6.2.39), including the three #252 review
 * blockers it fixes: the crosswalk keyed by user id, the {@code ""} placeholders that let only one
 * patient finish, and plain-text tokens.
 */
class MedicareConnectionServiceTest {

    private static final Instant NOW = Instant.parse("2026-10-04T12:00:00Z");
    private static final long MEDICARE_SOURCE = 2L;
    /** Patient 2 belongs to user 6, as in the dev seed: the ids differ. */
    private static final long USER_ID = 6L;
    private static final long PATIENT_ID = 2L;

    private PatientRepository patients;
    private EhrPatientCrosswalkRepository crosswalks;
    private TokenCryptor cryptor;
    private MedicareService medicare;
    private MedicareTokenRefresher refresher;
    private MedicareConnectionService.MedicareDataStores stores;
    private PlatformTransactionManager txManager;
    private MedicareConnectionService service;

    @BeforeEach
    void setUp() {
        patients = mock(PatientRepository.class);
        crosswalks = mock(EhrPatientCrosswalkRepository.class);
        EhrSourceRepository sources = mock(EhrSourceRepository.class);
        when(sources.findByCode("MEDICARE")).thenReturn(Optional.of(EhrSource.builder().id(MEDICARE_SOURCE).code("MEDICARE").build()));
        cryptor = new TokenCryptor("careconnect-test-secret-32bytes!");
        medicare = mock(MedicareService.class);
        refresher = mock(MedicareTokenRefresher.class);
        stores = new MedicareConnectionService.MedicareDataStores(
                mock(EhrRawPayloadRepository.class), mock(EhrSourceIdentityRepository.class),
                mock(EhrCoverageRecordRepository.class), mock(EhrVisitRecordRepository.class),
                mock(EhrIdentityConflictRepository.class));
        txManager = mock(PlatformTransactionManager.class);
        service = new MedicareConnectionService(patients, crosswalks, sources, cryptor, medicare, refresher, stores,
                new TransactionTemplate(txManager), Clock.fixed(NOW, ZoneOffset.UTC));
        when(crosswalks.save(any(EhrPatientCrosswalk.class))).thenAnswer(inv -> inv.getArgument(0));
    }

    private EhrPatientCrosswalk pending(final String linkToken, final Instant expiresAt) {
        return EhrPatientCrosswalk.builder().id(10L).patientId(PATIENT_ID).sourceId(MEDICARE_SOURCE)
                .linkToken(linkToken).linkTokenExpiresAt(expiresAt).build();
    }

    @Test
    @DisplayName("a user is mapped to their patient id, not their user id")
    void patientIdIsNotUserId() {
        final Patient patient = Patient.builder().id(PATIENT_ID).build();
        when(patients.findByUserId(USER_ID)).thenReturn(Optional.of(patient));

        assertThat(service.patientIdFor(User.builder().id(USER_ID).build())).contains(PATIENT_ID);
        assertThat(service.patientIdFor(User.builder().id(99L).build())).isEmpty();
    }

    @Test
    @DisplayName("starting a link stores the patient id, a fresh link token, a 15-minute expiry, and no external id")
    void startLinkCreatesPendingRow() {
        when(crosswalks.findByPatientIdAndSourceId(PATIENT_ID, MEDICARE_SOURCE)).thenReturn(Optional.empty());

        final String token = service.startLink(PATIENT_ID);

        final ArgumentCaptor<EhrPatientCrosswalk> saved = ArgumentCaptor.forClass(EhrPatientCrosswalk.class);
        verify(crosswalks).save(saved.capture());
        assertThat(saved.getValue().getPatientId()).isEqualTo(PATIENT_ID);
        assertThat(saved.getValue().getSourceId()).isEqualTo(MEDICARE_SOURCE);
        assertThat(saved.getValue().getLinkToken()).isEqualTo(token).hasSizeGreaterThanOrEqualTo(40);
        assertThat(saved.getValue().getLinkTokenExpiresAt()).isEqualTo(NOW.plus(MedicareConnectionService.LINK_TOKEN_TTL));
        assertThat(saved.getValue().getExternalPatientId()).as("null, never \"\"").isNull();
        assertThat(saved.getValue().isLinked()).isFalse();
    }

    @Test
    @DisplayName("re-linking keeps the existing link working until the new sign-in completes")
    void reLinkKeepsExistingToken() {
        final EhrPatientCrosswalk linked = pending(null, null);
        linked.setToken(cryptor.encrypt("old-access"));
        when(crosswalks.findByPatientIdAndSourceId(PATIENT_ID, MEDICARE_SOURCE)).thenReturn(Optional.of(linked));

        service.startLink(PATIENT_ID);

        assertThat(linked.isLinked()).isTrue();
        assertThat(service.accessToken(linked)).contains("old-access");
        assertThat(linked.getLinkToken()).isNotNull();
    }

    @Test
    @DisplayName("each start issues a different link token")
    void linkTokensAreUnique() {
        when(crosswalks.findByPatientIdAndSourceId(PATIENT_ID, MEDICARE_SOURCE)).thenReturn(Optional.empty());
        assertThat(service.startLink(PATIENT_ID)).isNotEqualTo(service.startLink(PATIENT_ID));
    }

    @Test
    @DisplayName("an expired, unknown or blank link token is not a pending link")
    void expiredOrUnknownTokenIsRefused() {
        when(crosswalks.findByLinkToken("expired")).thenReturn(Optional.of(pending("expired", NOW.minusSeconds(1))));
        when(crosswalks.findByLinkToken("unknown")).thenReturn(Optional.empty());

        assertThat(service.pendingLink("expired")).isEmpty();
        assertThat(service.pendingLink("unknown")).isEmpty();
        assertThat(service.pendingLink("")).isEmpty();
        assertThat(service.pendingLink(null)).isEmpty();
    }

    @Test
    @DisplayName("completing a link stores encrypted tokens, the external id, and clears the link token to null")
    void completeLinkStoresEncryptedTokens() {
        final EhrPatientCrosswalk row = pending("lt", NOW.plusSeconds(60));
        when(crosswalks.findByLinkToken("lt")).thenReturn(Optional.of(row));
        when(crosswalks.findBySourceIdAndExternalPatientId(MEDICARE_SOURCE, "-20140000008325")).thenReturn(Optional.empty());
        final Instant expires = NOW.plusSeconds(3600);

        final LinkOutcome outcome = service.completeLink("lt", "-20140000008325", "access-1", expires, "refresh-1");

        assertThat(outcome).isEqualTo(LinkOutcome.CONNECTED);
        assertThat(row.getExternalPatientId()).isEqualTo("-20140000008325");
        assertThat(row.getToken()).isNotEqualTo("access-1");
        assertThat(row.getRefreshToken()).isNotEqualTo("refresh-1");
        assertThat(cryptor.decrypt(row.getRefreshToken())).isEqualTo("refresh-1");
        assertThat(service.accessToken(row)).contains("access-1");
        assertThat(row.getTokenExpiresAt()).isEqualTo(expires);
        assertThat(row.getLinkToken()).as("null, never \"\": a second patient must be able to finish too").isNull();
        assertThat(row.getLinkTokenExpiresAt()).isNull();
        assertThat(row.isLinked()).isTrue();
    }

    @Test
    @DisplayName("an expired link token at the callback stores nothing")
    void completeLinkWithExpiredTokenStoresNothing() {
        when(crosswalks.findByLinkToken("lt")).thenReturn(Optional.of(pending("lt", NOW.minusSeconds(1))));

        assertThat(service.completeLink("lt", "-1", "access", null, null)).isEqualTo(LinkOutcome.LINK_EXPIRED);
        verify(crosswalks, never()).save(any());
    }

    @Test
    @DisplayName("a Medicare account already linked to another patient is refused, and the pending row removed")
    void alreadyLinkedElsewhereIsRefused() {
        final EhrPatientCrosswalk row = pending("lt", NOW.plusSeconds(60));
        final EhrPatientCrosswalk someoneElse = EhrPatientCrosswalk.builder().id(99L).patientId(1L)
                .sourceId(MEDICARE_SOURCE).externalPatientId("-20140000008325").build();
        when(crosswalks.findByLinkToken("lt")).thenReturn(Optional.of(row));
        when(crosswalks.findBySourceIdAndExternalPatientId(MEDICARE_SOURCE, "-20140000008325")).thenReturn(Optional.of(someoneElse));

        assertThat(service.completeLink("lt", "-20140000008325", "access", null, null))
                .isEqualTo(LinkOutcome.ALREADY_LINKED_ELSEWHERE);
        verify(crosswalks).delete(row);
        assertThat(row.isLinked()).isFalse();
    }

    @Test
    @DisplayName("abandoning a link removes a row that was only pending, but keeps an existing link")
    void abandonLink() {
        final EhrPatientCrosswalk onlyPending = pending("p", NOW.plusSeconds(60));
        final EhrPatientCrosswalk relinking = pending("r", NOW.plusSeconds(60));
        relinking.setToken(cryptor.encrypt("still-valid"));
        when(crosswalks.findByLinkToken("p")).thenReturn(Optional.of(onlyPending));
        when(crosswalks.findByLinkToken("r")).thenReturn(Optional.of(relinking));

        service.abandonLink("p");
        service.abandonLink("r");

        verify(crosswalks).delete(onlyPending);
        assertThat(relinking.isLinked()).isTrue();
        assertThat(relinking.getLinkToken()).isNull();
    }

    @Test
    @DisplayName("status reports linked only once a token is on file; a pending link is not linked")
    void status() {
        final EhrPatientCrosswalk linked = pending(null, null);
        linked.setToken(cryptor.encrypt("a"));
        linked.setLastLoggedIn(java.time.LocalDateTime.parse("2026-10-04T08:00:00"));
        when(crosswalks.findByPatientIdAndSourceId(PATIENT_ID, MEDICARE_SOURCE)).thenReturn(Optional.of(linked));
        when(crosswalks.findByPatientIdAndSourceId(3L, MEDICARE_SOURCE)).thenReturn(Optional.of(pending("x", NOW.plusSeconds(60))));
        when(crosswalks.findByPatientIdAndSourceId(4L, MEDICARE_SOURCE)).thenReturn(Optional.empty());

        assertThat(service.status(PATIENT_ID).connected()).isTrue();
        assertThat(service.status(PATIENT_ID).status()).isEqualTo("LINKED");
        assertThat(service.status(PATIENT_ID).connectedAt()).isEqualTo(linked.getLastLoggedIn());
        assertThat(service.status(3L).connected()).isFalse();
        assertThat(service.status(4L).status()).isEqualTo("UNLINKED");
    }

    @Test
    @DisplayName("disconnect revokes at Blue Button, then deletes the Medicare data and the connection in one transaction")
    void disconnectDeletesMedicareData() {
        final EhrPatientCrosswalk linked = pending(null, null);
        linked.setToken(cryptor.encrypt("access-to-revoke"));
        when(crosswalks.findByPatientIdAndSourceId(PATIENT_ID, MEDICARE_SOURCE)).thenReturn(Optional.of(linked));

        assertThat(service.disconnect(PATIENT_ID)).isTrue();

        final InOrder order = inOrder(medicare, txManager, stores.rawPayloads(), crosswalks);
        order.verify(medicare).revoke("access-to-revoke");
        order.verify(txManager).getTransaction(any());
        order.verify(stores.rawPayloads()).deleteAllForPatientAndSource(PATIENT_ID, MEDICARE_SOURCE);
        order.verify(crosswalks).delete(linked);
        order.verify(txManager).commit(any());
        verify(stores.sourceIdentities()).deleteAllForPatientAndSource(PATIENT_ID, MEDICARE_SOURCE);
        verify(stores.coverages()).deleteAllForPatientAndSource(PATIENT_ID, MEDICARE_SOURCE);
        verify(stores.visits()).deleteAllForPatientAndSource(PATIENT_ID, MEDICARE_SOURCE);
        verify(stores.conflicts()).deleteAllForPatientAndSource(PATIENT_ID, MEDICARE_SOURCE);
    }

    @Test
    @DisplayName("disconnect of a link that never finished deletes without trying to revoke")
    void disconnectPendingLinkSkipsRevoke() {
        when(crosswalks.findByPatientIdAndSourceId(PATIENT_ID, MEDICARE_SOURCE)).thenReturn(Optional.of(pending("x", NOW.plusSeconds(60))));

        assertThat(service.disconnect(PATIENT_ID)).isTrue();

        verifyNoInteractions(medicare);
        verify(crosswalks).delete(any(EhrPatientCrosswalk.class));
    }

    @Test
    @DisplayName("disconnect with nothing linked is a no-op, not an error")
    void disconnectWithNothingLinked() {
        when(crosswalks.findByPatientIdAndSourceId(PATIENT_ID, MEDICARE_SOURCE)).thenReturn(Optional.empty());

        assertThat(service.disconnect(PATIENT_ID)).isFalse();

        verifyNoInteractions(medicare, txManager);
        verify(crosswalks, never()).delete(any());
    }

    private EhrPatientCrosswalk linkedExpiringAt(final Instant expiresAt) {
        final EhrPatientCrosswalk row = pending(null, null);
        row.setToken(cryptor.encrypt("old-access"));
        row.setRefreshToken(cryptor.encrypt("old-refresh"));
        row.setTokenExpiresAt(expiresAt);
        return row;
    }

    @Test
    @DisplayName("a token well before expiry is used as is, with no refresh")
    void freshTokenIsNotRefreshed() {
        assertThat(service.accessToken(linkedExpiringAt(NOW.plusSeconds(1800)))).contains("old-access");
        verifyNoInteractions(refresher);
    }

    @Test
    @DisplayName("STP-M3-E-12: a token at expiry is refreshed without the patient, and the new tokens are stored encrypted")
    void expiredTokenIsRefreshed() {
        final EhrPatientCrosswalk row = linkedExpiringAt(NOW.plusSeconds(30));
        when(refresher.refresh("old-refresh")).thenReturn(
                new MedicareTokenRefresher.Refreshed("new-access", NOW.plusSeconds(3600), "new-refresh"));

        assertThat(service.accessToken(row)).contains("new-access");

        assertThat(cryptor.decrypt(row.getToken())).isEqualTo("new-access");
        assertThat(cryptor.decrypt(row.getRefreshToken())).isEqualTo("new-refresh");
        assertThat(row.getTokenExpiresAt()).isEqualTo(NOW.plusSeconds(3600));
        verify(crosswalks).save(row);
    }

    @Test
    @DisplayName("a refresh that does not rotate the refresh token keeps the old one")
    void refreshWithoutRotationKeepsRefreshToken() {
        final EhrPatientCrosswalk row = linkedExpiringAt(NOW.minusSeconds(5));
        when(refresher.refresh("old-refresh")).thenReturn(new MedicareTokenRefresher.Refreshed("new-access", null, null));

        service.accessToken(row);

        assertThat(cryptor.decrypt(row.getRefreshToken())).isEqualTo("old-refresh");
    }

    @Test
    @DisplayName("FR-MCR-09: a rejected refresh sets the link to Unlinked and gives no token; the Medicare data stays")
    void rejectedRefreshUnlinks() {
        final EhrPatientCrosswalk row = linkedExpiringAt(NOW.minusSeconds(5));
        when(refresher.refresh("old-refresh")).thenReturn(new MedicareTokenRefresher.Rejected(400));

        assertThat(service.accessToken(row)).isEmpty();

        assertThat(row.isLinked()).isFalse();
        assertThat(row.getRefreshToken()).isNull();
        verify(crosswalks, never()).delete(any());
        verifyNoInteractions(stores.rawPayloads(), stores.coverages(), stores.visits());
    }

    @Test
    @DisplayName("a refresh that merely fails leaves the tokens alone and returns the current one")
    void failedRefreshKeepsCurrentToken() {
        final EhrPatientCrosswalk row = linkedExpiringAt(NOW.minusSeconds(5));
        when(refresher.refresh("old-refresh")).thenReturn(new MedicareTokenRefresher.Failed("timeout"));

        assertThat(service.accessToken(row)).contains("old-access");
        assertThat(row.isLinked()).isTrue();
    }

    @Test
    @DisplayName("requireAccessToken throws ERR-MCR-05 when there is no working link")
    void requireAccessTokenWithoutLink() {
        org.assertj.core.api.Assertions.assertThatThrownBy(() -> service.requireAccessToken(pending("x", NOW.plusSeconds(60))))
                .isInstanceOf(MedicareConnectionService.MedicareNotConnectedException.class)
                .hasMessage(MedicareConnectionService.ERR_MCR_05_MESSAGE);
    }

    @Test
    @DisplayName("FR-MCR-09: a token Blue Button rejected marks the link Unlinked without deleting data")
    void markTokenRejected() {
        final EhrPatientCrosswalk row = linkedExpiringAt(NOW.plusSeconds(1800));
        when(crosswalks.findByPatientIdAndSourceId(PATIENT_ID, MEDICARE_SOURCE)).thenReturn(Optional.of(row));

        service.markTokenRejected(PATIENT_ID);

        assertThat(row.isLinked()).isFalse();
        assertThat(service.status(PATIENT_ID).connected()).isFalse();
        verify(crosswalks, never()).delete(any());
    }
}
