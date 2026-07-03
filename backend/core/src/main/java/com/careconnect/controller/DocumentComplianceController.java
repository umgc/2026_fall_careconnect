package com.careconnect.controller;

import com.careconnect.dto.DocumentStatusUpdateRequest;
import com.careconnect.model.DocumentRequirementStatus;
import com.careconnect.model.DocumentRequirementStatus.SubjectType;
import com.careconnect.model.User;
import com.careconnect.model.UserFile;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.service.DocumentComplianceService;
import com.careconnect.util.SecurityUtil;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

/**
 * Document Completion and Compliance Tracking Dashboard.
 *
 * <p>Exposes the required-document checklist per employee or care circle, a
 * coordinator dashboard of compliance summaries, a filterable/exportable
 * missing-forms report, audited manual status transitions, and the transition
 * history. Coordinators (admins and caregivers) see everything; employees can
 * view their own checklist.</p>
 */
@Slf4j
@RestController
@RequestMapping("/v1/api/document-compliance")
public class DocumentComplianceController {

    private final DocumentComplianceService complianceService;
    private final SecurityUtil securityUtil;
    private final AuthorizationService authorizationService;

    public DocumentComplianceController(DocumentComplianceService complianceService,
                                        SecurityUtil securityUtil,
                                        AuthorizationService authorizationService) {
        this.complianceService = complianceService;
        this.securityUtil = securityUtil;
        this.authorizationService = authorizationService;
    }

    /** The document types tracked per subject type (drives frontend rendering). */
    @GetMapping("/required-documents")
    public ResponseEntity<?> requiredDocuments() {
        return ResponseEntity.ok(Map.of(
                SubjectType.EMPLOYEE.name(),
                DocumentRequirementStatus.REQUIRED_DOCUMENTS.get(SubjectType.EMPLOYEE)
                        .stream().map(Enum::name).sorted().toList(),
                SubjectType.CARE_CIRCLE.name(),
                DocumentRequirementStatus.REQUIRED_DOCUMENTS.get(SubjectType.CARE_CIRCLE)
                        .stream().map(Enum::name).sorted().toList()));
    }

    /** Compliance summary for every employee and/or care circle (coordinator dashboard). */
    @GetMapping("/dashboard")
    public ResponseEntity<?> dashboard(@RequestParam(required = false) String subjectType) {
        try {
            User user = requireUser();
            authorizationService.requireAdminOrCaregiver(user);
            SubjectType filter = parseOptionalSubjectType(subjectType);
            return ResponseEntity.ok(complianceService.getDashboard(filter));
        } catch (UnauthorizedException e) {
            return forbidden(e);
        } catch (IllegalArgumentException e) {
            return badRequest(e);
        }
    }

    /** Required-document checklist for one employee or care circle. */
    @GetMapping("/checklist/{subjectType}/{subjectId}")
    public ResponseEntity<?> checklist(@PathVariable String subjectType,
                                       @PathVariable Long subjectId) {
        try {
            User user = requireUser();
            SubjectType type = SubjectType.fromClientValue(subjectType);
            requireChecklistAccess(user, type, subjectId);
            return ResponseEntity.ok(complianceService.getChecklist(type, subjectId));
        } catch (UnauthorizedException e) {
            return forbidden(e);
        } catch (IllegalArgumentException e) {
            return badRequest(e);
        }
    }

    /** Outstanding required forms (MISSING / REJECTED), filterable by subject and document type. */
    @GetMapping("/missing")
    public ResponseEntity<?> missing(@RequestParam(required = false) String subjectType,
                                     @RequestParam(required = false) String documentType) {
        try {
            User user = requireUser();
            authorizationService.requireAdminOrCaregiver(user);
            return ResponseEntity.ok(complianceService.listMissingDocuments(
                    parseOptionalSubjectType(subjectType),
                    parseOptionalDocumentType(documentType)));
        } catch (UnauthorizedException e) {
            return forbidden(e);
        } catch (IllegalArgumentException e) {
            return badRequest(e);
        }
    }

