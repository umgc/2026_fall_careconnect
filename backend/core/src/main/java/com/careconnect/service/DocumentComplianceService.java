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
import com.careconnect.repository.DocumentRequirementStatusRepository;
import com.careconnect.repository.DocumentStatusHistoryRepository;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.StructuredDocumentEntryRepository;
import com.careconnect.repository.UserFileRepository;
import com.careconnect.repository.UserRepository;
import com.careconnect.security.Role;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.function.Function;
import java.util.stream.Collectors;

/**
 * Document Completion and Compliance Tracking.
 *
 * <p>Maintains a required-document checklist per subject — an employee going
 * through hiring/onboarding or a care circle (keyed by its patient) — so
 * coordinators can spot onboarding blockers at a glance. A document's status is
 * derived from existing evidence (uploaded files and digitized
 * {@link StructuredDocumentEntry} records) until an explicit transition is
 * recorded; every transition is written to an immutable audit trail capturing
 * who changed it, when and why.</p>
 */
@Slf4j
@Service
@Transactional
public class DocumentComplianceService {

    private static final DateTimeFormatter CSV_TS = DateTimeFormatter.ISO_LOCAL_DATE_TIME;

    private final DocumentRequirementStatusRepository statusRepository;
    private final DocumentStatusHistoryRepository historyRepository;
    private final UserFileRepository userFileRepository;
    private final StructuredDocumentEntryRepository structuredEntryRepository;
    private final UserRepository userRepository;
    private final PatientRepository patientRepository;

    @Autowired
    public DocumentComplianceService(DocumentRequirementStatusRepository statusRepository,
                                     DocumentStatusHistoryRepository historyRepository,
                                     UserFileRepository userFileRepository,
                                     StructuredDocumentEntryRepository structuredEntryRepository,
                                     UserRepository userRepository,
                                     PatientRepository patientRepository) {
        this.statusRepository = statusRepository;
        this.historyRepository = historyRepository;
        this.userFileRepository = userFileRepository;
        this.structuredEntryRepository = structuredEntryRepository;
        this.userRepository = userRepository;
        this.patientRepository = patientRepository;
    }

    // ==================== CHECKLIST ====================

    /** Required-document checklist for a single employee or care circle. */
    @Transactional(readOnly = true)
    public DocumentChecklistDTO getChecklist(SubjectType subjectType, Long subjectId) {
        Set<UserFile.FileCategory> required = requiredFor(subjectType);

        List<DocumentRequirementStatus> records =
                statusRepository.findBySubjectTypeAndSubjectId(subjectType, subjectId);

        List<UserFile> files;
        List<StructuredDocumentEntry> entries;
        if (subjectType == SubjectType.EMPLOYEE) {
            files = userFileRepository.findByOwnerIdAndOwnerTypeAndFileCategoryInAndIsActiveTrue(
                    subjectId, UserFile.OwnerType.CAREGIVER, required);
            entries = structuredEntryRepository.findByEmployeeUserIdAndIsActiveTrue(subjectId);
        } else {
            files = userFileRepository.findByPatientIdAndFileCategoryInAndIsActiveTrue(subjectId, required);
            entries = structuredEntryRepository.findByPatientIdAndIsActiveTrue(subjectId);
        }

        return buildChecklist(subjectType, subjectId, resolveSubjectName(subjectType, subjectId),
                records, files, entries);
    }

    // ==================== DASHBOARD ====================

    /**
     * Compliance summary rows for every subject of the given type ({@code null}
     * for both employees and care circles), least-complete first so onboarding
     * blockers surface at the top.
     */
    @Transactional(readOnly = true)
    public List<ComplianceSummaryDTO> getDashboard(SubjectType filter) {
        List<ComplianceSummaryDTO> rows = buildAllChecklists(filter).stream()
                .map(this::toSummary)
                .collect(Collectors.toList());
        rows.sort(Comparator.comparing(ComplianceSummaryDTO::isBlocked).reversed()
                .thenComparing(ComplianceSummaryDTO::getPercentComplete)
                .thenComparing(r -> r.getSubjectName() != null ? r.getSubjectName() : ""));
        return rows;
    }

    // ==================== MISSING FORMS REPORT ====================

