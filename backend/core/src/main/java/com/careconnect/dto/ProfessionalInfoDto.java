package com.careconnect.dto;

public class ProfessionalInfoDto {
    private String licenseNumber;
    private String issuingState;
    private int yearsExperience;
    private String organization;
    private String practiceName;

    public String getLicenseNumber() {
        return licenseNumber;
    }

    public void setLicenseNumber(String licenseNumber) {
        this.licenseNumber = licenseNumber;
    }

    public String getIssuingState() {
        return issuingState;
    }

    public void setIssuingState(String issuingState) {
        this.issuingState = issuingState;
    }

    public int getYearsExperience() {
        return yearsExperience;
    }

    public void setYearsExperience(int yearsExperience) {
        this.yearsExperience = yearsExperience;
    }

    public String getOrganization() {
        return organization;
    }

    public void setOrganization(String organization) {
        this.organization = organization;
    }

    public String getPracticeName() {
        return practiceName;
    }

    public void setPracticeName(String practiceName) {
        this.practiceName = practiceName;
    }

    /** Resolved practice/org label: organization, else practiceName. */
    public String resolvedOrganization() {
        if (organization != null && !organization.isBlank()) {
            return organization.trim();
        }
        if (practiceName != null && !practiceName.isBlank()) {
            return practiceName.trim();
        }
        return null;
    }
}