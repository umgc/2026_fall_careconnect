package com.careconnect.service;

import com.careconnect.dto.CaregiverRegistration;
import com.careconnect.dto.PatientRegistration;
import com.careconnect.dto.ProfessionalInfoDto;
import com.careconnect.exception.AppException;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;

import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;

class AuthServiceRegistrationValidationTest {

    @Test
    void primaryCarePhysicianMayIncludeOrganization() {
        final CaregiverRegistration req = new CaregiverRegistration();
        req.setCaregiverType(RegistrationValidation.PRIMARY_CARE_PHYSICIAN);
        final ProfessionalInfoDto info = new ProfessionalInfoDto();
        info.setOrganization("Oak Clinic");
        info.setLicenseNumber("MD-123");
        req.setProfessional(info);
        assertDoesNotThrow(() -> RegistrationValidation.validateCaregiverRegistration(req));
    }

    @Test
    void primaryCarePhysicianCompanyFieldsAreOptional() {
        final CaregiverRegistration req = new CaregiverRegistration();
        req.setCaregiverType(RegistrationValidation.PRIMARY_CARE_PHYSICIAN);
        assertDoesNotThrow(() -> RegistrationValidation.validateCaregiverRegistration(req));
    }

    @Test
    void nonDoctorCaregiverRejectsOrganization() {
        final CaregiverRegistration req = new CaregiverRegistration();
        req.setCaregiverType("Professional");
        final ProfessionalInfoDto info = new ProfessionalInfoDto();
        info.setOrganization("Acme Care");
        req.setProfessional(info);

        assertThatThrownBy(() -> RegistrationValidation.validateCaregiverRegistration(req))
                .isInstanceOf(AppException.class)
                .extracting(ex -> ((AppException) ex).getStatus())
                .isEqualTo(HttpStatus.BAD_REQUEST);
    }

    @Test
    void familyMemberWithoutCompanyFieldsPasses() {
        final CaregiverRegistration req = new CaregiverRegistration();
        req.setCaregiverType("Family Member");
        assertDoesNotThrow(() -> RegistrationValidation.validateCaregiverRegistration(req));
    }

    @Test
    void patientRegistrationHasNoCompanyFieldChecks() {
        assertDoesNotThrow(() -> RegistrationValidation.validatePatientRegistration(new PatientRegistration()));
        assertDoesNotThrow(() -> RegistrationValidation.validatePatientRegistration(null));
    }

    @Test
    void authServiceDelegatesCaregiverValidation() {
        final AuthService service = new AuthService();
        final CaregiverRegistration req = new CaregiverRegistration();
        req.setCaregiverType("Friend");
        final ProfessionalInfoDto info = new ProfessionalInfoDto();
        info.setLicenseNumber("X");
        req.setProfessional(info);
        assertThatThrownBy(() -> service.validateRegistrationFields(req))
                .isInstanceOf(AppException.class);
    }
}