    /**
     * Every outstanding required form (MISSING or REJECTED) across subjects,
     * optionally filtered by subject type and/or document type.
     */
    @Transactional(readOnly = true)
    public List<MissingDocumentDTO> listMissingDocuments(SubjectType subjectTypeFilter,
                                                         UserFile.FileCategory documentTypeFilter) {
        List<MissingDocumentDTO> out = new ArrayList<>();
        for (DocumentChecklistDTO checklist : buildAllChecklists(subjectTypeFilter)) {
            for (DocumentChecklistItemDTO item : checklist.getItems()) {
                boolean outstanding = ComplianceStatus.MISSING.name().equals(item.getStatus())
                        || ComplianceStatus.REJECTED.name().equals(item.getStatus());
                if (!outstanding) {
                    continue;
                }
                if (documentTypeFilter != null
                        && !documentTypeFilter.name().equals(item.getDocumentType())) {
                    continue;
                }
                out.add(MissingDocumentDTO.builder()
                        .subjectType(checklist.getSubjectType())
                        .subjectId(checklist.getSubjectId())
                        .subjectName(checklist.getSubjectName())
                        .documentType(item.getDocumentType())
                        .status(item.getStatus())
                        .notes(item.getNotes())
                        .updatedAt(item.getUpdatedAt())
                        .build());
            }
        }
        out.sort(Comparator
                .comparing((MissingDocumentDTO d) -> d.getSubjectName() != null ? d.getSubjectName() : "")
                .thenComparing(MissingDocumentDTO::getDocumentType));
        return out;
    }

    /** The missing-forms report rendered as CSV for export. */
    @Transactional(readOnly = true)
    public String exportMissingDocumentsCsv(SubjectType subjectTypeFilter,
                                            UserFile.FileCategory documentTypeFilter) {
        StringBuilder csv = new StringBuilder(
                "Subject Type,Subject ID,Subject Name,Document Type,Status,Notes,Last Updated\n");
        for (MissingDocumentDTO row : listMissingDocuments(subjectTypeFilter, documentTypeFilter)) {
            csv.append(csvCell(row.getSubjectType())).append(',')
               .append(row.getSubjectId()).append(',')
               .append(csvCell(row.getSubjectName())).append(',')
               .append(csvCell(row.getDocumentType())).append(',')
               .append(csvCell(row.getStatus())).append(',')
               .append(csvCell(row.getNotes())).append(',')
               .append(csvCell(row.getUpdatedAt() != null ? CSV_TS.format(row.getUpdatedAt()) : ""))
               .append('\n');
        }
        return csv.toString();
    }

    // ==================== STATUS TRANSITIONS ====================

    /**
     * Manually transition a required document's status (e.g. a coordinator
     * verifying a form COMPLETE or REJECTED). The reason is mandatory and is
     * written to the audit trail together with who made the change and when.
     */
    public DocumentChecklistItemDTO updateStatus(DocumentStatusUpdateRequest request, User actor) {
        SubjectType subjectType = SubjectType.fromClientValue(request.getSubjectType());
        if (request.getSubjectId() == null) {
            throw new IllegalArgumentException("subjectId is required");
        }
        UserFile.FileCategory documentType = parseDocumentType(request.getDocumentType());
        ComplianceStatus newStatus = ComplianceStatus.fromClientValue(request.getStatus());
        if (request.getReason() == null || request.getReason().isBlank()) {
            throw new IllegalArgumentException("A reason is required for every status change");
        }
        if (!requiredFor(subjectType).contains(documentType)) {
            throw new IllegalArgumentException("'" + documentType
                    + "' is not part of the required document set for " + subjectType);
        }
        verifySubjectExists(subjectType, request.getSubjectId());

        applyTransition(subjectType, request.getSubjectId(), documentType, newStatus,
                request.getReason().trim(), actor.getId(), null, null);

        // Return the refreshed checklist item so the caller sees the merged view.
        return getChecklist(subjectType, request.getSubjectId()).getItems().stream()
                .filter(i -> i.getDocumentType().equals(documentType.name()))
                .findFirst()
                .orElseThrow(() -> new IllegalStateException(
                        "Updated checklist item not found: " + documentType));
    }

