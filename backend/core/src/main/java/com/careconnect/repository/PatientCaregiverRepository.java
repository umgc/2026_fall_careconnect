package com.careconnect.repository;

import com.careconnect.model.CaregiverPatientLink;
import com.careconnect.model.User;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;

@Repository
public interface PatientCaregiverRepository extends JpaRepository<CaregiverPatientLink, Long> {

    boolean existsByCaregiverUserAndPatientUserAndStatus(
            User caregiverUser, User patientUser, CaregiverPatientLink.LinkStatus status);

    List<CaregiverPatientLink> findByCaregiverUser(User caregiverUser);

    List<CaregiverPatientLink> findByPatientUser(User patientUser);
}