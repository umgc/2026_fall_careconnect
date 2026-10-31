package com.careconnect.service.ehr;

import com.careconnect.ehr.reconciliation.IdentityFieldNames;
import com.careconnect.ehr.reconciliation.IdentityReconciler;
import com.careconnect.ehr.reconciliation.ReconciliationOutcome;
import com.careconnect.ehr.reconciliation.SourceIdentitySnapshot;
import com.careconnect.model.ehr.EhrSourceIdentity;
import com.careconnect.repository.ehr.EhrSourceIdentityRepository;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;

import java.time.Instant;
import java.time.LocalDate;
import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

/**
 * Unit tests for {@link EpicIdentitySync} — the Epic {@code Patient} -> identity-reconciliation feed
 * (Cononical_5_1 Step 7). Mocks the identity repository and the reconciler and captures both the
 * upserted {@code ehr_source_identity} row and the {@link SourceIdentitySnapshot} handed to the
 * reconciler.
 */
class EpicIdentitySyncTest {

    private final EhrSourceIdentityRepository identities = mock(EhrSourceIdentityRepository.class);
    private final IdentityReconciler reconciler = mock(IdentityReconciler.class);
    private final ObjectMapper mapper = new ObjectMapper();
    private final EpicIdentitySync sync = new EpicIdentitySync(identities, reconciler);

    private static final String FULL_PATIENT = "{"
            + "\"resourceType\":\"Patient\",\"id\":\"pat-1\","
            + "\"meta\":{\"lastUpdated\":\"2026-09-01T10:00:00Z\"},"
            + "\"name\":[{\"family\":\"Doe\",\"given\":[\"Jane\",\"Q\"]}],"
            + "\"birthDate\":\"1980-05-05\",\"gender\":\"female\","
            + "\"telecom\":[{\"system\":\"phone\",\"value\":\"555-1234\"},"
            + "  {\"system\":\"email\",\"value\":\"jane@x.com\"}],"
            + "\"address\":[{\"line\":[\"1 Main St\",\"Apt 2\"],\"city\":\"Austin\","
            + "  \"state\":\"TX\",\"postalCode\":\"78701\"}],"
            + "\"managingOrganization\":{\"display\":\"Epic Clinic\"},"
            + "\"communication\":[{\"language\":{\"text\":\"English\"}}],"
            + "\"identifier\":[{\"value\":\"MEM-99\"}]}";

    private JsonNode json(final String raw) {
        try {
            return mapper.readTree(raw);
        } catch (final Exception e) {
            throw new RuntimeException(e);
        }
    }

    // --- guards ----------------------------------------------------------

    @Test
    void syncFromPatient_isNoOp_whenAnyArgIsNull() {
        final JsonNode patient = json(FULL_PATIENT);
        sync.syncFromPatient(null, 3L, patient);
        sync.syncFromPatient(7L, null, patient);
        sync.syncFromPatient(7L, 3L, null);
        verifyNoInteractions(identities, reconciler);
    }

    @Test
    void syncFromPatient_skipsEntirely_whenPatientHasNoMetaLastUpdated() {
        // "Never fabricate a provenance timestamp": an undated Patient writes nothing.
        sync.syncFromPatient(7L, 3L, json("{\"resourceType\":\"Patient\",\"id\":\"pat-1\","
                + "\"name\":[{\"family\":\"Doe\"}]}"));
        verifyNoInteractions(identities, reconciler);
    }

    // --- happy path ------------------------------------------------------