    /** The missing-forms report as a downloadable CSV. */
    @GetMapping("/missing/export")
    public ResponseEntity<?> exportMissing(@RequestParam(required = false) String subjectType,
                                           @RequestParam(required = false) String documentType) {
        try {
            User user = requireUser();
            authorizationService.requireAdminOrCaregiver(user);
            String csv = complianceService.exportMissingDocumentsCsv(
                    parseOptionalSubjectType(subjectType),
                    parseOptionalDocumentType(documentType));
            return ResponseEntity.ok()
                    .header(HttpHeaders.CONTENT_DISPOSITION,
                            "attachment; filename=\"missing-documents.csv\"")
                    .contentType(MediaType.parseMediaType("text/csv"))
                    .body(csv);
        } catch (UnauthorizedException e) {
            return forbidden(e);
        } catch (IllegalArgumentException e) {
            return badRequest(e);
        }
    }

    /** Manually transition a document's status; the reason is mandatory and audited. */
    @PutMapping("/status")
    public ResponseEntity<?> updateStatus(@RequestBody DocumentStatusUpdateRequest request) {
        try {
            User user = requireUser();
            authorizationService.requireAdminOrCaregiver(user);
            return ResponseEntity.ok(complianceService.updateStatus(request, user));
        } catch (UnauthorizedException e) {
            return forbidden(e);
        } catch (IllegalArgumentException e) {
            return badRequest(e);
        }
    }

    /** Audit trail of status transitions for a subject (who, when, why). */
    @GetMapping("/history/{subjectType}/{subjectId}")
    public ResponseEntity<?> history(@PathVariable String subjectType,
                                     @PathVariable Long subjectId,
                                     @RequestParam(required = false) String documentType) {
        try {
            User user = requireUser();
            SubjectType type = SubjectType.fromClientValue(subjectType);
            requireChecklistAccess(user, type, subjectId);
            return ResponseEntity.ok(complianceService.getHistory(
                    type, subjectId, parseOptionalDocumentType(documentType)));
        } catch (UnauthorizedException e) {
            return forbidden(e);
        } catch (IllegalArgumentException e) {
            return badRequest(e);
        }
    }

    // ==================== HELPERS ====================

    private User requireUser() throws UnauthorizedException {
        User user = securityUtil.resolveCurrentUser();
        if (user == null) {
            throw new UnauthorizedException("Not authenticated");
        }
        return user;
    }

    /**
     * Coordinators (admin/caregiver) can view any checklist; an employee can
     * always view their own.
     */
    private void requireChecklistAccess(User user, SubjectType type, Long subjectId)
            throws UnauthorizedException {
        if (user.isAdmin() || user.isCaregiver()) {
            return;
        }
        if (type == SubjectType.EMPLOYEE) {
            if (user.getId().equals(subjectId)) {
                return;
            }
            // A patient id must never be conflated with an employee user id, so
            // reject explicitly instead of falling through to patient access.
            throw new UnauthorizedException(
                    "Admin or caregiver role required to view another employee's checklist");
        }
        authorizationService.requirePatientAccess(user, subjectId);
    }

    private SubjectType parseOptionalSubjectType(String raw) {
        return (raw == null || raw.isBlank()) ? null : SubjectType.fromClientValue(raw);
    }

    private UserFile.FileCategory parseOptionalDocumentType(String raw) {
        return (raw == null || raw.isBlank()) ? null : DocumentComplianceService.parseDocumentType(raw);
    }

    private ResponseEntity<Map<String, String>> forbidden(Exception e) {
        return ResponseEntity.status(HttpStatus.FORBIDDEN).body(Map.of("error", e.getMessage()));
    }

    private ResponseEntity<Map<String, String>> badRequest(Exception e) {
        return ResponseEntity.badRequest().body(Map.of("error", e.getMessage()));
    }
}
