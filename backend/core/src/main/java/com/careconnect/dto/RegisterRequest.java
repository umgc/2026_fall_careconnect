package com.careconnect.dto;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonSubTypes;
import com.fasterxml.jackson.annotation.JsonTypeInfo;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@NoArgsConstructor
@JsonIgnoreProperties(ignoreUnknown = true)
@JsonTypeInfo(use = JsonTypeInfo.Id.NAME, property = "role", visible = true)
@JsonSubTypes({
        @JsonSubTypes.Type(value = PatientRegistration.class, name = "PATIENT"),
        @JsonSubTypes.Type(value = CaregiverRegistration.class, name = "CAREGIVER")
})
public abstract class RegisterRequest {
    private String name;
    private String email;
    private String password;
    private String role;
    private String verificationBaseUrl;
}
