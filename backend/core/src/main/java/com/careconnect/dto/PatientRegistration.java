package com.careconnect.dto;

import com.careconnect.model.Gender;
import lombok.Data;
import lombok.EqualsAndHashCode;
import lombok.NoArgsConstructor;

@Data
@NoArgsConstructor
@EqualsAndHashCode(callSuper = true)
public class PatientRegistration extends RegisterRequest {
    private String firstName;
    private String lastName;
    private String phone;
    private AddressDto address;
    private String dob;
    private Gender gender;
    private Long caregiverId;
    private Long familyMemberId;
    private String relationship;
}