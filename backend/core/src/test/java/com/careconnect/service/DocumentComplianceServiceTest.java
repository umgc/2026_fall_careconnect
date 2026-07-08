package com.careconnect.service;

import com.careconnect.dto.ComplianceSummaryDTO;
import com.careconnect.dto.DocumentChecklistDTO;
import com.careconnect.dto.DocumentChecklistItemDTO;
import com.careconnect.dto.DocumentStatusHistoryDTO;
import com.careconnect.dto.DocumentStatusUpdateRequest;
import com.careconnect.dto.MissingDocumentDTO;
import com.careconnect.model.DocumentRequirementStatus;
import com.careconnect.model.DocumentRequirementStatus.ComplianceStatus;
import com.careconnect.model.DocumentRequirementStatus.SubjectType;
import com.careconnect.model.DocumentStatusHistory;
import com.careconnect.model.Patient;
import com.careconnect.model.StructuredDocumentEntry;
import com.careconnect.model.User;
import com.careconnect.model.UserFile;
import com.careconnect.model.UserFile.FileCategory;
import com.careconnect.model.UserFile.OwnerType;
import com.careconnect.repository.DocumentRequirementStatusRepository;
import com.careconnect.repository.DocumentStatusHistoryRepository;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.StructuredDocumentEntryRepository;
import com.careconnect.repository.UserFileRepository;
import com.careconnect.repository.UserRepository;
import com.careconnect.security.Role;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.MockitoAnnotations;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

/**
 * Unit tests for {@link DocumentComplianceService}: checklist generation and
 * status derivation, missing-document detection, audited status transitions,
 * dashboard aggregation and CSV export.
 */
class DocumentComplianceServiceTest {

    private static final Long EMPLOYEE_ID = 2L;
    private static final Long PATIENT_ID = 7L;
    private static final int EMPLOYEE_REQUIRED =
            DocumentRequirementStatus.REQUIRED_DOCUMENTS.get(SubjectType.EMPLOYEE).size(); // 9
    private static final int CARE_CIRCLE_REQUIRED =
            DocumentRequirementStatus.REQUIRED_DOCUMENTS.get(SubjectType.CARE_CIRCLE).size(); // 4

    @Mock private DocumentRequirementStatusRepository statusRepository;
    @Mock private DocumentStatusHistoryRepository historyRepository;
    @Mock private UserFileRepository userFileRepository;
    @Mock private StructuredDocumentEntryRepository structuredEntryRepository;
    @Mock private UserRepository userRepository;
    @Mock private PatientRepository patientRepository;

    private DocumentComplianceService service;

    private User employee;
    private Patient patient;

    @BeforeEach
    void setUp() {
        MockitoAnnotations.openMocks(this);
        service = new DocumentComplianceService(statusRepository, historyRepository,
                userFileRepository, structuredEntryRepository, userRepository, patientRepository);

        employee = new User();
        employee.setId(EMPLOYEE_ID);
        employee.setName("Jane Caregiver");
        employee.setEmail("jane@test.com");
        employee.setRole(Role.CAREGIVER);

        patient = Patient.builder().id(PATIENT_ID).firstName("Pat").lastName("Recipient").build();
    }

    // ==================== helpers ====================

    private UserFile file(Long id, FileCategory category, Long ownerId, OwnerType ownerType,
                          Long patientId, String originalFilename, LocalDateTime uploadedAt) {
        return UserFile.builder()
                .id(id)
                .filename("f" + id)
                .originalFilename(originalFilename)
                .fileCategory(category)
                .ownerId(ownerId)
                .ownerType(ownerType)
                .patientId(patientId)
                .storageType(UserFile.StorageType.DATABASE)
                .uploadedAt(uploadedAt)
                .isActive(true)
                .build();
    }

    private StructuredDocumentEntry entry(Long id, FileCategory type, Long employeeUserId, Long patientId) {
        return StructuredDocumentEntry.builder()
                .id(id)
                .userFileId(100L + id)
                .documentType(type)
                .employeeUserId(employeeUserId)
                .patientId(patientId)
                .isActive(true)
                .build();
    }

    private DocumentRequirementStatus record(SubjectType subjectType, Long subjectId,
                                             FileCategory type, ComplianceStatus status) {
        return DocumentRequirementStatus.builder()
                .id(50L)
                .subjectType(subjectType)
                .subjectId(subjectId)
                .documentType(type)
                .status(status)
                .notes("recorded reason")
                .updatedBy(9L)
                .build();
    }

    private void stubEmployeeChecklist(List<DocumentRequirementStatus> records,
                                       List<UserFile> files,
                                       List<StructuredDocumentEntry> entries) {
        when(statusRepository.findBySubjectTypeAndSubjectId(SubjectType.EMPLOYEE, EMPLOYEE_ID))
                .thenReturn(records);
        when(userFileRepository.findByOwnerIdAndOwnerTypeAndFileCategoryInAndIsActiveTrue(
                eq(EMPLOYEE_ID), eq(OwnerType.CAREGIVER), anyCollection()))
                .thenReturn(files);
        when(structuredEntryRepository.findByEmployeeUserIdAndIsActiveTrue(EMPLOYEE_ID))
                .thenReturn(entries);
        when(userRepository.findById(EMPLOYEE_ID)).thenReturn(Optional.of(employee));
    }

