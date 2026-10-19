package com.careconnect.repository;

import com.careconnect.model.DocumentRequirementStatus;
import com.careconnect.model.DocumentRequirementStatus.ComplianceStatus;
import com.careconnect.model.DocumentRequirementStatus.SubjectType;
import com.careconnect.model.DocumentStatusHistory;
import com.careconnect.model.StructuredDocumentEntry;
import com.careconnect.model.UserFile;
import com.careconnect.model.UserFile.FileCategory;
import com.careconnect.model.UserFile.OwnerType;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.test.context.ActiveProfiles;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;
import java.util.Set;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.catchThrowable;

/**
 * Persistence-layer tests for the compliance tracking tables and the bulk
 * queries that feed the dashboard: requirement-status lookups per subject and
 * document type, the append-only status history (ordering + immutability), and
 * the new aggregate queries on {@link UserFileRepository} and
 * {@link StructuredDocumentEntryRepository}.
 */
@DataJpaTest
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@ActiveProfiles("test")
class DocumentComplianceRepositoryTest {

    @Autowired
    private DocumentRequirementStatusRepository statusRepo;
    @Autowired
    private DocumentStatusHistoryRepository historyRepo;
    @Autowired
    private UserFileRepository fileRepo;
    @Autowired
    private StructuredDocumentEntryRepository entryRepo;

    private static List<Throwable> rootCauseChain(Throwable t) {
        java.util.ArrayList<Throwable> chain = new java.util.ArrayList<>();
        while (t != null && !chain.contains(t)) {
            chain.add(t);
            t = t.getCause();
        }
        return chain;
    }

    @BeforeEach
    void clean() {
        historyRepo.deleteAllInBatch();
        statusRepo.deleteAllInBatch();
        entryRepo.deleteAllInBatch();
        fileRepo.deleteAllInBatch();
    }

    private DocumentRequirementStatus saveStatus(SubjectType subjectType, Long subjectId,
                                                 FileCategory type, ComplianceStatus status) {
        return statusRepo.saveAndFlush(DocumentRequirementStatus.builder()
                .subjectType(subjectType)
                .subjectId(subjectId)
                .documentType(type)
                .status(status)
                .notes("test")
                .updatedBy(1L)
                .build());
    }

    private DocumentStatusHistory saveHistory(SubjectType subjectType, Long subjectId,
                                              FileCategory type, ComplianceStatus previous,
                                              ComplianceStatus next, LocalDateTime at) {
        return historyRepo.saveAndFlush(DocumentStatusHistory.builder()
                .subjectType(subjectType)
                .subjectId(subjectId)
                .documentType(type)
                .previousStatus(previous)
                .newStatus(next)
                .changedBy(1L)
                .reason("test reason")
                .changedAt(at)
                .build());
    }

    private UserFile saveFile(Long ownerId, OwnerType ownerType, FileCategory category,
                              Long patientId, boolean active) {
        return fileRepo.saveAndFlush(UserFile.builder()
                .filename("f-" + System.nanoTime())
                .originalFilename("doc.pdf")
                .contentType("application/pdf")
                .fileSize(4L)
                .ownerId(ownerId)
                .ownerType(ownerType)
                .fileCategory(category)
                .patientId(patientId)
                .storageType(UserFile.StorageType.DATABASE)
                .isActive(active)
                .build());
    }

    // ─────────────── Requirement status lookups ───────────────

    private StructuredDocumentEntry saveEntry(FileCategory type, Long employeeUserId, Long patientId,
                                              boolean active) {
        return entryRepo.saveAndFlush(StructuredDocumentEntry.builder()
                .userFileId(1L)
                .documentType(type)
                .employeeUserId(employeeUserId)
                .patientId(patientId)
                .fieldsJson("{}")
                .isActive(active)
                .build());
    }

    @Test
    @DisplayName("Status: lookup by subject + document type returns the tracked record")
    void findBySubjectAndDocumentType() {
        saveStatus(SubjectType.EMPLOYEE, 2L, FileCategory.CERTIFICATION, ComplianceStatus.IN_PROGRESS);
        saveStatus(SubjectType.EMPLOYEE, 2L, FileCategory.TAX_FORM, ComplianceStatus.MISSING);

        Optional<DocumentRequirementStatus> found =
                statusRepo.findBySubjectTypeAndSubjectIdAndDocumentType(
                        SubjectType.EMPLOYEE, 2L, FileCategory.CERTIFICATION);

        assertThat(found).isPresent();
        assertThat(found.get().getStatus()).isEqualTo(ComplianceStatus.IN_PROGRESS);
    }

