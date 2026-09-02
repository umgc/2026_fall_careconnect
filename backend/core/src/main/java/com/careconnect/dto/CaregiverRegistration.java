package com.careconnect.dto;

import com.careconnect.model.Gender;
import lombok.Data;
import lombok.EqualsAndHashCode;
import lombok.NoArgsConstructor;

@Data
@NoArgsConstructor
@EqualsAndHashCode(callSuper = true)
public class CaregiverRegistration extends RegisterRequest {

    private String firstName;
    private String lastName;
    private String dob;
    private Gender gender;
    private String phone;
    private ProfessionalInfoDto professional;
    private AddressDto address;
    private LoginRequest credentials;
    private String caregiverType;
    private String planId;
}