    /**
     * System transition hook: a document was uploaded. Moves MISSING (or
     * untracked, or REJECTED) requirements to IN_PROGRESS for every subject
     * context the file applies to; never downgrades IN_PROGRESS or COMPLETE.
     * Called by {@link FileManagementService} after each upload.
     */
    public void recordDocumentUploaded(UserFile file, Long actorUserId) {
        UserFile.FileCategory category = file.getFileCategory();
        String reason = "Document uploaded: "
                + (file.getOriginalFilename() != null ? file.getOriginalFilename() : file.getFilename());

        if (file.getOwnerType() == UserFile.OwnerType.CAREGIVER
                && requiredFor(SubjectType.EMPLOYEE).contains(category)) {
            progressOnEvidence(SubjectType.EMPLOYEE, file.getOwnerId(), category,
                    ComplianceStatus.IN_PROGRESS, reason, actorUserId, file.getId(), null);
        }
        if (file.getPatientId() != null
                && requiredFor(SubjectType.CARE_CIRCLE).contains(category)) {
            progressOnEvidence(SubjectType.CARE_CIRCLE, file.getPatientId(), category,
                    ComplianceStatus.IN_PROGRESS, reason, actorUserId, file.getId(), null);
        }
    }

    /**
     * System transition hook: an uploaded document was digitized into a
     * structured record. Marks the requirement COMPLETE for every subject
     * context the entry applies to. Called by {@link FileManagementService}
     * after a structured entry is saved.
     */
    public void recordStructuredEntrySaved(StructuredDocumentEntry entry, UserFile file, Long actorUserId) {
        UserFile.FileCategory category = entry.getDocumentType();
        String reason = "Structured record digitized"
                + (file != null && file.getOriginalFilename() != null
                        ? " from " + file.getOriginalFilename() : "");

        if (entry.getEmployeeUserId() != null
                && requiredFor(SubjectType.EMPLOYEE).contains(category)) {
            progressOnEvidence(SubjectType.EMPLOYEE, entry.getEmployeeUserId(), category,
                    ComplianceStatus.COMPLETE, reason, actorUserId, entry.getUserFileId(), entry.getId());
        }
        if (entry.getPatientId() != null
                && requiredFor(SubjectType.CARE_CIRCLE).contains(category)) {
            progressOnEvidence(SubjectType.CARE_CIRCLE, entry.getPatientId(), category,
                    ComplianceStatus.COMPLETE, reason, actorUserId, entry.getUserFileId(), entry.getId());
        }
    }

    // ==================== AUDIT TRAIL ====================

    /** Status-transition history for a subject, optionally scoped to one document type. */
    @Transactional(readOnly = true)
    public List<DocumentStatusHistoryDTO> getHistory(SubjectType subjectType, Long subjectId,
                                                     UserFile.FileCategory documentType) {
        List<DocumentStatusHistory> history = documentType != null
                ? historyRepository.findBySubjectTypeAndSubjectIdAndDocumentTypeOrderByChangedAtDesc(
                        subjectType, subjectId, documentType)
                : historyRepository.findBySubjectTypeAndSubjectIdOrderByChangedAtDesc(
                        subjectType, subjectId);

        // Resolve actor names in one query
        Set<Long> actorIds = history.stream()
                .map(DocumentStatusHistory::getChangedBy)
                .collect(Collectors.toSet());
        Map<Long, String> actorNames = userRepository.findAllById(actorIds).stream()
                .collect(Collectors.toMap(User::getId,
                        u -> u.getName() != null ? u.getName() : u.getEmail()));

        return history.stream()
                .map(h -> DocumentStatusHistoryDTO.builder()
                        .id(h.getId())
                        .subjectType(h.getSubjectType().name())
                        .subjectId(h.getSubjectId())
                        .documentType(h.getDocumentType().name())
                        .previousStatus(h.getPreviousStatus() != null ? h.getPreviousStatus().name() : null)
                        .newStatus(h.getNewStatus().name())
                        .changedBy(h.getChangedBy())
                        .changedByName(actorNames.get(h.getChangedBy()))
                        .reason(h.getReason())
                        .changedAt(h.getChangedAt())
                        .build())
                .collect(Collectors.toList());
    }

    // ==================== INTERNALS ====================

