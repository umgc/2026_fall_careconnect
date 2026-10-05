package com.careconnect.repository;

import com.careconnect.model.DocumentRequirementStatus;
import com.careconnect.model.DocumentStatusHistory;
import com.careconnect.model.UserFile;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;

@Repository
public interface DocumentStatusHistoryRepository
        extends JpaRepository<DocumentStatusHistory, Long> {

    /**
     * Full audit trail for a subject, newest first.
     */
    List<DocumentStatusHistory> findBySubjectTypeAndSubjectIdOrderByChangedAtDesc(
            DocumentRequirementStatus.SubjectType subjectType, Long subjectId);

    /**
     * Audit trail for a single required document of a subject, newest first.
     */
    List<DocumentStatusHistory> findBySubjectTypeAndSubjectIdAndDocumentTypeOrderByChangedAtDesc(
            DocumentRequirementStatus.SubjectType subjectType, Long subjectId,
            UserFile.FileCategory documentType);
}