    private DocumentChecklistItemDTO itemFor(DocumentChecklistDTO checklist, FileCategory type) {
        return checklist.getItems().stream()
                .filter(i -> i.getDocumentType().equals(type.name()))
                .findFirst()
                .orElseThrow(() -> new AssertionError("Item not found: " + type));
    }

    // ==================== CHECKLIST GENERATION ====================

    @Test
    @DisplayName("Checklist: employee statuses derive from files, entries and recorded transitions")
    void checklist_employee_derivesStatusesFromEvidence() {
        LocalDateTime now = LocalDateTime.now();
        stubEmployeeChecklist(
                // Explicit tracked state wins over derivation:
                List.of(record(SubjectType.EMPLOYEE, EMPLOYEE_ID,
                        FileCategory.EMPLOYMENT_CONTRACT, ComplianceStatus.REJECTED)),
                // Uploaded-only evidence -> IN_PROGRESS:
                List.of(file(10L, FileCategory.CERTIFICATION, EMPLOYEE_ID, OwnerType.CAREGIVER,
                        null, "cpr.pdf", now)),
                // Digitized structured record -> COMPLETE:
                List.of(entry(1L, FileCategory.BACKGROUND_CHECK, EMPLOYEE_ID, null)));

        DocumentChecklistDTO checklist = service.getChecklist(SubjectType.EMPLOYEE, EMPLOYEE_ID);

        assertEquals(EMPLOYEE_REQUIRED, checklist.getRequiredCount());
        assertEquals("Jane Caregiver", checklist.getSubjectName());

        DocumentChecklistItemDTO uploaded = itemFor(checklist, FileCategory.CERTIFICATION);
        assertEquals("IN_PROGRESS", uploaded.getStatus());
        assertEquals(1, uploaded.getFileCount());
        assertFalse(uploaded.isTracked());
        assertEquals("cpr.pdf", uploaded.getLatestFilename());

        DocumentChecklistItemDTO digitized = itemFor(checklist, FileCategory.BACKGROUND_CHECK);
        assertEquals("COMPLETE", digitized.getStatus());
        assertTrue(digitized.isHasStructuredEntry());

        DocumentChecklistItemDTO rejected = itemFor(checklist, FileCategory.EMPLOYMENT_CONTRACT);
        assertEquals("REJECTED", rejected.getStatus());
        assertTrue(rejected.isTracked());
        assertEquals("recorded reason", rejected.getNotes());

        DocumentChecklistItemDTO missing = itemFor(checklist, FileCategory.TAX_FORM);
        assertEquals("MISSING", missing.getStatus());
        assertEquals(0, missing.getFileCount());

        assertEquals(1, checklist.getCompleteCount());
        assertEquals(1, checklist.getInProgressCount());
        assertEquals(1, checklist.getRejectedCount());
        assertEquals(EMPLOYEE_REQUIRED - 3, checklist.getMissingCount());
        assertEquals(100 / EMPLOYEE_REQUIRED, checklist.getPercentComplete());
    }

    @Test
    @DisplayName("Checklist: care-circle context queries by patient and uses the care-circle document set")
    void checklist_careCircle_usesPatientContext() {
        when(statusRepository.findBySubjectTypeAndSubjectId(SubjectType.CARE_CIRCLE, PATIENT_ID))
                .thenReturn(List.of());
        when(userFileRepository.findByPatientIdAndFileCategoryInAndIsActiveTrue(
                eq(PATIENT_ID), anyCollection()))
                .thenReturn(List.of(file(11L, FileCategory.CONSENT_FORM, 1L, OwnerType.PATIENT,
                        PATIENT_ID, "consent.pdf", LocalDateTime.now())));
        when(structuredEntryRepository.findByPatientIdAndIsActiveTrue(PATIENT_ID))
                .thenReturn(List.of(entry(2L, FileCategory.INSURANCE_DOCUMENT, null, PATIENT_ID)));
        when(patientRepository.findById(PATIENT_ID)).thenReturn(Optional.of(patient));

        DocumentChecklistDTO checklist = service.getChecklist(SubjectType.CARE_CIRCLE, PATIENT_ID);

        assertEquals(CARE_CIRCLE_REQUIRED, checklist.getRequiredCount());
        assertEquals("Pat Recipient", checklist.getSubjectName());
        assertEquals("IN_PROGRESS", itemFor(checklist, FileCategory.CONSENT_FORM).getStatus());
        assertEquals("COMPLETE", itemFor(checklist, FileCategory.INSURANCE_DOCUMENT).getStatus());
        assertEquals("MISSING", itemFor(checklist, FileCategory.CARE_PLAN).getStatus());
        verify(userFileRepository).findByPatientIdAndFileCategoryInAndIsActiveTrue(
                eq(PATIENT_ID), anyCollection());
        verify(userFileRepository, never())
                .findByOwnerIdAndOwnerTypeAndFileCategoryInAndIsActiveTrue(any(), any(), anyCollection());
    }

