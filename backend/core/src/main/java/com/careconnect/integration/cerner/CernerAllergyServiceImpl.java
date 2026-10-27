package com.careconnect.integration.cerner;

import java.util.List;

import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Service;

@Service
@ConditionalOnProperty(name = "careconnect.cerner.enabled", havingValue = "true")
public class CernerAllergyServiceImpl implements CernerAllergyService {

     private final CernerPatientAppointmentService patientAppointmentService;
     private final CernerFhirBundleHttpClient fhirClient;

     public CernerAllergyServiceImpl(
             CernerPatientAppointmentService patientAppointmentService,
             CernerFhirBundleHttpClient fhirClient) {
      this.patientAppointmentService = patientAppointmentService;
      this.fhirClient = fhirClient;
     }

     @Override
     public List<CernerAllergyMapper.Allergy> getAllergies(long patientId) {
          if (patientId <= 0L) {
              throw new IllegalArgumentException("patientId must be positive");
          }
          try {
              final String authorizedPatientId = resolveAuthorizedPatientId(patientId);
              final var bundle = fhirClient.getAllergies(authorizedPatientId);
              return CernerAllergyMapper.map(bundle, authorizedPatientId);
          } catch (UnknownPatientException ex) {
              throw ex;
          } catch (CernerSourceException ex) {
              throw ex;
          } catch (Exception ex) {
              throw new CernerSourceException("CERNER_SOURCE_UNAVAILABLE", true);
          }
     }

 private String resolveAuthorizedPatientId(long patientId) {
     final boolean valid = patientAppointmentService.validatePatientAndAppointmentExpectedOutputFixtures(
          patientId,
          java.time.Instant.now().minusSeconds(3600),
          java.time.Instant.now());

     if (!valid) {
         throw new UnknownPatientException();
     }

     return String.valueOf(patientId);
    }
}
