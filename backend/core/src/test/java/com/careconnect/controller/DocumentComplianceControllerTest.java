package com.careconnect.controller;

import com.careconnect.dto.ComplianceSummaryDTO;
import com.careconnect.dto.DocumentChecklistDTO;
import com.careconnect.dto.DocumentChecklistItemDTO;
import com.careconnect.dto.DocumentStatusHistoryDTO;
import com.careconnect.dto.DocumentStatusUpdateRequest;
import com.careconnect.model.DocumentRequirementStatus.SubjectType;
import com.careconnect.model.User;
import com.careconnect.model.UserFile.FileCategory;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.Role;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.service.DocumentComplianceService;
import com.careconnect.util.SecurityUtil;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import java.util.List;

import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

/**
 * Endpoint tests for {@link DocumentComplianceController}: HTTP status codes,
 * JSON response shape, permission enforcement and error handling for invalid
 * subject types, status values and missing reasons.
 */
@ExtendWith(MockitoExtension.class)
class DocumentComplianceControllerTest {

    private MockMvc mockMvc;

    @Mock private DocumentComplianceService complianceService;
    @Mock private SecurityUtil securityUtil;
    @Mock private AuthorizationService authorizationService;

    @InjectMocks
    private DocumentComplianceController controller;

    private User coordinator;
    private User patientUser;

    @BeforeEach
    void setUp() {
        mockMvc = MockMvcBuilders.standaloneSetup(controller).build();

        coordinator = new User();
        coordinator.setId(1L);
        coordinator.setEmail("coordinator@test.com");
        coordinator.setRole(Role.CAREGIVER);

        patientUser = new User();
        patientUser.setId(5L);
        patientUser.setEmail("patient@test.com");
        patientUser.setRole(Role.PATIENT);
    }

    private DocumentChecklistDTO sampleChecklist() {
        return DocumentChecklistDTO.builder()
                .subjectType("EMPLOYEE")
                .subjectId(2L)
                .subjectName("Jane Caregiver")
                .items(List.of(DocumentChecklistItemDTO.builder()
                        .documentType("CERTIFICATION")
                        .status("IN_PROGRESS")
                        .fileCount(1)
                        .build()))
                .requiredCount(9)
                .missingCount(8)
                .inProgressCount(1)
                .percentComplete(0)
                .build();
    }

    // ==================== DASHBOARD ====================

    @Test
    @DisplayName("GET /dashboard - unauthenticated -> 403")
    void dashboard_unauthenticated_forbidden() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(null);

