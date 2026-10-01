package com.careconnect.model;


import jakarta.persistence.Embeddable;
import lombok.*;

@Embeddable
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class ProfessionalInfo {
    private String licenseNumber;
    private String issuingState;
    private Integer yearsExperience;
}