    @Test
    @DisplayName("Status: per-subject listing excludes other subjects and subject types")
    void findBySubjectTypeAndSubjectId_scopedToSubject() {
        saveStatus(SubjectType.EMPLOYEE, 2L, FileCategory.CERTIFICATION, ComplianceStatus.COMPLETE);
        saveStatus(SubjectType.EMPLOYEE, 3L, FileCategory.CERTIFICATION, ComplianceStatus.MISSING);
        // Same numeric id, different subject type — must not leak across:
        saveStatus(SubjectType.CARE_CIRCLE, 2L, FileCategory.CONSENT_FORM, ComplianceStatus.MISSING);

        List<DocumentRequirementStatus> employee2 =
                statusRepo.findBySubjectTypeAndSubjectId(SubjectType.EMPLOYEE, 2L);

        assertThat(employee2).hasSize(1);
        assertThat(employee2.get(0).getDocumentType()).isEqualTo(FileCategory.CERTIFICATION);
    }

    @Test
    @DisplayName("Status: findBySubjectType supports dashboard aggregation across subjects")
    void findBySubjectType_returnsAllForType() {
        saveStatus(SubjectType.EMPLOYEE, 2L, FileCategory.CERTIFICATION, ComplianceStatus.COMPLETE);
        saveStatus(SubjectType.EMPLOYEE, 3L, FileCategory.TAX_FORM, ComplianceStatus.REJECTED);
        saveStatus(SubjectType.CARE_CIRCLE, 7L, FileCategory.CONSENT_FORM, ComplianceStatus.MISSING);

        assertThat(statusRepo.findBySubjectType(SubjectType.EMPLOYEE)).hasSize(2);
        assertThat(statusRepo.findBySubjectType(SubjectType.CARE_CIRCLE)).hasSize(1);
    }

    // ─────────────── Audit history ───────────────

    @Test
    @DisplayName("Status: one row per (subject, document type) — duplicates are rejected by the DB")
    void duplicateRequirementRow_rejected() {
        saveStatus(SubjectType.EMPLOYEE, 2L, FileCategory.CERTIFICATION, ComplianceStatus.MISSING);

        Throwable thrown = catchThrowable(() ->
                saveStatus(SubjectType.EMPLOYEE, 2L, FileCategory.CERTIFICATION,
                        ComplianceStatus.COMPLETE));

        assertThat(thrown).isNotNull(); // unique constraint uq_doc_requirement_subject
    }

    @Test
    @DisplayName("History: full trail is returned newest first")
    void history_orderedNewestFirst() {
        LocalDateTime base = LocalDateTime.now();
        saveHistory(SubjectType.EMPLOYEE, 2L, FileCategory.CERTIFICATION,
                null, ComplianceStatus.IN_PROGRESS, base.minusDays(2));
        saveHistory(SubjectType.EMPLOYEE, 2L, FileCategory.CERTIFICATION,
                ComplianceStatus.IN_PROGRESS, ComplianceStatus.COMPLETE, base.minusDays(1));
        saveHistory(SubjectType.EMPLOYEE, 2L, FileCategory.CERTIFICATION,
                ComplianceStatus.COMPLETE, ComplianceStatus.REJECTED, base);

        List<DocumentStatusHistory> trail =
                historyRepo.findBySubjectTypeAndSubjectIdOrderByChangedAtDesc(SubjectType.EMPLOYEE, 2L);

        assertThat(trail).hasSize(3);
        assertThat(trail.get(0).getNewStatus()).isEqualTo(ComplianceStatus.REJECTED);
        assertThat(trail.get(2).getNewStatus()).isEqualTo(ComplianceStatus.IN_PROGRESS);
        assertThat(trail.get(2).getPreviousStatus()).isNull();
        // Every entry carries the full audit payload
        assertThat(trail).allMatch(h -> h.getChangedBy() != null
                && h.getReason() != null && h.getChangedAt() != null);
    }

    @Test
    @DisplayName("History: document-type filter narrows the trail")
    void history_documentTypeFilter() {
        LocalDateTime now = LocalDateTime.now();
        saveHistory(SubjectType.EMPLOYEE, 2L, FileCategory.CERTIFICATION,
                null, ComplianceStatus.IN_PROGRESS, now);
        saveHistory(SubjectType.EMPLOYEE, 2L, FileCategory.TAX_FORM,
                null, ComplianceStatus.COMPLETE, now);

        List<DocumentStatusHistory> certOnly =
                historyRepo.findBySubjectTypeAndSubjectIdAndDocumentTypeOrderByChangedAtDesc(
                        SubjectType.EMPLOYEE, 2L, FileCategory.CERTIFICATION);

        assertThat(certOnly).hasSize(1);
        assertThat(certOnly.get(0).getDocumentType()).isEqualTo(FileCategory.CERTIFICATION);
    }

