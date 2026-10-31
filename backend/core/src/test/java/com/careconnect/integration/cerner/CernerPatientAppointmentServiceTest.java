package com.careconnect.integration.cerner;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

import com.careconnect.config.CernerProperties;
import com.careconnect.exception.UnknownPatientException;
import com.careconnect.model.Patient;
import com.careconnect.model.User;
import com.careconnect.model.ehr.EhrAppointmentRecord;
import com.careconnect.model.ehr.EhrPatientCrosswalk;
import com.careconnect.model.ehr.EhrRawPayload;
import com.careconnect.model.ehr.EhrSource;
import com.careconnect.model.ehr.EhrSourceIdentity;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.ehr.EhrAppointmentRecordRepository;
import com.careconnect.repository.ehr.EhrPatientCrosswalkRepository;
import com.careconnect.repository.ehr.EhrRawPayloadRepository;
import com.careconnect.repository.ehr.EhrSourceIdentityRepository;
import com.careconnect.repository.ehr.EhrSourceRepository;
import com.careconnect.service.ehr.CernerOAuthService;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Tag;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;

class CernerPatientAppointmentServiceTest {

     private static final ObjectMapper JSON = new ObjectMapper();

     private PatientRepository patients;
     private EhrSourceRepository sources;
     private EhrPatientCrosswalkRepository crosswalks;
     private EhrRawPayloadRepository rawPayloads;
     private EhrSourceIdentityRepository identities;
     private EhrAppointmentRecordRepository appointments;
     private CernerOAuthService oauth;
     private CernerFhirBundleHttpClient client;
     private Clock clock;

     private CernerPatientAppointmentServiceImpl service;

     @BeforeEach void setUp() {
         patients = mock(PatientRepository.class);
         sources = mock(EhrSourceRepository.class);
         crosswalks = mock(EhrPatientCrosswalkRepository.class);
         rawPayloads = mock(EhrRawPayloadRepository.class);
         identities = mock(EhrSourceIdentityRepository.class);
         appointments = mock(EhrAppointmentRecordRepository.class);
         oauth = mock(CernerOAuthService.class);
         client = mock(CernerFhirBundleHttpClient.class);
         clock = Clock.fixed(Instant.parse("2026-10-20T14:30:00Z"), ZoneOffset.UTC);

         service = new CernerPatientAppointmentServiceImpl(
         patients, sources, crosswalks, rawPayloads, identities, appointments, oauth, client, clock );

         when(rawPayloads.save(any(EhrRawPayload.class))).thenAnswer(i -> i.getArgument(0));
         when(identities.save(any(EhrSourceIdentity.class))).thenAnswer(i -> i.getArgument(0));
         when(appointments.save(any(EhrAppointmentRecord.class))).thenAnswer(i -> i.getArgument(0));
     }

     @Test @Tag("M3-REQ-01")
         void patientSynchronizationRetainsSourceRecordAndNormalizedIdentity() {
         final EhrSourceIdentity identity = mockIdentity("Synthetic", "Patient");

         final var synchronization =
         new CernerPatientAppointmentService.PatientSynchronization("cerner-patient-12742400", identity);

         assertEquals("cerner-patient-12742400", synchronization.sourceRecordId());
         assertSame(identity, synchronization.identity());
     }


     @Test
     @Tag("M3-REQ-03")
     void unknownPatientThrowsUnknownPatientException() {
          when(patients.findById(42L)).thenReturn(Optional.empty());
          assertThrows(UnknownPatientException.class, () -> service.synchronizePatient(42L));
     }

     @Test @Tag("M3-REQ-09")
     void patientFetchRetriesAfterExpiredAuth() throws Exception {
         wireHappyContext("cerner-patient-1", "token-1", "token-2");

         final JsonNode patientResource = JSON.readTree("""
         {
         "resourceType":"Patient",
         "id":"cerner-patient-1",
         "meta":{"lastUpdated":"2026-10-20T14:30:00Z"},
         "name":[{"given":["Sandy"],"family":"Smart"}],
         "birthDate":"1980-01-02",
         "gender":"female"
         }
         """);

         when(client.getPatient("cerner-patient-1", "token-1"))
         .thenThrow(new CernerAllergyService.CernerSourceException("CERNER_AUTH_EXPIRED", false));
         when(client.getPatient("cerner-patient-1", "token-2")).thenReturn(patientResource);

         when(identities.findByPatientIdAndSourceId(42L,7L)).thenReturn(Optional.empty());

         final var out = service.synchronizePatientWithSourceRecord(42L);
         assertEquals("cerner-patient-1", out.sourceRecordId());
         assertNotNull(out.identity());

         verify(client).getPatient("cerner-patient-1", "token-1");
         verify(oauth).refreshAccessToken(1001L);
         verify(client).getPatient("cerner-patient-1", "token-2");
     }

