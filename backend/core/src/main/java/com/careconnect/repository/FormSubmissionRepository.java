package com.careconnect.repository;

import com.careconnect.model.UserFile;
import com.careconnect.model.forms.FormSubmission;
import com.careconnect.model.forms.FormType;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

@Repository
public interface FormSubmissionRepository extends JpaRepository<FormSubmission, Long> {

    List<FormSubmission> findByOwnerIdAndOwnerType(Long ownerId, UserFile.OwnerType ownerType);

    List<FormSubmission> findByOwnerIdAndOwnerTypeAndFormType(Long ownerId, UserFile.OwnerType ownerType, FormType formType);

    List<FormSubmission> findByStatus(FormSubmission.SubmissionStatus status);

    Optional<FormSubmission> findByUserFileId(Long userFileId);
}
