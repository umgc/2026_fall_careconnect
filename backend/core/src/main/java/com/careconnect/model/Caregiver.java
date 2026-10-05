package com.careconnect.model;

import jakarta.persistence.*;
import lombok.*;

@Entity
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class Caregiver {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    private String firstName;
    private String lastName;
    private String dob;

    @Column(name = "gender")
    @Enumerated(EnumType.STRING)
    private Gender gender;

    private String email;
    private String phone;

    @Embedded
    private ProfessionalInfo professional;

    @Embedded
    private Address address;

    private String caregiverType;

    @OneToOne(cascade = CascadeType.ALL)
    @JoinColumn(name = "user_id")
    private User user;

    public String getCaregiverType() {
        return caregiverType;
    }

    public void setCaregiverType(String caregiverType) {
        this.caregiverType = caregiverType;
    }
}