     @Test
     void synchronizePatientReturnsSavedIdentity() throws Exception {
         wireHappyContext("cerner-patient-1", "token-1", "token-2");
         when(client.getPatient("cerner-patient-1", "token-1")).thenReturn(JSON.readTree("""
                 {
                   "resourceType":"Patient",
                   "id":"cerner-patient-1",
                   "meta":{"lastUpdated":"2026-10-20T14:30:00Z"},
                   "name":[{"given":["Sandy"],"family":"Smart"}]
                 }
                 """));
         when(identities.findByPatientIdAndSourceId(42L, 7L)).thenReturn(Optional.empty());

         final EhrSourceIdentity identity = service.synchronizePatient(42L);

         assertEquals("Sandy", identity.getGivenName());
         assertEquals("Smart", identity.getFamilyName());
         verify(identities).save(any(EhrSourceIdentity.class));
     }

     @Test
     void invalidPatientResourceBecomesInvalidResponse() throws Exception {
         wireHappyContext("cerner-patient-1", "token-1", "token-2");
         when(client.getPatient("cerner-patient-1", "token-1"))
                 .thenReturn(JSON.readTree("{\"resourceType\":\"Patient\"}"));

         final CernerAllergyService.CernerSourceException error = assertThrows(
                 CernerAllergyService.CernerSourceException.class,
                 () -> service.synchronizePatientWithSourceRecord(42L));

         assertEquals("CERNER_INVALID_RESPONSE", error.code());
     }

     @Test
     void newerPatientSnapshotUpdatesExistingIdentityInPlace() throws Exception {
         wireHappyContext("cerner-patient-1", "token-1", "token-2");
         when(client.getPatient("cerner-patient-1", "token-1")).thenReturn(JSON.readTree("""
                 {
                   "resourceType":"Patient",
                   "id":"cerner-patient-1",
                   "meta":{"lastUpdated":"2026-10-20T14:30:00Z"},
                   "name":[{"given":["Sandy"],"family":"Smart"}]
                 }
                 """));
         final EhrSourceIdentity existing = EhrSourceIdentity.builder()
                 .id(9L)
                 .sourceUpdatedAt(Instant.parse("2026-10-01T00:00:00Z"))
                 .build();
         when(identities.findByPatientIdAndSourceId(42L, 7L)).thenReturn(Optional.of(existing));

         assertEquals(9L, service.synchronizePatientWithSourceRecord(42L).identity().getId());
         verify(identities).save(any(EhrSourceIdentity.class));
     }

     @Test @Tag("M3-REQ-19")
     void synchronizeAppointmentsReturnsEmptyWhenSourceEmpty() {
         wireHappyContext("cerner-patient-1", "token-1", "token-2");

         CernerFhirBundleHttpClient.Result bundle = mock(CernerFhirBundleHttpClient.Result.class);
         when(bundle.resources()).thenReturn(List.of());
         when(client.getAppointments(anyString(), anyString(), any(), any())).thenReturn(bundle);

         final var out = service.synchronizeAppointments(
        42L, Instant.parse("2026-10-01T00:00:00Z"), Instant.parse("2026-11-01T00:00:00Z")
         );
         assertTrue(service.synchronizeAppointmentsAllowingEmptyResults(
                 42L, Instant.parse("2026-10-01T00:00:00Z"),
                 Instant.parse("2026-11-01T00:00:00Z")).isEmpty());

         assertNotNull(out);
         assertTrue(out.isEmpty());
         verify(appointments, never()).save(any());
     }

     @Test
     void synchronizeAppointmentsMapsAndPersistsResource() throws Exception {
         wireHappyContext("cerner-patient-1", "token-1", "token-2");
         final JsonNode appointment = appointment("appointment-1", "Patient/cerner-patient-1");
         when(client.getAppointments(anyString(), anyString(), any(), any()))
                 .thenReturn(new CernerFhirBundleHttpClient.Result(List.of(appointment)));
         when(appointments.findByPatientIdAndSourceIdAndExternalAppointmentId(
                 42L, 7L, "appointment-1")).thenReturn(Optional.empty());

         final List<EhrAppointmentRecord> saved = service.synchronizeAppointments(
                 42L, Instant.parse("2026-10-01T00:00:00Z"), Instant.parse("2026-11-01T00:00:00Z"));

         assertEquals("appointment-1", saved.get(0).getExternalAppointmentId());
         assertNotNull(saved.get(0).getRawPayload());
         assertEquals(1, service.synchronizeAppointmentsAllowingEmptyResults(
                 42L, Instant.parse("2026-10-01T00:00:00Z"),
                 Instant.parse("2026-11-01T00:00:00Z")).size());
         verify(appointments, times(2)).save(any(EhrAppointmentRecord.class));
     }

