package com.careconnect.integration.cerner;

import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.ehr.EhrPatientCrosswalkRepository;
import com.careconnect.repository.ehr.EhrRawPayloadRepository;
import com.careconnect.repository.ehr.EhrSourceRepository;
import com.careconnect.service.ehr.CernerOAuthService;
import java.time.Clock;
import java.util.List;
import java.util.Objects;

/**
 * Non-bean adapter around the authenticated {@link DefaultCernerAllergyService} and
 * {@link CernerAllergyHttpClient} {@code AllergyIntolerance} Bundle transport. Spring registers
 * {@link DefaultCernerAllergyService} directly when {@code careconnect.cerner.enabled=true}.
 */
public class CernerAllergyServiceImpl implements CernerAllergyService {

    private final CernerAllergyService delegate;

    public CernerAllergyServiceImpl(final CernerAllergyService delegate) {
        this.delegate = Objects.requireNonNull(delegate, "delegate is required");
    }

    public CernerAllergyServiceImpl(
            final PatientRepository patients,
            final EhrSourceRepository sources,
            final EhrPatientCrosswalkRepository crosswalks,
            final EhrRawPayloadRepository rawPayloads,
            final CernerOAuthService oauth,
            final CernerAllergyHttpClient client,
            final Clock clock) {
        this(new DefaultCernerAllergyService(
                patients, sources, crosswalks, rawPayloads, oauth, client, clock));
    }

    @Override
    @SuppressWarnings("PMD.PreserveStackTrace")
    public List<CernerAllergyMapper.Allergy> getAllergies(final long patientId) {
        if (patientId <= 0L) {
            throw new IllegalArgumentException("patientId must be positive");
        }
        try {
            return delegate.getAllergies(patientId);
        } catch (UnknownPatientException | CernerSourceException ex) {
            throw ex;
        } catch (RuntimeException ex) {
            throw new CernerSourceException("CERNER_SOURCE_UNAVAILABLE", true);
        }
    }
}
