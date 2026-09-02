package com.careconnect.repository;

import com.careconnect.model.DocumentRequirementStatus;
import com.careconnect.model.UserFile;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

@Repository
public interface DocumentRequirementStatusRepository
        extends JpaRepository<DocumentRequirementStatus, Long> {

    /**
     * All tracked requirement statuses for one subject's checklist.
     */
    List<DocumentRequirementStatus> findBySubjectTypeAndSubjectId(
            DocumentRequirementStatus.SubjectType subjectType, Long subjectId);

    /**
     * The tracked status of a single required document, if it has ever transitioned.
     */
    Optional<DocumentRequirementStatus> findBySubjectTypeAndSubjectIdAndDocumentType(
            DocumentRequirementStatus.SubjectType subjectType, Long subjectId,
            UserFile.FileCategory documentType);

    /**
     * All tracked statuses for one subject type (dashboard aggregation).
     */
    List<DocumentRequirementStatus> findBySubjectType(
            DocumentRequirementStatus.SubjectType subjectType);
}