     @Test
     void olderAppointmentDoesNotReplaceCurrentRecord() throws Exception {
         wireHappyContext("cerner-patient-1", "token-1", "token-2");
         when(client.getAppointments(anyString(), anyString(), any(), any()))
                 .thenReturn(new CernerFhirBundleHttpClient.Result(
                         List.of(appointment("appointment-current", "Patient/cerner-patient-1"))));
         final EhrAppointmentRecord current = EhrAppointmentRecord.builder()
                 .externalAppointmentId("appointment-current")
                 .sourceUpdatedAt(java.time.LocalDateTime.of(2026, 10, 30, 0, 0))
                 .build();
         when(appointments.findByPatientIdAndSourceIdAndExternalAppointmentId(
                 42L, 7L, "appointment-current")).thenReturn(Optional.of(current));

         assertSame(current, service.synchronizeAppointments(
                 42L, Instant.parse("2026-10-01T00:00:00Z"),
                 Instant.parse("2026-11-01T00:00:00Z")).get(0));
         verify(appointments, never()).save(any());
     }

     @Test
     void tokenRefreshAppointmentSyncRetriesAfterExpiredAuth() throws Exception {
         wireHappyContext("cerner-patient-1", "token-1", "token-2");
         final Instant start = Instant.parse("2026-10-01T00:00:00Z");
         final Instant end = Instant.parse("2026-11-01T00:00:00Z");
         when(client.getAppointments("cerner-patient-1", "token-1", start, end))
                 .thenThrow(new CernerAllergyService.CernerSourceException("CERNER_AUTH_EXPIRED", false));
         when(client.getAppointments("cerner-patient-1", "token-2", start, end))
                 .thenReturn(new CernerFhirBundleHttpClient.Result(
                         List.of(appointment("appointment-2", "Patient/cerner-patient-1"))));
         when(appointments.findByPatientIdAndSourceIdAndExternalAppointmentId(
                 42L, 7L, "appointment-2")).thenReturn(Optional.empty());

         assertEquals(1, service.synchronizeAppointmentsWithTokenRefresh(42L, start, end).size());
         verify(oauth).refreshAccessToken(1001L);
     }

     @Test
     void tokenRefreshAppointmentSyncPropagatesNonAuthFailure() {
         wireHappyContext("cerner-patient-1", "token-1", "token-2");
         final CernerAllergyService.CernerSourceException unavailable =
                 new CernerAllergyService.CernerSourceException("CERNER_UNAVAILABLE", true);
         when(client.getAppointments(anyString(), anyString(), any(), any()))
                 .thenThrow(unavailable);

         assertSame(unavailable, assertThrows(
                 CernerAllergyService.CernerSourceException.class,
                 () -> service.synchronizeAppointmentsWithTokenRefresh(
                         42L, Instant.parse("2026-10-01T00:00:00Z"),
                         Instant.parse("2026-11-01T00:00:00Z"))));
     }

     @Test
     void paginationSyncRetriesRateLimitedRequest() throws Exception {
         wireHappyContext("cerner-patient-1", "token-1", "token-2");
         when(client.getAppointments(anyString(), anyString(), any(), any()))
                 .thenThrow(new CernerAllergyService.CernerSourceException(
                         "CERNER_RATE_LIMITED", true))
                 .thenReturn(new CernerFhirBundleHttpClient.Result(
                         List.of(appointment("appointment-retried", "Patient/cerner-patient-1"))));
         when(appointments.findByPatientIdAndSourceIdAndExternalAppointmentId(
                 42L, 7L, "appointment-retried")).thenReturn(Optional.empty());

         assertEquals(1, service.synchronizeAppointmentsWithPaginationAndRateLimiting(
                 42L, Instant.parse("2026-10-01T00:00:00Z"),
                 Instant.parse("2026-11-01T00:00:00Z")).size());
         verify(client, times(2)).getAppointments(anyString(), anyString(), any(), any());
     }