    @Test
    @DisplayName("Checklist: no documents at all -> every required item MISSING, 0% complete")
    void checklist_noDocuments_allMissing() {
        stubEmployeeChecklist(List.of(), List.of(), List.of());

        DocumentChecklistDTO checklist = service.getChecklist(SubjectType.EMPLOYEE, EMPLOYEE_ID);

        assertEquals(EMPLOYEE_REQUIRED, checklist.getMissingCount());
        assertEquals(0, checklist.getPercentComplete());
        assertTrue(checklist.getItems().stream().allMatch(i -> i.getStatus().equals("MISSING")));
    }

    @Test
    @DisplayName("Checklist: duplicate uploads of the same type count on one item; latest file wins")
    void checklist_duplicateDocumentTypes_aggregateOnOneItem() {
        LocalDateTime older = LocalDateTime.now().minusDays(2);
        LocalDateTime newer = LocalDateTime.now();
        stubEmployeeChecklist(List.of(), List.of(
                file(10L, FileCategory.CERTIFICATION, EMPLOYEE_ID, OwnerType.CAREGIVER, null, "old.pdf", older),
                file(11L, FileCategory.CERTIFICATION, EMPLOYEE_ID, OwnerType.CAREGIVER, null, "new.pdf", newer)),
                List.of());

        DocumentChecklistDTO checklist = service.getChecklist(SubjectType.EMPLOYEE, EMPLOYEE_ID);

        DocumentChecklistItemDTO item = itemFor(checklist, FileCategory.CERTIFICATION);
        assertEquals(2, item.getFileCount());
        assertEquals("new.pdf", item.getLatestFilename());
        assertEquals(11L, item.getLatestFileId());
        // Still exactly one checklist row per required document type
        assertEquals(EMPLOYEE_REQUIRED, checklist.getItems().size());
    }

    @Test
    @DisplayName("Checklist: rejected recorded state is not overridden by existing evidence")
    void checklist_rejectedRecord_winsOverEvidence() {
        stubEmployeeChecklist(
                List.of(record(SubjectType.EMPLOYEE, EMPLOYEE_ID,
                        FileCategory.CERTIFICATION, ComplianceStatus.REJECTED)),
                List.of(file(10L, FileCategory.CERTIFICATION, EMPLOYEE_ID, OwnerType.CAREGIVER,
                        null, "cpr.pdf", LocalDateTime.now())),
                List.of(entry(1L, FileCategory.CERTIFICATION, EMPLOYEE_ID, null)));

        DocumentChecklistDTO checklist = service.getChecklist(SubjectType.EMPLOYEE, EMPLOYEE_ID);

        DocumentChecklistItemDTO item = itemFor(checklist, FileCategory.CERTIFICATION);
        assertEquals("REJECTED", item.getStatus());
        // Evidence is still surfaced so the coordinator can review it
        assertEquals(1, item.getFileCount());
        assertTrue(item.isHasStructuredEntry());
    }

    // ==================== MANUAL STATUS TRANSITIONS ====================

    private DocumentStatusUpdateRequest updateRequest(String status, String reason) {
        DocumentStatusUpdateRequest request = new DocumentStatusUpdateRequest();
        request.setSubjectType("EMPLOYEE");
        request.setSubjectId(EMPLOYEE_ID);
        request.setDocumentType("CERTIFICATION");
        request.setStatus(status);
        request.setReason(reason);
        return request;
    }