        mockMvc.perform(get("/v1/api/document-compliance/dashboard"))
                .andExpect(status().isForbidden());
        verifyNoInteractions(complianceService);
    }

    @Test
    @DisplayName("GET /dashboard - non-coordinator -> 403 with error body")
    void dashboard_nonCoordinator_forbidden() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(patientUser);
        doThrow(new UnauthorizedException("Admin or caregiver role required"))
                .when(authorizationService).requireAdminOrCaregiver(patientUser);

        mockMvc.perform(get("/v1/api/document-compliance/dashboard"))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.error").value("Admin or caregiver role required"));
        verifyNoInteractions(complianceService);
    }

    @Test
    @DisplayName("GET /dashboard - coordinator -> 200 with summary rows")
    void dashboard_coordinator_returnsSummaries() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(coordinator);
        when(complianceService.getDashboard(null)).thenReturn(List.of(
                ComplianceSummaryDTO.builder()
                        .subjectType("EMPLOYEE").subjectId(2L).subjectName("Jane Caregiver")
                        .requiredCount(9).missingCount(7).inProgressCount(1).completeCount(1)
                        .percentComplete(11).blocked(true)
                        .build()));

        mockMvc.perform(get("/v1/api/document-compliance/dashboard"))
                .andExpect(status().isOk())
                .andExpect(content().contentType(MediaType.APPLICATION_JSON))
                .andExpect(jsonPath("$[0].subjectType").value("EMPLOYEE"))
                .andExpect(jsonPath("$[0].subjectName").value("Jane Caregiver"))
                .andExpect(jsonPath("$[0].missingCount").value(7))
                .andExpect(jsonPath("$[0].blocked").value(true));
    }

    @Test
    @DisplayName("GET /dashboard - subjectType filter is forwarded to the service")
    void dashboard_subjectTypeFilter_forwarded() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(coordinator);
        when(complianceService.getDashboard(SubjectType.CARE_CIRCLE)).thenReturn(List.of());

        mockMvc.perform(get("/v1/api/document-compliance/dashboard")
                        .param("subjectType", "CARE_CIRCLE"))
                .andExpect(status().isOk());
        verify(complianceService).getDashboard(SubjectType.CARE_CIRCLE);
    }

    @Test
    @DisplayName("GET /dashboard - invalid subjectType -> 400 with error body")
    void dashboard_invalidSubjectType_badRequest() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(coordinator);

        mockMvc.perform(get("/v1/api/document-compliance/dashboard")
                        .param("subjectType", "BOGUS"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error").exists());
    }

    // ==================== CHECKLIST ====================

    @Test
    @DisplayName("GET /checklist - coordinator can view any subject -> 200 with items")
    void checklist_coordinator_ok() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(coordinator);
        when(complianceService.getChecklist(SubjectType.EMPLOYEE, 2L)).thenReturn(sampleChecklist());

        mockMvc.perform(get("/v1/api/document-compliance/checklist/EMPLOYEE/2"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.subjectName").value("Jane Caregiver"))
                .andExpect(jsonPath("$.items[0].documentType").value("CERTIFICATION"))
                .andExpect(jsonPath("$.items[0].status").value("IN_PROGRESS"))
                .andExpect(jsonPath("$.requiredCount").value(9));
    }

    @Test
    @DisplayName("GET /checklist - non-coordinator can view their own employee checklist")
    void checklist_selfEmployee_ok() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(patientUser); // id 5, not a coordinator
        when(complianceService.getChecklist(SubjectType.EMPLOYEE, 5L)).thenReturn(sampleChecklist());

        mockMvc.perform(get("/v1/api/document-compliance/checklist/EMPLOYEE/5"))
                .andExpect(status().isOk());
        // Self-access must not require patient-level authorization
        verify(authorizationService, never()).requirePatientAccess(any(), anyLong());
    }

    @Test
    @DisplayName("GET /checklist - care-circle access denied for unrelated user -> 403")
    void checklist_careCircleUnauthorized_forbidden() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(patientUser);
        doThrow(new UnauthorizedException("No access to this patient"))
                .when(authorizationService).requirePatientAccess(patientUser, 9L);

        mockMvc.perform(get("/v1/api/document-compliance/checklist/CARE_CIRCLE/9"))
                .andExpect(status().isForbidden());
        verifyNoInteractions(complianceService);
    }

    @Test
    @DisplayName("GET /checklist - invalid subject type -> 400")
    void checklist_invalidSubjectType_badRequest() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(coordinator);

        mockMvc.perform(get("/v1/api/document-compliance/checklist/HOUSEHOLD/2"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error").exists());
    }

    @Test
    @DisplayName("GET /checklist - unknown subject id -> 400 (service rejects)")
    void checklist_unknownSubject_badRequest() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(coordinator);
        when(complianceService.getChecklist(SubjectType.EMPLOYEE, 999L))
                .thenThrow(new IllegalArgumentException("EMPLOYEE subject not found: 999"));

        mockMvc.perform(get("/v1/api/document-compliance/checklist/EMPLOYEE/999"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error").value("EMPLOYEE subject not found: 999"));
    }

    // ==================== MISSING + EXPORT ====================

    @Test
    @DisplayName("GET /missing - filters forwarded, 200 with list")
    void missing_filtersForwarded() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(coordinator);
        when(complianceService.listMissingDocuments(SubjectType.EMPLOYEE, FileCategory.TAX_FORM))
                .thenReturn(List.of());

        mockMvc.perform(get("/v1/api/document-compliance/missing")
                        .param("subjectType", "EMPLOYEE")
                        .param("documentType", "TAX_FORM"))
                .andExpect(status().isOk());
        verify(complianceService).listMissingDocuments(SubjectType.EMPLOYEE, FileCategory.TAX_FORM);
    }

    @Test
    @DisplayName("GET /missing/export - returns CSV attachment")
    void export_returnsCsvAttachment() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(coordinator);
        when(complianceService.exportMissingDocumentsCsv(null, null))
                .thenReturn("Subject Type,Subject ID,Subject Name,Document Type,Status,Notes,Last Updated\n");

        mockMvc.perform(get("/v1/api/document-compliance/missing/export"))
                .andExpect(status().isOk())
                .andExpect(header().string("Content-Disposition",
                        "attachment; filename=\"missing-documents.csv\""))
                .andExpect(content().contentTypeCompatibleWith("text/csv"))
                .andExpect(content().string(org.hamcrest.Matchers.startsWith("Subject Type,")));
    }

    @Test
    @DisplayName("GET /missing/export - non-coordinator -> 403")
    void export_nonCoordinator_forbidden() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(patientUser);
        doThrow(new UnauthorizedException("Admin or caregiver role required"))
                .when(authorizationService).requireAdminOrCaregiver(patientUser);

        mockMvc.perform(get("/v1/api/document-compliance/missing/export"))
                .andExpect(status().isForbidden());
        verifyNoInteractions(complianceService);
    }

    // ==================== STATUS UPDATE ====================

    @Test
    @DisplayName("PUT /status - valid transition -> 200 with refreshed item")
    void updateStatus_valid_ok() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(coordinator);
        when(complianceService.updateStatus(any(DocumentStatusUpdateRequest.class), eq(coordinator)))
                .thenReturn(DocumentChecklistItemDTO.builder()
                        .documentType("CERTIFICATION")
                        .status("COMPLETE")
                        .tracked(true)
                        .build());

        mockMvc.perform(put("/v1/api/document-compliance/status")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"subjectType":"EMPLOYEE","subjectId":2,
                                 "documentType":"CERTIFICATION","status":"COMPLETE",
                                 "reason":"Verified against original"}
                                """))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("COMPLETE"))
                .andExpect(jsonPath("$.tracked").value(true));
    }

    @Test
    @DisplayName("PUT /status - missing reason -> 400 with error message")
    void updateStatus_missingReason_badRequest() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(coordinator);
        when(complianceService.updateStatus(any(), eq(coordinator)))
                .thenThrow(new IllegalArgumentException(
                        "A reason is required for every status change"));

        mockMvc.perform(put("/v1/api/document-compliance/status")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"subjectType":"EMPLOYEE","subjectId":2,
                                 "documentType":"CERTIFICATION","status":"REJECTED"}
                                """))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error")
                        .value("A reason is required for every status change"));
    }

    @Test
    @DisplayName("PUT /status - non-coordinator -> 403, service never called")
    void updateStatus_nonCoordinator_forbidden() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(patientUser);
        doThrow(new UnauthorizedException("Admin or caregiver role required"))
                .when(authorizationService).requireAdminOrCaregiver(patientUser);

        mockMvc.perform(put("/v1/api/document-compliance/status")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"subjectType":"EMPLOYEE","subjectId":2,
                                 "documentType":"CERTIFICATION","status":"COMPLETE",
                                 "reason":"r"}
                                """))
                .andExpect(status().isForbidden());
        verifyNoInteractions(complianceService);
    }

    // ==================== HISTORY ====================

    @Test
    @DisplayName("GET /history - returns audit entries with who/when/why")
    void history_returnsAuditEntries() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(coordinator);
        when(complianceService.getHistory(SubjectType.EMPLOYEE, 2L, null))
                .thenReturn(List.of(DocumentStatusHistoryDTO.builder()
                        .id(1L)
                        .documentType("CERTIFICATION")
                        .previousStatus("IN_PROGRESS")
                        .newStatus("COMPLETE")
                        .changedBy(1L)
                        .changedByName("Coordinator")
                        .reason("Verified")
                        .build()));

        mockMvc.perform(get("/v1/api/document-compliance/history/EMPLOYEE/2"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].previousStatus").value("IN_PROGRESS"))
                .andExpect(jsonPath("$[0].newStatus").value("COMPLETE"))
                .andExpect(jsonPath("$[0].changedByName").value("Coordinator"))
                .andExpect(jsonPath("$[0].reason").value("Verified"));
    }

    @Test
    @DisplayName("GET /history - documentType filter is forwarded")
    void history_documentTypeFilter_forwarded() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(coordinator);
        when(complianceService.getHistory(SubjectType.EMPLOYEE, 2L, FileCategory.TAX_FORM))
                .thenReturn(List.of());

        mockMvc.perform(get("/v1/api/document-compliance/history/EMPLOYEE/2")
                        .param("documentType", "TAX_FORM"))
                .andExpect(status().isOk());
        verify(complianceService).getHistory(SubjectType.EMPLOYEE, 2L, FileCategory.TAX_FORM);
    }

    // ==================== REQUIRED DOCUMENTS ====================

    @Test
    @DisplayName("GET /required-documents - lists the tracked sets per subject type")
    void requiredDocuments_listsBothSets() throws Exception {
        mockMvc.perform(get("/v1/api/document-compliance/required-documents"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.EMPLOYEE").isArray())
                .andExpect(jsonPath("$.CARE_CIRCLE").isArray());
    }
}