    /**
     * Strictly resolve a client-supplied document type to a {@link UserFile.FileCategory}.
     * Case- and separator-insensitive; unknown values throw so callers can surface a 400.
     */
    public static UserFile.FileCategory parseDocumentType(String raw) {
        if (raw == null || raw.isBlank()) {
            throw new IllegalArgumentException("documentType is required");
        }
        String key = raw.trim().toUpperCase().replace('-', '_').replace(' ', '_');
        try {
            return UserFile.FileCategory.valueOf(key);
        } catch (IllegalArgumentException e) {
            throw new IllegalArgumentException("Invalid documentType '" + raw + "'");
        }
    }

    private Set<UserFile.FileCategory> requiredFor(SubjectType subjectType) {
        return DocumentRequirementStatus.REQUIRED_DOCUMENTS.get(subjectType);
    }

    private void verifySubjectExists(SubjectType subjectType, Long subjectId) {
        boolean exists = subjectType == SubjectType.EMPLOYEE
                ? userRepository.existsById(subjectId)
                : patientRepository.existsById(subjectId);
        if (!exists) {
            throw new IllegalArgumentException(subjectType + " subject not found: " + subjectId);
        }
    }

    private String resolveSubjectName(SubjectType subjectType, Long subjectId) {
        if (subjectType == SubjectType.EMPLOYEE) {
            return userRepository.findById(subjectId)
                    .map(u -> u.getName() != null ? u.getName() : u.getEmail())
                    .orElse("Employee #" + subjectId);
        }
        return patientRepository.findById(subjectId)
                .map(DocumentComplianceService::patientDisplayName)
                .orElse("Care circle #" + subjectId);
    }

    private static String patientDisplayName(Patient patient) {
        String name = ((patient.getFirstName() != null ? patient.getFirstName() : "") + " "
                + (patient.getLastName() != null ? patient.getLastName() : "")).trim();
        return name.isEmpty() ? "Care circle #" + patient.getId() : name;
    }

    /**
     * System transitions only ever move a requirement forward (MISSING/REJECTED
     * → IN_PROGRESS → COMPLETE); a manually verified COMPLETE or REJECTED state
     * is never silently downgraded, though evidence links are kept current.
     */
    private void progressOnEvidence(SubjectType subjectType, Long subjectId,
                                    UserFile.FileCategory documentType, ComplianceStatus target,
                                    String reason, Long actorUserId, Long fileId, Long entryId) {
        try {
            Optional<DocumentRequirementStatus> existing =
                    statusRepository.findBySubjectTypeAndSubjectIdAndDocumentType(
                            subjectType, subjectId, documentType);
            ComplianceStatus current = existing.map(DocumentRequirementStatus::getStatus).orElse(null);

            boolean shouldTransition;
            if (target == ComplianceStatus.COMPLETE) {
                shouldTransition = current != ComplianceStatus.COMPLETE;
            } else { // IN_PROGRESS on upload
                shouldTransition = current == null
                        || current == ComplianceStatus.MISSING
                        || current == ComplianceStatus.REJECTED;
            }

            if (shouldTransition) {
                applyTransition(subjectType, subjectId, documentType, target,
                        reason, actorUserId, fileId, entryId);
            } else if (existing.isPresent()) {
                // Keep the evidence links fresh without spamming the audit trail.
                DocumentRequirementStatus record = existing.get();
                if (fileId != null) {
                    record.setUserFileId(fileId);
                }
                if (entryId != null) {
                    record.setStructuredEntryId(entryId);
                }
                statusRepository.save(record);
            }
        } catch (Exception e) {
            // Compliance bookkeeping must never fail the upload/digitization itself.
            log.error("Failed to record compliance transition for {} {} / {}",
                    subjectType, subjectId, documentType, e);
        }
    }

