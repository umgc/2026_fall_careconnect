package com.careconnect.model;


import jakarta.persistence.Embeddable;
import lombok.*;

@Embeddable
@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class ProfessionalInfo {
	private String licenseNumber;
	private String issuingState;
	private Integer yearsExperience;
	private String organization;
	private String practiceName;

	public ProfessionalInfo(
			String licenseNumber,
			String issuingState,
			Integer yearsExperience) {
		this.licenseNumber = licenseNumber;
		this.issuingState = issuingState;
		this.yearsExperience = yearsExperience;
	}
}