    @Test
    @DisplayName("updateStatus: records the transition with actor, reason and previous status")
    void updateStatus_recordsAuditedTransition() {
        when(userRepository.existsById(EMPLOYEE_ID)).thenReturn(true);
        when(statusRepository.findBySubjectTypeAndSubjectIdAndDocumentType(
                SubjectType.EMPLOYEE, EMPLOYEE_ID, FileCategory.CERTIFICATION))
                .thenReturn(Optional.empty());
        when(statusRepository.save(any(DocumentRequirementStatus.class)))
                .thenAnswer(inv -> inv.getArgument(0));
        when(historyRepository.save(any(DocumentStatusHistory.class)))
                .thenAnswer(inv -> inv.getArgument(0));
        // Refreshed checklist read after the transition:
        stubEmployeeChecklist(
                List.of(record(SubjectType.EMPLOYEE, EMPLOYEE_ID,
                        FileCategory.CERTIFICATION, ComplianceStatus.COMPLETE)),
                List.of(), List.of());

        DocumentChecklistItemDTO item = service.updateStatus(
                updateRequest("COMPLETE", "Verified against original"), employee);

        assertEquals("COMPLETE", item.getStatus());
        assertTrue(item.isTracked());

        ArgumentCaptor<DocumentRequirementStatus> savedRecord =
                ArgumentCaptor.forClass(DocumentRequirementStatus.class);
        verify(statusRepository).save(savedRecord.capture());
        assertEquals(ComplianceStatus.COMPLETE, savedRecord.getValue().getStatus());
        assertEquals("Verified against original", savedRecord.getValue().getNotes());
        assertEquals(EMPLOYEE_ID, savedRecord.getValue().getUpdatedBy());

        ArgumentCaptor<DocumentStatusHistory> savedHistory =
                ArgumentCaptor.forClass(DocumentStatusHistory.class);
        verify(historyRepository).save(savedHistory.capture());
        assertNull(savedHistory.getValue().getPreviousStatus()); // first transition
        assertEquals(ComplianceStatus.COMPLETE, savedHistory.getValue().getNewStatus());
        assertEquals(EMPLOYEE_ID, savedHistory.getValue().getChangedBy());
        assertEquals("Verified against original", savedHistory.getValue().getReason());
    }

    @Test
    @DisplayName("updateStatus: complete -> rejected preserves the previous status in the audit trail")
    void updateStatus_completeToRejected_recordsPreviousStatus() {
        DocumentRequirementStatus existing = record(SubjectType.EMPLOYEE, EMPLOYEE_ID,
                FileCategory.CERTIFICATION, ComplianceStatus.COMPLETE);
        when(userRepository.existsById(EMPLOYEE_ID)).thenReturn(true);
        when(statusRepository.findBySubjectTypeAndSubjectIdAndDocumentType(
                SubjectType.EMPLOYEE, EMPLOYEE_ID, FileCategory.CERTIFICATION))
                .thenReturn(Optional.of(existing));
        when(statusRepository.save(any())).thenAnswer(inv -> inv.getArgument(0));
        when(historyRepository.save(any())).thenAnswer(inv -> inv.getArgument(0));
        stubEmployeeChecklist(List.of(existing), List.of(), List.of());

        service.updateStatus(updateRequest("REJECTED", "Certificate expired"), employee);

        ArgumentCaptor<DocumentStatusHistory> history =
                ArgumentCaptor.forClass(DocumentStatusHistory.class);
        verify(historyRepository).save(history.capture());
        assertEquals(ComplianceStatus.COMPLETE, history.getValue().getPreviousStatus());
        assertEquals(ComplianceStatus.REJECTED, history.getValue().getNewStatus());
        assertEquals("Certificate expired", history.getValue().getReason());
    }

    @Test
    @DisplayName("updateStatus: missing reason -> rejected, nothing persisted")
    void updateStatus_missingReason_throws() {
        IllegalArgumentException ex = assertThrows(IllegalArgumentException.class,
                () -> service.updateStatus(updateRequest("REJECTED", "  "), employee));
        assertTrue(ex.getMessage().contains("reason"));
        verify(statusRepository, never()).save(any());
        verify(historyRepository, never()).save(any());
    }

    @Test
    @DisplayName("updateStatus: document type outside the required set -> rejected")
    void updateStatus_documentNotRequired_throws() {
        DocumentStatusUpdateRequest request = updateRequest("COMPLETE", "reason");
        request.setDocumentType("MEDICAL_RECORD"); // not in the employee intake set

        IllegalArgumentException ex = assertThrows(IllegalArgumentException.class,
                () -> service.updateStatus(request, employee));
        assertTrue(ex.getMessage().contains("not part of the required document set"));
        verify(statusRepository, never()).save(any());
    }

    @Test
    @DisplayName("updateStatus: unknown subject id -> rejected")
    void updateStatus_unknownSubject_throws() {
        when(userRepository.existsById(EMPLOYEE_ID)).thenReturn(false);

        IllegalArgumentException ex = assertThrows(IllegalArgumentException.class,
                () -> service.updateStatus(updateRequest("COMPLETE", "reason"), employee));
        assertTrue(ex.getMessage().contains("not found"));
        verify(historyRepository, never()).save(any());
    }

    @Test
    @DisplayName("updateStatus: invalid status value -> rejected with clear message")
    void updateStatus_invalidStatus_throws() {
        IllegalArgumentException ex = assertThrows(IllegalArgumentException.class,
                () -> service.updateStatus(updateRequest("BOGUS", "reason"), employee));
        assertTrue(ex.getMessage().contains("Invalid status"));
    }

    @Test
    @DisplayName("updateStatus: missing subjectId -> rejected")
    void updateStatus_missingSubjectId_throws() {
        DocumentStatusUpdateRequest request = updateRequest("COMPLETE", "reason");
        request.setSubjectId(null);

        assertThrows(IllegalArgumentException.class,
                () -> service.updateStatus(request, employee));
    }