    private void applyTransition(SubjectType subjectType, Long subjectId,
                                 UserFile.FileCategory documentType, ComplianceStatus newStatus,
                                 String reason, Long actorUserId, Long fileId, Long entryId) {
        DocumentRequirementStatus record = statusRepository
                .findBySubjectTypeAndSubjectIdAndDocumentType(subjectType, subjectId, documentType)
                .orElseGet(() -> DocumentRequirementStatus.builder()
                        .subjectType(subjectType)
                        .subjectId(subjectId)
                        .documentType(documentType)
                        .build());

        ComplianceStatus previous = record.getStatus(); // null on first transition
        record.setStatus(newStatus);
        record.setNotes(reason);
        record.setUpdatedBy(actorUserId);
        if (fileId != null) {
            record.setUserFileId(fileId);
        }
        if (entryId != null) {
            record.setStructuredEntryId(entryId);
        }
        statusRepository.save(record);

        historyRepository.save(DocumentStatusHistory.builder()
                .subjectType(subjectType)
                .subjectId(subjectId)
                .documentType(documentType)
                .previousStatus(previous)
                .newStatus(newStatus)
                .changedBy(actorUserId)
                .reason(reason)
                .build());

        log.info("Compliance status transition: {} {} / {} {} -> {} by user {}",
                subjectType, subjectId, documentType, previous, newStatus, actorUserId);
    }

    /**
     * Build every subject's checklist for the requested subject type(s) using a
     * fixed number of bulk queries, so the dashboard does not issue per-subject
     * lookups.
     */
    private List<DocumentChecklistDTO> buildAllChecklists(SubjectType filter) {
        List<DocumentChecklistDTO> out = new ArrayList<>();

        if (filter == null || filter == SubjectType.EMPLOYEE) {
            Set<UserFile.FileCategory> required = requiredFor(SubjectType.EMPLOYEE);
            Map<Long, List<DocumentRequirementStatus>> records = groupBy(
                    statusRepository.findBySubjectType(SubjectType.EMPLOYEE),
                    DocumentRequirementStatus::getSubjectId);
            Map<Long, List<UserFile>> files = groupBy(
                    userFileRepository.findByOwnerTypeAndFileCategoryInAndIsActiveTrue(
                            UserFile.OwnerType.CAREGIVER, required),
                    UserFile::getOwnerId);
            Map<Long, List<StructuredDocumentEntry>> entries = groupBy(
                    structuredEntryRepository.findByEmployeeUserIdIsNotNullAndIsActiveTrue(),
                    StructuredDocumentEntry::getEmployeeUserId);

            for (User employee : userRepository.findByRole(Role.CAREGIVER)) {
                out.add(buildChecklist(SubjectType.EMPLOYEE, employee.getId(),
                        employee.getName() != null ? employee.getName() : employee.getEmail(),
                        records.getOrDefault(employee.getId(), List.of()),
                        files.getOrDefault(employee.getId(), List.of()),
                        entries.getOrDefault(employee.getId(), List.of())));
            }
        }

        if (filter == null || filter == SubjectType.CARE_CIRCLE) {
            Set<UserFile.FileCategory> required = requiredFor(SubjectType.CARE_CIRCLE);
            Map<Long, List<DocumentRequirementStatus>> records = groupBy(
                    statusRepository.findBySubjectType(SubjectType.CARE_CIRCLE),
                    DocumentRequirementStatus::getSubjectId);
            Map<Long, List<UserFile>> files = groupBy(
                    userFileRepository.findByPatientIdIsNotNullAndFileCategoryInAndIsActiveTrue(required),
                    UserFile::getPatientId);
            Map<Long, List<StructuredDocumentEntry>> entries = groupBy(
                    structuredEntryRepository.findByPatientIdIsNotNullAndIsActiveTrue(),
                    StructuredDocumentEntry::getPatientId);

            for (Patient patient : patientRepository.findAll()) {
                out.add(buildChecklist(SubjectType.CARE_CIRCLE, patient.getId(),
                        patientDisplayName(patient),
                        records.getOrDefault(patient.getId(), List.of()),
                        files.getOrDefault(patient.getId(), List.of()),
                        entries.getOrDefault(patient.getId(), List.of())));
            }
        }

        return out;
    }

    private static <T> Map<Long, List<T>> groupBy(List<T> items, Function<T, Long> key) {
        return items.stream().collect(Collectors.groupingBy(key));
    }