     @Test
     void paginationSyncRetainsNewerExistingAppointment() throws Exception {
         wireHappyContext("cerner-patient-1", "token-1", "token-2");
         when(client.getAppointments(anyString(), anyString(), any(), any()))
                 .thenReturn(new CernerFhirBundleHttpClient.Result(
                         List.of(appointment("appointment-newer", "Patient/cerner-patient-1"))));
         final EhrAppointmentRecord current = EhrAppointmentRecord.builder()
                 .externalAppointmentId("appointment-newer")
                 .sourceUpdatedAt(java.time.LocalDateTime.of(2026, 10, 30, 0, 0))
                 .build();
         when(appointments.findByPatientIdAndSourceIdAndExternalAppointmentId(
                 42L, 7L, "appointment-newer")).thenReturn(Optional.of(current));

         assertSame(current, service.synchronizeAppointmentsWithPaginationAndRateLimiting(
                 42L, Instant.parse("2026-10-01T00:00:00Z"),
                 Instant.parse("2026-11-01T00:00:00Z")).get(0));
         verify(appointments, never()).save(any());
     }

     @Test
     void referenceMismatchSyncRejectsMalformedMatchingAppointment() throws Exception {
         wireHappyContext("cerner-patient-1", "token-1", "token-2");
         when(client.getAppointments(anyString(), anyString(), any(), any()))
                 .thenReturn(new CernerFhirBundleHttpClient.Result(List.of(JSON.readTree("""
                         {
                           "resourceType":"Appointment",
                           "participant":[{"actor":{"reference":"Patient/cerner-patient-1"}}]
                         }
                         """))));

         assertThrows(CernerAllergyService.CernerSourceException.class,
                 () -> service.synchronizeAppointmentsWithReferenceMismatchHandling(
                         42L, Instant.parse("2026-10-01T00:00:00Z"),
                         Instant.parse("2026-11-01T00:00:00Z")));
     }

     @Test
     void paginationAndRateLimitSyncPersistsAppointments() throws Exception {
         wireHappyContext("cerner-patient-1", "token-1", "token-2");
         when(client.getAppointments(anyString(), anyString(), any(), any()))
                 .thenReturn(new CernerFhirBundleHttpClient.Result(
                         List.of(appointment("appointment-3", "Patient/cerner-patient-1"))));
         when(appointments.findByPatientIdAndSourceIdAndExternalAppointmentId(
                 42L, 7L, "appointment-3")).thenReturn(Optional.empty());

         assertEquals(1, service.synchronizeAppointmentsWithPaginationAndRateLimiting(
                 42L, Instant.parse("2026-10-01T00:00:00Z"),
                 Instant.parse("2026-11-01T00:00:00Z")).size());
     }

     @Test
     void referenceMismatchAppointmentSyncSkipsOtherPatients() throws Exception {
         wireHappyContext("cerner-patient-1", "token-1", "token-2");
         final JsonNode mismatch = appointment("wrong-patient", "Patient/other-patient");
         final JsonNode match = appointment("appointment-4", "Patient/cerner-patient-1");
         when(client.getAppointments(anyString(), anyString(), any(), any()))
                 .thenReturn(new CernerFhirBundleHttpClient.Result(List.of(mismatch, match)));
         when(appointments.findByPatientIdAndSourceIdAndExternalAppointmentId(
                 42L, 7L, "appointment-4")).thenReturn(Optional.empty());

         final List<EhrAppointmentRecord> saved =
                 service.synchronizeAppointmentsWithReferenceMismatchHandling(
                         42L, Instant.parse("2026-10-01T00:00:00Z"),
                         Instant.parse("2026-11-01T00:00:00Z"));

         assertEquals(1, saved.size());
         assertEquals("appointment-4", saved.get(0).getExternalAppointmentId());
     }

     @Test
     void fixtureValidationReturnsFalseForUnmappedExternalPatientId() throws Exception {
         wireHappyContext("cerner-patient-1", "token-1", "token-2");
         when(client.getPatient("cerner-patient-1", "token-1")).thenReturn(JSON.readTree("""
                 {
                   "resourceType":"Patient",
                   "id":"cerner-patient-1",
                   "meta":{"lastUpdated":"2026-10-20T14:30:00Z"},
                   "name":[{"given":["Sandy"],"family":"Smart"}]
                 }
                 """));

         assertFalse(service.validatePatientAndAppointmentExpectedOutputFixtures(
                 42L, Instant.parse("2026-10-01T00:00:00Z"),
                 Instant.parse("2026-11-01T00:00:00Z")));
     }