    // ==================== SYSTEM TRANSITIONS (UPLOAD / DIGITIZATION) ====================

    @Test
    @DisplayName("Upload hook: missing -> in_progress, audited with uploader and filename")
    void recordDocumentUploaded_missingToInProgress() {
        when(statusRepository.findBySubjectTypeAndSubjectIdAndDocumentType(
                SubjectType.EMPLOYEE, EMPLOYEE_ID, FileCategory.CERTIFICATION))
                .thenReturn(Optional.empty());
        when(statusRepository.save(any())).thenAnswer(inv -> inv.getArgument(0));
        when(historyRepository.save(any())).thenAnswer(inv -> inv.getArgument(0));

        service.recordDocumentUploaded(
                file(10L, FileCategory.CERTIFICATION, EMPLOYEE_ID, OwnerType.CAREGIVER,
                        null, "cpr.pdf", LocalDateTime.now()),
                EMPLOYEE_ID);

        ArgumentCaptor<DocumentStatusHistory> history =
                ArgumentCaptor.forClass(DocumentStatusHistory.class);
        verify(historyRepository).save(history.capture());
        assertNull(history.getValue().getPreviousStatus());
        assertEquals(ComplianceStatus.IN_PROGRESS, history.getValue().getNewStatus());
        assertEquals(EMPLOYEE_ID, history.getValue().getChangedBy());
        assertTrue(history.getValue().getReason().contains("cpr.pdf"));

        ArgumentCaptor<DocumentRequirementStatus> saved =
                ArgumentCaptor.forClass(DocumentRequirementStatus.class);
        verify(statusRepository).save(saved.capture());
        assertEquals(10L, saved.getValue().getUserFileId());
    }

    @Test
    @DisplayName("Upload hook: rejected -> in_progress when a replacement document arrives")
    void recordDocumentUploaded_rejectedToInProgress() {
        DocumentRequirementStatus existing = record(SubjectType.EMPLOYEE, EMPLOYEE_ID,
                FileCategory.CERTIFICATION, ComplianceStatus.REJECTED);
        when(statusRepository.findBySubjectTypeAndSubjectIdAndDocumentType(
                SubjectType.EMPLOYEE, EMPLOYEE_ID, FileCategory.CERTIFICATION))
                .thenReturn(Optional.of(existing));
        when(statusRepository.save(any())).thenAnswer(inv -> inv.getArgument(0));
        when(historyRepository.save(any())).thenAnswer(inv -> inv.getArgument(0));

        service.recordDocumentUploaded(
                file(11L, FileCategory.CERTIFICATION, EMPLOYEE_ID, OwnerType.CAREGIVER,
                        null, "cpr-v2.pdf", LocalDateTime.now()),
                EMPLOYEE_ID);

        ArgumentCaptor<DocumentStatusHistory> history =
                ArgumentCaptor.forClass(DocumentStatusHistory.class);
        verify(historyRepository).save(history.capture());
        assertEquals(ComplianceStatus.REJECTED, history.getValue().getPreviousStatus());
        assertEquals(ComplianceStatus.IN_PROGRESS, history.getValue().getNewStatus());
    }

    @Test
    @DisplayName("Upload hook: complete is never downgraded; evidence link still refreshed")
    void recordDocumentUploaded_completeNotDowngraded() {
        DocumentRequirementStatus existing = record(SubjectType.EMPLOYEE, EMPLOYEE_ID,
                FileCategory.CERTIFICATION, ComplianceStatus.COMPLETE);
        when(statusRepository.findBySubjectTypeAndSubjectIdAndDocumentType(
                SubjectType.EMPLOYEE, EMPLOYEE_ID, FileCategory.CERTIFICATION))
                .thenReturn(Optional.of(existing));
        when(statusRepository.save(any())).thenAnswer(inv -> inv.getArgument(0));

        service.recordDocumentUploaded(
                file(12L, FileCategory.CERTIFICATION, EMPLOYEE_ID, OwnerType.CAREGIVER,
                        null, "extra.pdf", LocalDateTime.now()),
                EMPLOYEE_ID);

        verify(historyRepository, never()).save(any());
        assertEquals(ComplianceStatus.COMPLETE, existing.getStatus());
        assertEquals(12L, existing.getUserFileId());
        verify(statusRepository).save(existing);
    }

    @Test
    @DisplayName("Upload hook: patient-linked required document transitions the care circle")
    void recordDocumentUploaded_careCircleContext() {
        when(statusRepository.findBySubjectTypeAndSubjectIdAndDocumentType(
                SubjectType.CARE_CIRCLE, PATIENT_ID, FileCategory.CONSENT_FORM))
                .thenReturn(Optional.empty());
        when(statusRepository.save(any())).thenAnswer(inv -> inv.getArgument(0));
        when(historyRepository.save(any())).thenAnswer(inv -> inv.getArgument(0));

        service.recordDocumentUploaded(
                file(13L, FileCategory.CONSENT_FORM, 1L, OwnerType.PATIENT,
                        PATIENT_ID, "consent.pdf", LocalDateTime.now()),
                1L);

        ArgumentCaptor<DocumentStatusHistory> history =
                ArgumentCaptor.forClass(DocumentStatusHistory.class);
        verify(historyRepository).save(history.capture());
        assertEquals(SubjectType.CARE_CIRCLE, history.getValue().getSubjectType());
        assertEquals(PATIENT_ID, history.getValue().getSubjectId());
    }