    @Test
    void syncFromPatient_mapsIdentityRowAndReconciles() {
        sync.syncFromPatient(7L, 3L, json(FULL_PATIENT));

        final ArgumentCaptor<EhrSourceIdentity> savedRow = ArgumentCaptor.forClass(EhrSourceIdentity.class);
        verify(identities).save(savedRow.capture());
        final EhrSourceIdentity row = savedRow.getValue();
        assertThat(row.getPatientId()).isEqualTo(7L);
        assertThat(row.getSourceId()).isEqualTo(3L);
        assertThat(row.getSourceUpdatedAt()).isEqualTo(Instant.parse("2026-09-01T10:00:00Z"));
        assertThat(row.getGivenName()).isEqualTo("Jane Q");
        assertThat(row.getFamilyName()).isEqualTo("Doe");
        assertThat(row.getDateOfBirth()).isEqualTo(LocalDate.of(1980, 5, 5));
        assertThat(row.getGender()).isEqualTo("female");
        assertThat(row.getPhone()).isEqualTo("555-1234");
        assertThat(row.getEmail()).isEqualTo("jane@x.com");
        assertThat(row.getAddressLine1()).isEqualTo("1 Main St");
        assertThat(row.getAddressLine2()).isEqualTo("Apt 2");
        assertThat(row.getCity()).isEqualTo("Austin");
        assertThat(row.getState()).isEqualTo("TX");
        assertThat(row.getPostalCode()).isEqualTo("78701");
        assertThat(row.getManagingOrg()).isEqualTo("Epic Clinic");
        assertThat(row.getLanguage()).isEqualTo("English");
        assertThat(row.getMemberId()).isEqualTo("MEM-99");

        final ArgumentCaptor<SourceIdentitySnapshot> snap = ArgumentCaptor.forClass(SourceIdentitySnapshot.class);
        verify(reconciler).reconcile(snap.capture());
        final SourceIdentitySnapshot snapshot = snap.getValue();
        assertThat(snapshot.patientId()).isEqualTo(7L);
        assertThat(snapshot.sourceId()).isEqualTo(3L);
        assertThat(snapshot.sourceUpdatedAt()).isEqualTo(Instant.parse("2026-09-01T10:00:00Z"));
        // Only the 10 reconciled fields, keyed by the IdentityFieldNames constants (no gender /
        // managing_org / language / member_id).
        assertThat(snapshot.fields()).containsOnlyKeys(
                IdentityFieldNames.GIVEN_NAME, IdentityFieldNames.FAMILY_NAME,
                IdentityFieldNames.DATE_OF_BIRTH, IdentityFieldNames.PHONE, IdentityFieldNames.EMAIL,
                IdentityFieldNames.ADDRESS_LINE1, IdentityFieldNames.ADDRESS_LINE2,
                IdentityFieldNames.CITY, IdentityFieldNames.STATE, IdentityFieldNames.POSTAL_CODE);
        assertThat(snapshot.fields())
                .containsEntry(IdentityFieldNames.GIVEN_NAME, "Jane Q")
                .containsEntry(IdentityFieldNames.DATE_OF_BIRTH, "1980-05-05")
                .containsEntry(IdentityFieldNames.CITY, "Austin");
    }

    @Test
    void syncFromPatient_reusesExistingIdentityRowId() {
        final EhrSourceIdentity existing = EhrSourceIdentity.builder().patientId(7L).sourceId(3L).build();
        existing.setId(55L);
        when(identities.findByPatientIdAndSourceId(7L, 3L)).thenReturn(Optional.of(existing));

        sync.syncFromPatient(7L, 3L, json(FULL_PATIENT));

        final ArgumentCaptor<EhrSourceIdentity> savedRow = ArgumentCaptor.forClass(EhrSourceIdentity.class);
        verify(identities).save(savedRow.capture());
        assertThat(savedRow.getValue().getId()).isEqualTo(55L);
    }

    @Test
    void syncFromPatient_savesRowButSkipsReconcile_whenNoReconcilableFields() {
        // Only id + meta: the row is upserted, but there is nothing to reconcile.
        sync.syncFromPatient(7L, 3L, json("{\"resourceType\":\"Patient\",\"id\":\"pat-1\","
                + "\"meta\":{\"lastUpdated\":\"2026-09-01T10:00:00Z\"}}"));

        verify(identities).save(any(EhrSourceIdentity.class));
        verify(reconciler, never()).reconcile(any());
    }

    @Test
    void syncFromPatient_completesWhenReconcilerReturnsPendingDob() {
        when(reconciler.reconcile(any())).thenReturn(List.of(new ReconciliationOutcome(
                IdentityFieldNames.DATE_OF_BIRTH,
                ReconciliationOutcome.Decision.PENDING_PATIENT_CONFIRMATION,
                "1980-05-05")));

        assertThatCode(() -> sync.syncFromPatient(7L, 3L, json(FULL_PATIENT)))
                .doesNotThrowAnyException();
        verify(reconciler).reconcile(any());
    }

    @Test
    void syncFromPatient_yearOnlyBirthDate_omitsDateOfBirthFromSnapshot() {
        sync.syncFromPatient(7L, 3L, json("{\"resourceType\":\"Patient\",\"id\":\"pat-1\","
                + "\"meta\":{\"lastUpdated\":\"2026-09-01T10:00:00Z\"},"
                + "\"name\":[{\"family\":\"Doe\"}],\"birthDate\":\"1980\"}"));

        final ArgumentCaptor<EhrSourceIdentity> savedRow = ArgumentCaptor.forClass(EhrSourceIdentity.class);
        verify(identities).save(savedRow.capture());
        assertThat(savedRow.getValue().getDateOfBirth()).isNull();

        final ArgumentCaptor<SourceIdentitySnapshot> snap = ArgumentCaptor.forClass(SourceIdentitySnapshot.class);
        verify(reconciler).reconcile(snap.capture());
        assertThat(snap.getValue().fields()).doesNotContainKey(IdentityFieldNames.DATE_OF_BIRTH);
    }
}
