package com.careconnect.service;

import com.careconnect.dto.CaregiverRegistration;
import com.careconnect.dto.PatientRegistration;
import com.careconnect.dto.ProfessionalInfoDto;
import com.careconnect.exception.AppException;
import org.springframework.http.HttpStatus;

/**
 * Registration-time validation for doctor company fields.
 * Company / practice / license data is allowed only for Primary Care Physician
 * caregivers; other caregivers and all patients must not send it.
 */
public final class RegistrationValidation {

    public static final String PRIMARY_CARE_PHYSICIAN = "Primary Care Physician";

    private RegistrationValidation() {}

    public static void validatePatientRegistration(PatientRegistration reg) {
        // PatientRegistration has no professional/company fields by type.
        if (reg == null) {
            return;
        }
    }

    public static void validateCaregiverRegistration(CaregiverRegistration reg) {
        if (reg == null) {
            return;
        }

        final boolean doctor = isPrimaryCarePhysician(reg.getCaregiverType());
        final ProfessionalInfoDto prof = reg.getProfessional();

        if (!doctor && hasCompanyFields(prof)) {
            throw new AppException(HttpStatus.BAD_REQUEST,
                    "Company / practice fields are only allowed for Primary Care Physician");
        }
        // Doctor company fields are optional — no further required checks.
    }

    public static boolean isPrimaryCarePhysician(String caregiverType) {
        return caregiverType != null
                && caregiverType.trim().equalsIgnoreCase(PRIMARY_CARE_PHYSICIAN);
    }

    private static boolean hasCompanyFields(ProfessionalInfoDto prof) {
        if (prof == null) {
            return false;
        }
        final String org = prof.resolvedOrganization();
        return (org != null && !org.isBlank())
                || (prof.getLicenseNumber() != null && !prof.getLicenseNumber().isBlank())
                || (prof.getIssuingState() != null && !prof.getIssuingState().isBlank())
                || prof.getYearsExperience() > 0;
    }
}
