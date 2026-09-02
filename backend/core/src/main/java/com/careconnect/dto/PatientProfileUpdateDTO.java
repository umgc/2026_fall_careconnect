package com.careconnect.dto;

import com.careconnect.model.Gender;

import java.util.List;

/**
 * DTO for updating patient profile information
 * This includes optional fields that can be updated after registration
 */
public class PatientProfileUpdateDTO {

    private String firstName;
    private String lastName;
    private String phone;
    private String dob;
    private Gender gender;
    private AddressDto address;
    private String relationship;

    // In-Home personalization fields
    private String likes;
    private String dislikes;
    private String habits;
    private String phobias;
    private String preferredCommunicationMethod;

    // Allergies are managed separately through the allergy endpoints
    // but can be included here for bulk profile updates if needed
    private List<AllergyDTO> allergies;

    public PatientProfileUpdateDTO() {
    }

    public String getFirstName() {
        return firstName;
    }

    public void setFirstName(String firstName) {
        this.firstName = firstName;
    }

    public String getLastName() {
        return lastName;
    }

    public void setLastName(String lastName) {
        this.lastName = lastName;
    }

    public String getPhone() {
        return phone;
    }

    public void setPhone(String phone) {
        this.phone = phone;
    }

    public String getDob() {
        return dob;
    }

    public void setDob(String dob) {
        this.dob = dob;
    }

    public Gender getGender() {
        return gender;
    }

    public void setGender(Gender gender) {
        this.gender = gender;
    }

    public AddressDto getAddress() {
        return address;
    }

    public void setAddress(AddressDto address) {
        this.address = address;
    }

    public String getRelationship() {
        return relationship;
    }

    public void setRelationship(String relationship) {
        this.relationship = relationship;
    }

    public String getLikes() {
        return likes;
    }

    public void setLikes(String likes) {
        this.likes = likes;
    }

    public String getDislikes() {
        return dislikes;
    }

    public void setDislikes(String dislikes) {
        this.dislikes = dislikes;
    }

    public String getHabits() {
        return habits;
    }

    public void setHabits(String habits) {
        this.habits = habits;
    }

    public String getPhobias() {
        return phobias;
    }

    public void setPhobias(String phobias) {
        this.phobias = phobias;
    }

    public String getPreferredCommunicationMethod() {
        return preferredCommunicationMethod;
    }

    public void setPreferredCommunicationMethod(String preferredCommunicationMethod) {
        this.preferredCommunicationMethod = preferredCommunicationMethod;
    }

    public List<AllergyDTO> getAllergies() {
        return allergies;
    }

    public void setAllergies(List<AllergyDTO> allergies) {
        this.allergies = allergies;
    }
}