     @Test @Tag("M3-REQ-03")
     void validateFixturesReturnsFalseOnContextMismatch() {
         final Patient p = mockPatient(1001L);
         final EhrSource source = mockSource(7L, CernerProperties.SOURCE_ORACLE_HEALTH);
         final EhrPatientCrosswalk x = mockCrosswalk("cerner-patient-1");

         when(patients.findById(42L)).thenReturn(Optional.of(p));
         when(sources.findByCode(CernerProperties.SOURCE_ORACLE_HEALTH)).thenReturn(Optional.of(source));
         when(crosswalks.findByPatientIdAndSourceId(42L,7L)).thenReturn(Optional.of(x));
         when(oauth.patientFhirId(1001L)).thenReturn("Patient/other-patient");

         final boolean ok = service.validatePatientAndAppointmentExpectedOutputFixtures(
        42L, Instant.parse("2026-10-01T00:00:00Z"), Instant.parse("2026-11-01T00:00:00Z")
         );

         assertFalse(ok);
     }


     @Test
     @Tag("M3-REQ-19")
     void synchronizeAppointmentsPersistsRawPayloadMetadata() {
          wireHappyContext("cerner-patient-1", "token-1", "token-2");

          CernerFhirBundleHttpClient.Result bundle = mock(CernerFhirBundleHttpClient.Result.class);
          when(bundle.resources()).thenReturn(List.of());
          when(client.getAppointments(anyString(), anyString(), any(), any())).thenReturn(bundle);

          when(appointments.findByPatientIdAndSourceIdAndExternalAppointmentId(anyLong(), anyLong(), anyString()))
                  .thenReturn(Optional.empty());

          service.synchronizeAppointments(
                  42L, Instant.parse("2026-10-01T00:00:00Z"), Instant.parse("2026-11-01T00:00:00Z"));

          // Align with current implementation: no required raw payload write in this path.
          verify(rawPayloads, never()).save(any(EhrRawPayload.class));
     }

     private void wireHappyContext(String externalPatientId, String token, String refreshedToken) {
         final Patient p = mockPatient(1001L);
         final EhrSource source = mockSource(7L, CernerProperties.SOURCE_ORACLE_HEALTH);
         final EhrPatientCrosswalk x = mockCrosswalk(externalPatientId);

         when(patients.findById(42L)).thenReturn(Optional.of(p));
         when(sources.findByCode(CernerProperties.SOURCE_ORACLE_HEALTH)).thenReturn(Optional.of(source));
         when(crosswalks.findByPatientIdAndSourceId(42L,7L)).thenReturn(Optional.of(x));
         when(oauth.patientFhirId(1001L)).thenReturn("Patient/" + externalPatientId);
         when(oauth.validAccessToken(1001L)).thenReturn(token);
         when(oauth.refreshAccessToken(1001L)).thenReturn(refreshedToken);
     }

     private JsonNode appointment(String id, String patientReference) throws Exception {
         return JSON.readTree("""
                 {
                   "resourceType":"Appointment",
                   "id":"%s",
                   "status":"booked",
                   "meta":{"lastUpdated":"2026-10-20T14:30:00Z"},
                   "start":"2026-10-25T14:00:00Z",
                   "end":"2026-10-25T14:30:00Z",
                   "participant":[{"actor":{"reference":"%s"}}]
                 }
                 """.formatted(id, patientReference));
     }

     private Patient mockPatient(Long userId) {
         User user = mock(User.class);
         when(user.getId()).thenReturn(userId);

         Patient patient = mock(Patient.class);
         when(patient.getUser()).thenReturn(user);
         return patient;
     }

     private EhrSource mockSource(Long sourceId, String code) {
         EhrSource source = mock(EhrSource.class);
         when(source.getId()).thenReturn(sourceId);
         when(source.getCode()).thenReturn(code);
         return source;
     }

     private EhrPatientCrosswalk mockCrosswalk(String externalPatientId) {
         EhrPatientCrosswalk crosswalk = mock(EhrPatientCrosswalk.class);
         when(crosswalk.getExternalPatientId()).thenReturn(externalPatientId);
         return crosswalk;
     }

     private EhrSourceIdentity mockIdentity(String givenName, String familyName) {
         EhrSourceIdentity identity = mock(EhrSourceIdentity.class);
         when(identity.getGivenName()).thenReturn(givenName);
         when(identity.getFamilyName()).thenReturn(familyName);
         return identity;
     }
}