    @Test
    @DisplayName("Upload hook: categories outside every required set are ignored")
    void recordDocumentUploaded_untrackedCategory_ignored() {
        service.recordDocumentUploaded(
                file(14L, FileCategory.OTHER_DOCUMENT, EMPLOYEE_ID, OwnerType.CAREGIVER,
                        PATIENT_ID, "misc.pdf", LocalDateTime.now()),
                EMPLOYEE_ID);

        verifyNoInteractions(statusRepository, historyRepository);
    }

    @Test
    @DisplayName("Digitization hook: in_progress -> complete with entry linked, audited")
    void recordStructuredEntrySaved_marksComplete() {
        DocumentRequirementStatus existing = record(SubjectType.EMPLOYEE, EMPLOYEE_ID,
                FileCategory.CERTIFICATION, ComplianceStatus.IN_PROGRESS);
        when(statusRepository.findBySubjectTypeAndSubjectIdAndDocumentType(
                SubjectType.EMPLOYEE, EMPLOYEE_ID, FileCategory.CERTIFICATION))
                .thenReturn(Optional.of(existing));
        when(statusRepository.save(any())).thenAnswer(inv -> inv.getArgument(0));
        when(historyRepository.save(any())).thenAnswer(inv -> inv.getArgument(0));

        StructuredDocumentEntry saved = entry(3L, FileCategory.CERTIFICATION, EMPLOYEE_ID, null);
        service.recordStructuredEntrySaved(saved,
                file(10L, FileCategory.CERTIFICATION, EMPLOYEE_ID, OwnerType.CAREGIVER,
                        null, "cpr.pdf", LocalDateTime.now()),
                EMPLOYEE_ID);

        ArgumentCaptor<DocumentStatusHistory> history =
                ArgumentCaptor.forClass(DocumentStatusHistory.class);
        verify(historyRepository).save(history.capture());
        assertEquals(ComplianceStatus.IN_PROGRESS, history.getValue().getPreviousStatus());
        assertEquals(ComplianceStatus.COMPLETE, history.getValue().getNewStatus());
        assertTrue(history.getValue().getReason().contains("cpr.pdf"));

        assertEquals(3L, existing.getStructuredEntryId());
    }

    @Test
    @DisplayName("Hooks never propagate persistence failures to the upload itself")
    void recordDocumentUploaded_persistenceFailure_swallowed() {
        when(statusRepository.findBySubjectTypeAndSubjectIdAndDocumentType(any(), any(), any()))
                .thenThrow(new RuntimeException("db down"));

        assertDoesNotThrow(() -> service.recordDocumentUploaded(
                file(10L, FileCategory.CERTIFICATION, EMPLOYEE_ID, OwnerType.CAREGIVER,
                        null, "cpr.pdf", LocalDateTime.now()),
                EMPLOYEE_ID));
    }

    // ==================== DASHBOARD & MISSING REPORT ====================

    private void stubBulkData(List<DocumentRequirementStatus> employeeRecords,
                              List<UserFile> employeeFiles,
                              List<StructuredDocumentEntry> employeeEntries) {
        when(userRepository.findByRole(Role.CAREGIVER)).thenReturn(List.of(employee));
        when(statusRepository.findBySubjectType(SubjectType.EMPLOYEE)).thenReturn(employeeRecords);
        when(userFileRepository.findByOwnerTypeAndFileCategoryInAndIsActiveTrue(
                eq(OwnerType.CAREGIVER), anyCollection())).thenReturn(employeeFiles);
        when(structuredEntryRepository.findByEmployeeUserIdIsNotNullAndIsActiveTrue())
                .thenReturn(employeeEntries);

        when(patientRepository.findAll()).thenReturn(List.of(patient));
        when(statusRepository.findBySubjectType(SubjectType.CARE_CIRCLE)).thenReturn(List.of());
        when(userFileRepository.findByPatientIdIsNotNullAndFileCategoryInAndIsActiveTrue(anyCollection()))
                .thenReturn(List.of());
        when(structuredEntryRepository.findByPatientIdIsNotNullAndIsActiveTrue())
                .thenReturn(List.of());
    }

