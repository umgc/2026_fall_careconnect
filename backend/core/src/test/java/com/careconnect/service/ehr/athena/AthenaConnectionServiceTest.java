package com.careconnect.service.ehr.athena;

import com.careconnect.config.AthenaProperties;
import com.careconnect.dto.ehr.AthenaConnectionResponse;
import com.careconnect.model.ConsentGrant;
import com.careconnect.model.Patient;
import com.careconnect.model.ehr.EhrPatientCrosswalk;
import com.careconnect.repository.ConsentGrantRepository;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.ehr.EhrPatientCrosswalkRepository;
import com.careconnect.service.ConsentService;
import com.careconnect.service.ehr.EhrAuditService;
import com.careconnect.service.ehr.EhrSourceDataPurger;
import com.careconnect.service.ehr.EhrSourceResolver;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.InOrder;
import org.springframework.transaction.support.TransactionCallback;
import org.springframework.transaction.support.TransactionTemplate;

import java.util.List;
import java.util.Optional;

import static com.careconnect.testsupport.fixtures.AthenaFhirFixtures.ROMILDA_ID;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertSame;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.inOrder;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Unit tests for {@link AthenaConnectionService}: how consent and the crosswalk link combine into a
 * connection state, the order connect does things in, and what disconnect removes and keeps.
 */
class AthenaConnectionServiceTest {

    private static final long USER_ID = 7L;
    private static final long PATIENT_ID = 5L;
    private static final long SOURCE_ID = 9L;
    private static final String SOURCE = AthenaProperties.SOURCE_ATHENA;

    private ConsentService consentService;
    private ConsentGrantRepository consentGrants;
    private AthenaPatientLinker linker;
    private AthenaSyncService syncService;
    private AthenaFhirClient fhir;
    private EhrSourceDataPurger purger;
    private EhrPatientCrosswalkRepository crosswalks;
    private EhrAuditService audit;
    private AthenaConnectionService service;

    @BeforeEach
    @SuppressWarnings("unchecked")
    void setUp() {
        consentService = mock(ConsentService.class);
        consentGrants = mock(ConsentGrantRepository.class);
        linker = mock(AthenaPatientLinker.class);
        syncService = mock(AthenaSyncService.class);
        fhir = mock(AthenaFhirClient.class);
        purger = mock(EhrSourceDataPurger.class);
        crosswalks = mock(EhrPatientCrosswalkRepository.class);
        audit = mock(EhrAuditService.class);
        final EhrSourceResolver sources = mock(EhrSourceResolver.class);
        final PatientRepository patients = mock(PatientRepository.class);
        // Runs the callback inline, the way a real template would inside its transaction.
        final TransactionTemplate transactions = mock(TransactionTemplate.class);
        when(transactions.execute(any())).thenAnswer(inv ->
                ((TransactionCallback<Object>) inv.getArgument(0)).doInTransaction(null));
        service = new AthenaConnectionService(consentService, consentGrants, linker, syncService, fhir,
                purger, sources, patients, crosswalks, audit, transactions);

        when(sources.idForCode(SOURCE)).thenReturn(SOURCE_ID);
        when(patients.findByUserId(USER_ID)).thenReturn(Optional.of(Patient.builder().id(PATIENT_ID).build()));
    }

    private void consented(final boolean active) {
        when(consentGrants.findActiveGrants(eq(USER_ID), eq(USER_ID), eq(ConsentGrant.SCOPE_EHR_IMPORT), any()))
                .thenReturn(active ? List.of(ConsentGrant.builder().build()) : List.of());
    }

    private void linked(final boolean linked) {
        when(fhir.linkedPatientId(USER_ID)).thenReturn(linked ? Optional.of(ROMILDA_ID) : Optional.empty());
    }

    @Test
    @DisplayName("status is NOT_CONSENTED without an active EHR-import grant, even when a link exists")
    void statusWithoutConsent() {
        // Arrange: Romilda's link is seeded, but seeding is not consent.
        consented(false);
        linked(true);

        // Act
        final AthenaConnectionResponse status = service.status(USER_ID);

        // Assert
        assertFalse(status.connected());
        assertEquals(AthenaConnectionResponse.NOT_CONNECTED, status.status());
        assertEquals("NOT_CONSENTED", status.reason());
        assertFalse(service.isConnected(USER_ID));
    }

