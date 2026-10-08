package com.careconnect.integration.cerner;

import java.util.List;

/** Service boundary used by the controller; implemented later by the Cerner client. */
public interface CernerAllergyService {

    /** @throws UnknownPatientException when no local patient exists
     *  @throws CernerSourceException when the Cerner source is unavailable or authorization expired */
    List<CernerAllergyMapper.Allergy> getAllergies(long patientId);

    class UnknownPatientException extends RuntimeException {
        public UnknownPatientException() {
            super("Patient not found");
        }
    }

    class CernerSourceException extends RuntimeException {
        private final String code;
        private final boolean retryable;

        public CernerSourceException(String code, boolean retryable) {
            super("Cerner source error");
            this.code = code;
            this.retryable = retryable;
        }

        public String code() {
            return code;
        }

        public boolean retryable() {
            return retryable;
        }
    }
}
