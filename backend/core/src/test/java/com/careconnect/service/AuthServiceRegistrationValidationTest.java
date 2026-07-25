package com.careconnect.service;

import com.careconnect.dto.CaregiverRegistration;
import com.careconnect.dto.ProfessionalInfoDto;
import com.careconnect.exception.AppException;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;

import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;

class AuthServiceRegistrationValidationTest {

    @Test
    void professionalRequiresOrganizationAndLicense() {
        final AuthService service = mockAuthService();
        final CaregiverRegistration req = new CaregiverRegistration();
        req.setCaregiverType("Professional");
        req.setProfessional(new ProfessionalInfoDto());

        assertThatThrownBy(() -> service.validateRegistrationFields(req))
                .isInstanceOf(AppException.class)
                .extracting(ex -> ((AppException) ex).getStatus())
                .isEqualTo(HttpStatus.BAD_REQUEST);
    }

    @Test
    void nonProfessionalRejectsOrganization() {
        final AuthService service = mockAuthService();
        final CaregiverRegistration req = new CaregiverRegistration();
        req.setCaregiverType("Family Member");
        final ProfessionalInfoDto info = new ProfessionalInfoDto();
        info.setOrganization("Acme Care");
        req.setProfessional(info);

        assertThatThrownBy(() -> service.validateRegistrationFields(req))
                .isInstanceOf(AppException.class);
    }

    @Test
    void professionalWithOrgAndLicensePasses() {
        final AuthService service = mockAuthService();
        final CaregiverRegistration req = new CaregiverRegistration();
        req.setCaregiverType("Professional");
        final ProfessionalInfoDto info = new ProfessionalInfoDto();
        info.setOrganization("Oak Clinic");
        info.setLicenseNumber("RN-123");
        req.setProfessional(info);
        assertDoesNotThrow(() -> service.validateRegistrationFields(req));
    }

    @Test
    void professionalAcceptsPracticeNameAlias() {
        final CaregiverRegistration req = new CaregiverRegistration();
        req.setCaregiverType("professional");
        final ProfessionalInfoDto info = new ProfessionalInfoDto();
        info.setPracticeName("Riverside Practice");
        info.setLicenseNumber("LIC-9");
        req.setProfessional(info);
        assertDoesNotThrow(() -> RegistrationValidation.validateCaregiverRegistration(req));
    }

    private static AuthService mockAuthService() {
        // Concrete instance with nulls is fine — validateRegistrationFields uses no collaborators
        return new AuthService();
    }
}