    @Test
    @DisplayName("status is NOT_LINKED when consent exists but no chart is linked")
    void statusWithoutLink() {
        consented(true);
        linked(false);
        assertEquals("NOT_LINKED", service.status(USER_ID).reason());
        assertFalse(service.isConnected(USER_ID));
    }

    @Test
    @DisplayName("consent plus a link is CONNECTED")
    void statusConnected() {
        consented(true);
        linked(true);
        final AthenaConnectionResponse status = service.status(USER_ID);
        assertTrue(status.connected());
        assertEquals(AthenaConnectionResponse.CONNECTED, status.status());
        assertNull(status.reason());
        assertTrue(service.isConnected(USER_ID));
    }

    @Test
    @DisplayName("connect records consent before searching for the chart, then runs the first sync")
    void connectRecordsConsentFirst() {
        // Arrange
        when(linker.link(USER_ID)).thenReturn(AthenaLinkResult.linked(ROMILDA_ID));
        final AthenaSyncResult sync = AthenaSyncResult.completed(List.of());
        when(syncService.sync(USER_ID)).thenReturn(sync);

        // Act
        final AthenaConnectionResponse response = service.connect(USER_ID);

        // Assert
        final InOrder order = inOrder(consentService, linker, syncService);
        order.verify(consentService).recordEhrImportConsent(USER_ID);
        order.verify(linker).link(USER_ID);
        order.verify(syncService).sync(USER_ID);
        assertTrue(response.connected());
        assertSame(sync, response.sync());
    }

    @Test
    @DisplayName("a failed link reports why, keeps the consent, and does not sync")
    void connectWithFailedLink() {
        // Arrange
        when(linker.link(USER_ID)).thenReturn(AthenaLinkResult.of(AthenaLinkResult.State.AMBIGUOUS_MATCH));

        // Act
        final AthenaConnectionResponse response = service.connect(USER_ID);

        // Assert
        assertFalse(response.connected());
        assertEquals("AMBIGUOUS_MATCH", response.reason());
        verify(syncService, never()).sync(any());
        verify(consentService, never()).revokeEhrImportConsent(any());
    }

    @Test
    @DisplayName("disconnect purges athena data and revokes consent when athena was the last linked source")
    void disconnectRevokesWhenLastLink() {
        // Arrange
        final EhrSourceDataPurger.Purged purged = new EhrSourceDataPurger.Purged(3, 3, 0, 0, 1);
        when(purger.purge(USER_ID, PATIENT_ID, SOURCE_ID, SOURCE)).thenReturn(purged);
        when(crosswalks.findByPatientId(PATIENT_ID)).thenReturn(List.of());

        // Act
        final EhrSourceDataPurger.Purged result = service.disconnect(USER_ID);

        // Assert
        assertSame(purged, result);
        final InOrder order = inOrder(purger, consentService, audit);
        order.verify(purger).purge(USER_ID, PATIENT_ID, SOURCE_ID, SOURCE);
        order.verify(consentService).revokeEhrImportConsent(USER_ID);
        order.verify(audit).record(USER_ID, SOURCE, "ATHENA_DISCONNECT", EhrAuditService.OUTCOME_OK);
    }

    @Test
    @DisplayName("disconnect keeps the shared EHR-import grant while another source is still linked")
    void disconnectKeepsConsentForOtherSources() {
        // Arrange: an Epic link remains after athena's crosswalk row is deleted.
        when(purger.purge(anyLong(), any(), any(), any())).thenReturn(new EhrSourceDataPurger.Purged(0, 0, 0, 0, 1));
        when(crosswalks.findByPatientId(PATIENT_ID)).thenReturn(List.of(EhrPatientCrosswalk.builder()
                .patientId(PATIENT_ID).sourceId(3L).externalPatientId("epic-1").build()));

        // Act
        service.disconnect(USER_ID);

        // Assert
        verify(consentService, never()).revokeEhrImportConsent(any());
    }
}
