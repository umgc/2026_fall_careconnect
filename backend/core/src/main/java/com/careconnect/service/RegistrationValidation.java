package com.careconnect.service;

import com.careconnect.dto.CaregiverRegistration;
import com.careconnect.dto.PatientRegistration;
import com.careconnect.dto.ProfessionalInfoDto;
import com.careconnect.exception.AppException;
import org.springframework.http.HttpStatus;

/**
 * Registration-time validation for caregiver professional/company fields
 * and guardrails against patient registrations carrying org data.
 */
public final class RegistrationValidation {

    private RegistrationValidation() {}

    public static void validatePatientRegistration(PatientRegistration reg) {
        if (reg == null) {
            return;
        }
        // PatientRegistration must not carry professional/company fields.
        try {
            var organizationGetter = reg.getClass().getMethod("getOrganization");
            Object value = organizationGetter.invoke(reg);
            if (value instanceof String s && !s.isBlank()) {
                throw new AppException(HttpStatus.BAD_REQUEST,
                        "Patient registration must not include organization fields");
            }
        } catch (NoSuchMethodException ignored) {
            // Expected — PatientRegistration has no organization getter.
        } catch (AppException e) {
            throw e;
        } catch (ReflectiveOperationException e) {
            throw new AppException(HttpStatus.BAD_REQUEST,
                    "Patient registration must not include organization fields");
        }

        try {
            var practiceGetter = reg.getClass().getMethod("getPracticeName");
            Object value = practiceGetter.invoke(reg);
            if (value instanceof String s && !s.isBlank()) {
                throw new AppException(HttpStatus.BAD_REQUEST,
                        "Patient registration must not include organization fields");
            }
        } catch (NoSuchMethodException ignored) {
            // Expected.
        } catch (AppException e) {
            throw e;
        } catch (ReflectiveOperationException e) {
            throw new AppException(HttpStatus.BAD_REQUEST,
                    "Patient registration must not include organization fields");
        }

        try {
            var professionalGetter = reg.getClass().getMethod("getProfessional");
            Object value = professionalGetter.invoke(reg);
            if (value != null) {
                throw new AppException(HttpStatus.BAD_REQUEST,
                        "Patient registration must not include professional fields");
            }
        } catch (NoSuchMethodException ignored) {
            // Expected.
        } catch (AppException e) {
            throw e;
        } catch (ReflectiveOperationException e) {
            throw new AppException(HttpStatus.BAD_REQUEST,
                    "Patient registration must not include professional fields");
        }
    }

    public static void validateCaregiverRegistration(CaregiverRegistration reg) {
        if (reg == null) {
            return;
        }

        String type = reg.getCaregiverType();
        boolean professional = type != null && type.trim().equalsIgnoreCase("Professional");
        ProfessionalInfoDto prof = reg.getProfessional();
        String org = prof == null ? null : prof.resolvedOrganization();

        if (professional) {
            if (org == null || org.isBlank()) {
                throw new AppException(HttpStatus.BAD_REQUEST,
                        "Practice / organization is required for Professional caregivers");
            }
            if (prof == null || prof.getLicenseNumber() == null || prof.getLicenseNumber().isBlank()) {
                throw new AppException(HttpStatus.BAD_REQUEST,
                        "License number is required for Professional caregivers");
            }
            return;
        }

        if (org != null && !org.isBlank()) {
            throw new AppException(HttpStatus.BAD_REQUEST,
                    "Company / practice fields are only allowed for Professional caregivers");
        }
    }
}