    @Test
    @DisplayName("History: records are immutable — updates are blocked")
    void history_updateBlocked() {
        DocumentStatusHistory saved = saveHistory(SubjectType.EMPLOYEE, 2L,
                FileCategory.CERTIFICATION, null, ComplianceStatus.IN_PROGRESS, LocalDateTime.now());

        saved.setReason("tampered");
        Throwable thrown = catchThrowable(() -> historyRepo.saveAndFlush(saved));

        assertThat(thrown).isNotNull();
        assertThat(rootCauseChain(thrown))
                .anyMatch(t -> t instanceof UnsupportedOperationException);
    }

    @Test
    @DisplayName("History: records are immutable — deletes are blocked")
    void history_deleteBlocked() {
        DocumentStatusHistory saved = saveHistory(SubjectType.EMPLOYEE, 2L,
                FileCategory.CERTIFICATION, null, ComplianceStatus.IN_PROGRESS, LocalDateTime.now());

        Throwable thrown = catchThrowable(() -> {
            historyRepo.delete(saved);
            historyRepo.flush();
        });

        assertThat(thrown).isNotNull();
        assertThat(rootCauseChain(thrown))
                .anyMatch(t -> t instanceof UnsupportedOperationException);
    }

    // ─────────────── Dashboard bulk queries ───────────────

    @Test
    @DisplayName("Files: owner-type bulk query returns active intake docs across all employees only")
    void files_bulkByOwnerType() {
        saveFile(2L, OwnerType.CAREGIVER, FileCategory.CERTIFICATION, null, true);
        saveFile(3L, OwnerType.CAREGIVER, FileCategory.TAX_FORM, null, true);
        saveFile(3L, OwnerType.CAREGIVER, FileCategory.CERTIFICATION, null, false); // soft-deleted
        saveFile(4L, OwnerType.PATIENT, FileCategory.CERTIFICATION, null, true);    // wrong owner type
        saveFile(2L, OwnerType.CAREGIVER, FileCategory.MEDICAL_RECORD, null, true); // not intake

        List<UserFile> intake = fileRepo.findByOwnerTypeAndFileCategoryInAndIsActiveTrue(
                OwnerType.CAREGIVER,
                DocumentRequirementStatus.REQUIRED_DOCUMENTS
                        .get(DocumentRequirementStatus.SubjectType.EMPLOYEE));

        assertThat(intake).hasSize(2);
        assertThat(intake).extracting(UserFile::getOwnerId).containsExactlyInAnyOrder(2L, 3L);
    }

    @Test
    @DisplayName("Files: patient-linked bulk query excludes unlinked and inactive files")
    void files_bulkByPatientLinked() {
        Set<FileCategory> careCircleDocs = Set.of(
                FileCategory.CONSENT_FORM, FileCategory.INSURANCE_DOCUMENT,
                FileCategory.CARE_PLAN, FileCategory.EMERGENCY_CONTACT);

        saveFile(1L, OwnerType.PATIENT, FileCategory.CONSENT_FORM, 7L, true);
        saveFile(2L, OwnerType.CAREGIVER, FileCategory.CARE_PLAN, 8L, true);
        saveFile(1L, OwnerType.PATIENT, FileCategory.CONSENT_FORM, null, true); // not patient-linked
        saveFile(1L, OwnerType.PATIENT, FileCategory.CONSENT_FORM, 7L, false);  // soft-deleted

        List<UserFile> linked =
                fileRepo.findByPatientIdIsNotNullAndFileCategoryInAndIsActiveTrue(careCircleDocs);

        assertThat(linked).hasSize(2);
        assertThat(linked).extracting(UserFile::getPatientId).containsExactlyInAnyOrder(7L, 8L);
    }

    @Test
    @DisplayName("Entries: employee/patient bulk queries partition by context and skip inactive")
    void entries_bulkByContext() {
        saveEntry(FileCategory.CERTIFICATION, 2L, null, true);
        saveEntry(FileCategory.BACKGROUND_CHECK, 3L, null, true);
        saveEntry(FileCategory.CONSENT_FORM, null, 7L, true);
        saveEntry(FileCategory.CERTIFICATION, 2L, null, false); // inactive

        List<StructuredDocumentEntry> employeeEntries =
                entryRepo.findByEmployeeUserIdIsNotNullAndIsActiveTrue();
        List<StructuredDocumentEntry> patientEntries =
                entryRepo.findByPatientIdIsNotNullAndIsActiveTrue();

        assertThat(employeeEntries).hasSize(2);
        assertThat(patientEntries).hasSize(1);
        assertThat(patientEntries.get(0).getPatientId()).isEqualTo(7L);
    }
}