    @Test
    @DisplayName("Dashboard: aggregates both subject types with correct counts and blocked flag")
    void dashboard_aggregatesBothSubjectTypes() {
        stubBulkData(List.of(),
                List.of(file(10L, FileCategory.CERTIFICATION, EMPLOYEE_ID, OwnerType.CAREGIVER,
                        null, "cpr.pdf", LocalDateTime.now())),
                List.of(entry(1L, FileCategory.BACKGROUND_CHECK, EMPLOYEE_ID, null)));

        List<ComplianceSummaryDTO> rows = service.getDashboard(null);

        assertEquals(2, rows.size());
        ComplianceSummaryDTO employeeRow = rows.stream()
                .filter(r -> r.getSubjectType().equals("EMPLOYEE")).findFirst().orElseThrow();
        assertEquals(EMPLOYEE_REQUIRED, employeeRow.getRequiredCount());
        assertEquals(1, employeeRow.getCompleteCount());
        assertEquals(1, employeeRow.getInProgressCount());
        assertTrue(employeeRow.isBlocked()); // still has missing docs

        ComplianceSummaryDTO circleRow = rows.stream()
                .filter(r -> r.getSubjectType().equals("CARE_CIRCLE")).findFirst().orElseThrow();
        assertEquals(CARE_CIRCLE_REQUIRED, circleRow.getMissingCount());
        assertTrue(circleRow.isBlocked());
    }

    @Test
    @DisplayName("Dashboard: subject-type filter skips the other subject type entirely")
    void dashboard_subjectTypeFilter_respected() {
        when(userRepository.findByRole(Role.CAREGIVER)).thenReturn(List.of(employee));
        when(statusRepository.findBySubjectType(SubjectType.EMPLOYEE)).thenReturn(List.of());
        when(userFileRepository.findByOwnerTypeAndFileCategoryInAndIsActiveTrue(
                eq(OwnerType.CAREGIVER), anyCollection())).thenReturn(List.of());
        when(structuredEntryRepository.findByEmployeeUserIdIsNotNullAndIsActiveTrue())
                .thenReturn(List.of());

        List<ComplianceSummaryDTO> rows = service.getDashboard(SubjectType.EMPLOYEE);

        assertEquals(1, rows.size());
        assertEquals("EMPLOYEE", rows.get(0).getSubjectType());
        verify(patientRepository, never()).findAll();
    }

    @Test
    @DisplayName("Missing report: only MISSING and REJECTED items; complete and in-progress excluded")
    void listMissing_excludesCompleteAndInProgress() {
        stubBulkData(
                List.of(record(SubjectType.EMPLOYEE, EMPLOYEE_ID,
                        FileCategory.EMPLOYMENT_CONTRACT, ComplianceStatus.REJECTED)),
                List.of(file(10L, FileCategory.CERTIFICATION, EMPLOYEE_ID, OwnerType.CAREGIVER,
                        null, "cpr.pdf", LocalDateTime.now())),
                List.of(entry(1L, FileCategory.BACKGROUND_CHECK, EMPLOYEE_ID, null)));

        List<MissingDocumentDTO> missing = service.listMissingDocuments(SubjectType.EMPLOYEE, null);

        // 9 required - 1 in-progress - 1 complete = 7 outstanding (6 missing + 1 rejected)
        assertEquals(EMPLOYEE_REQUIRED - 2, missing.size());
        assertTrue(missing.stream().noneMatch(m ->
                m.getDocumentType().equals(FileCategory.CERTIFICATION.name())
                        || m.getDocumentType().equals(FileCategory.BACKGROUND_CHECK.name())));
        assertTrue(missing.stream().anyMatch(m ->
                m.getDocumentType().equals(FileCategory.EMPLOYMENT_CONTRACT.name())
                        && m.getStatus().equals("REJECTED")));
        assertTrue(missing.stream().allMatch(m -> m.getSubjectName().equals("Jane Caregiver")));
    }

    @Test
    @DisplayName("Missing report: document-type filter narrows the result")
    void listMissing_documentTypeFilter_respected() {
        stubBulkData(List.of(), List.of(), List.of());

        List<MissingDocumentDTO> missing =
                service.listMissingDocuments(SubjectType.EMPLOYEE, FileCategory.TAX_FORM);

        assertEquals(1, missing.size());
        assertEquals("TAX_FORM", missing.get(0).getDocumentType());
    }

    // ==================== CSV EXPORT ====================

    @Test
    @DisplayName("CSV export: header row plus one line per outstanding form, filters respected")
    void exportCsv_rendersHeaderAndRows() {
        stubBulkData(List.of(), List.of(), List.of());

        String csv = service.exportMissingDocumentsCsv(SubjectType.EMPLOYEE, FileCategory.TAX_FORM);

        String[] lines = csv.split("\n");
        assertEquals("Subject Type,Subject ID,Subject Name,Document Type,Status,Notes,Last Updated",
                lines[0]);
        assertEquals(2, lines.length);
        assertTrue(lines[1].startsWith("EMPLOYEE," + EMPLOYEE_ID + ",Jane Caregiver,TAX_FORM,MISSING"));
    }

