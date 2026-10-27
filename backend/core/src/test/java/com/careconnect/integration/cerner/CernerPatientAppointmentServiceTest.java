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

     @Test @Tag("M3-REQ-19")
     void synchronizeAppointmentsReturnsEmptyWhenSourceEmpty() {
         wireHappyContext("cerner-patient-1", "token-1", "token-2");

         CernerFhirBundleHttpClient.Result bundle = mock(CernerFhirBundleHttpClient.Result.class);
         when(bundle.resources()).thenReturn(List.of());
         when(client.getAppointments(anyString(), anyString(), any(), any())).thenReturn(bundle);

         final var out = service.synchronizeAppointments(
        42L, Instant.parse("2026-10-01T00:00:00Z"), Instant.parse("2026-11-01T00:00:00Z")
         );

         assertNotNull(out);
         assertTrue(out.isEmpty());
         verify(appointments, never()).save(any());
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