    private DocumentChecklistDTO buildChecklist(SubjectType subjectType, Long subjectId,
                                                String subjectName,
                                                List<DocumentRequirementStatus> records,
                                                List<UserFile> files,
                                                List<StructuredDocumentEntry> entries) {
        Set<UserFile.FileCategory> required = requiredFor(subjectType);

        Map<UserFile.FileCategory, DocumentRequirementStatus> recordByDoc = records.stream()
                .collect(Collectors.toMap(DocumentRequirementStatus::getDocumentType,
                        r -> r, (a, b) -> a, LinkedHashMap::new));
        Map<UserFile.FileCategory, List<UserFile>> filesByDoc = files.stream()
                .collect(Collectors.groupingBy(UserFile::getFileCategory));
        Set<UserFile.FileCategory> digitizedDocs = entries.stream()
                .map(StructuredDocumentEntry::getDocumentType)
                .collect(Collectors.toSet());

        List<DocumentChecklistItemDTO> items = required.stream()
                .sorted(Comparator.comparing(Enum::name))
                .map(docType -> buildItem(docType,
                        recordByDoc.get(docType),
                        filesByDoc.getOrDefault(docType, List.of()),
                        digitizedDocs.contains(docType)))
                .collect(Collectors.toList());

        int missing = 0, inProgress = 0, complete = 0, rejected = 0;
        for (DocumentChecklistItemDTO item : items) {
            switch (ComplianceStatus.valueOf(item.getStatus())) {
                case MISSING -> missing++;
                case IN_PROGRESS -> inProgress++;
                case COMPLETE -> complete++;
                case REJECTED -> rejected++;
            }
        }

        return DocumentChecklistDTO.builder()
                .subjectType(subjectType.name())
                .subjectId(subjectId)
                .subjectName(subjectName)
                .items(items)
                .requiredCount(items.size())
                .missingCount(missing)
                .inProgressCount(inProgress)
                .completeCount(complete)
                .rejectedCount(rejected)
                .percentComplete(items.isEmpty() ? 0 : complete * 100 / items.size())
                .build();
    }

    private DocumentChecklistItemDTO buildItem(UserFile.FileCategory documentType,
                                               DocumentRequirementStatus record,
                                               List<UserFile> filesOfType,
                                               boolean hasStructuredEntry) {
        UserFile latest = filesOfType.stream()
                .max(Comparator.comparing(UserFile::getUploadedAt,
                        Comparator.nullsFirst(Comparator.naturalOrder())))
                .orElse(null);

        // A recorded transition wins; otherwise derive from existing evidence so
        // documents uploaded before this feature still report a sensible state.
        ComplianceStatus status;
        if (record != null) {
            status = record.getStatus();
        } else if (hasStructuredEntry) {
            status = ComplianceStatus.COMPLETE;
        } else if (!filesOfType.isEmpty()) {
            status = ComplianceStatus.IN_PROGRESS;
        } else {
            status = ComplianceStatus.MISSING;
        }

        return DocumentChecklistItemDTO.builder()
                .documentType(documentType.name())
                .status(status.name())
                .tracked(record != null)
                .fileCount(filesOfType.size())
                .hasStructuredEntry(hasStructuredEntry)
                .latestFileId(latest != null ? latest.getId() : null)
                .latestFilename(latest != null ? latest.getOriginalFilename() : null)
                .latestUploadAt(latest != null ? latest.getUploadedAt() : null)
                .notes(record != null ? record.getNotes() : null)
                .updatedBy(record != null ? record.getUpdatedBy() : null)
                .updatedAt(record != null ? record.getUpdatedAt() : null)
                .build();
    }

    private ComplianceSummaryDTO toSummary(DocumentChecklistDTO checklist) {
        return ComplianceSummaryDTO.builder()
                .subjectType(checklist.getSubjectType())
                .subjectId(checklist.getSubjectId())
                .subjectName(checklist.getSubjectName())
                .requiredCount(checklist.getRequiredCount())
                .missingCount(checklist.getMissingCount())
                .inProgressCount(checklist.getInProgressCount())
                .completeCount(checklist.getCompleteCount())
                .rejectedCount(checklist.getRejectedCount())
                .percentComplete(checklist.getPercentComplete())
                .blocked(checklist.getMissingCount() + checklist.getRejectedCount() > 0)
                .build();
    }

    private static String csvCell(String value) {
        if (value == null) {
            return "";
        }
        if (value.contains(",") || value.contains("\"") || value.contains("\n")) {
            return '"' + value.replace("\"", "\"\"") + '"';
        }
        return value;
    }
}