    @Test
    @DisplayName("CSV export: values containing commas or quotes are escaped")
    void exportCsv_escapesSpecialCharacters() {
        employee.setName("Doe, Jane \"JD\"");
        stubBulkData(List.of(), List.of(), List.of());

        String csv = service.exportMissingDocumentsCsv(SubjectType.EMPLOYEE, FileCategory.TAX_FORM);

        assertTrue(csv.contains("\"Doe, Jane \"\"JD\"\"\""));
    }

    @Test
    @DisplayName("CSV export: zero outstanding forms -> header only")
    void exportCsv_zeroMissing_headerOnly() {
        when(userRepository.findByRole(Role.CAREGIVER)).thenReturn(List.of());
        when(statusRepository.findBySubjectType(SubjectType.EMPLOYEE)).thenReturn(List.of());
        when(userFileRepository.findByOwnerTypeAndFileCategoryInAndIsActiveTrue(
                eq(OwnerType.CAREGIVER), anyCollection())).thenReturn(List.of());
        when(structuredEntryRepository.findByEmployeeUserIdIsNotNullAndIsActiveTrue())
                .thenReturn(List.of());
        when(patientRepository.findAll()).thenReturn(List.of());
        when(statusRepository.findBySubjectType(SubjectType.CARE_CIRCLE)).thenReturn(List.of());
        when(userFileRepository.findByPatientIdIsNotNullAndFileCategoryInAndIsActiveTrue(anyCollection()))
                .thenReturn(List.of());
        when(structuredEntryRepository.findByPatientIdIsNotNullAndIsActiveTrue())
                .thenReturn(List.of());

        String csv = service.exportMissingDocumentsCsv(null, null);

        assertEquals("Subject Type,Subject ID,Subject Name,Document Type,Status,Notes,Last Updated\n",
                csv);
    }

    // ==================== AUDIT TRAIL RETRIEVAL ====================

    @Test
    @DisplayName("History: entries are mapped with resolved actor names, newest first order preserved")
    void getHistory_mapsEntriesWithActorNames() {
        DocumentStatusHistory h1 = DocumentStatusHistory.builder()
                .id(1L).subjectType(SubjectType.EMPLOYEE).subjectId(EMPLOYEE_ID)
                .documentType(FileCategory.CERTIFICATION)
                .previousStatus(ComplianceStatus.IN_PROGRESS)
                .newStatus(ComplianceStatus.COMPLETE)
                .changedBy(EMPLOYEE_ID).reason("verified")
                .changedAt(LocalDateTime.now())
                .build();
        DocumentStatusHistory h2 = DocumentStatusHistory.builder()
                .id(2L).subjectType(SubjectType.EMPLOYEE).subjectId(EMPLOYEE_ID)
                .documentType(FileCategory.CERTIFICATION)
                .previousStatus(null)
                .newStatus(ComplianceStatus.IN_PROGRESS)
                .changedBy(99L).reason("uploaded")
                .changedAt(LocalDateTime.now().minusDays(1))
                .build();
        when(historyRepository.findBySubjectTypeAndSubjectIdOrderByChangedAtDesc(
                SubjectType.EMPLOYEE, EMPLOYEE_ID)).thenReturn(List.of(h1, h2));
        when(userRepository.findAllById(anyCollection())).thenReturn(List.of(employee));

        List<DocumentStatusHistoryDTO> history =
                service.getHistory(SubjectType.EMPLOYEE, EMPLOYEE_ID, null);

        assertEquals(2, history.size());
        assertEquals("Jane Caregiver", history.get(0).getChangedByName());
        assertEquals("IN_PROGRESS", history.get(0).getPreviousStatus());
        assertEquals("COMPLETE", history.get(0).getNewStatus());
        assertNull(history.get(1).getPreviousStatus());
        assertNull(history.get(1).getChangedByName()); // unknown actor id -> no name
        assertEquals("uploaded", history.get(1).getReason());
    }

    @Test
    @DisplayName("History: document-type filter delegates to the scoped repository query")
    void getHistory_documentTypeFilter_usesScopedQuery() {
        when(historyRepository.findBySubjectTypeAndSubjectIdAndDocumentTypeOrderByChangedAtDesc(
                SubjectType.EMPLOYEE, EMPLOYEE_ID, FileCategory.TAX_FORM)).thenReturn(List.of());
        when(userRepository.findAllById(anyCollection())).thenReturn(List.of());

        service.getHistory(SubjectType.EMPLOYEE, EMPLOYEE_ID, FileCategory.TAX_FORM);

        verify(historyRepository).findBySubjectTypeAndSubjectIdAndDocumentTypeOrderByChangedAtDesc(
                SubjectType.EMPLOYEE, EMPLOYEE_ID, FileCategory.TAX_FORM);
        verify(historyRepository, never())
                .findBySubjectTypeAndSubjectIdOrderByChangedAtDesc(any(), any());
    }
}
