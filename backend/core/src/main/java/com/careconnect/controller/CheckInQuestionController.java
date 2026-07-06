package com.careconnect.controller;

import com.careconnect.security.Permission;
import com.careconnect.security.RequirePermission;

import com.careconnect.dto.CheckInCreateRequestDTO;
import com.careconnect.dto.CheckInCreateResponseDTO;
import com.careconnect.dto.CheckInSummaryDTO;
import com.careconnect.dto.QuestionDTO;
import com.careconnect.dto.SubmitAnswersRequestDTO;
import com.careconnect.dto.SubmitAnswersResponseDTO;
import com.careconnect.model.User;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.service.AnswerSubmissionService;
import com.careconnect.service.CheckInSnapshotService;
import com.careconnect.service.QuestionService;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import com.careconnect.util.SecurityUtil;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Optional;

@RestController
@RequestMapping(path = {"/api/checkins", "/v1/api/checkins"})
public class CheckInQuestionController {

    private final QuestionService questionService;
    private final CheckInSnapshotService checkInSnapshotService;
    private final AnswerSubmissionService answerSubmissionService;
    private final SecurityUtil securityUtil;
    private final AuthorizationService authorizationService;

    public CheckInQuestionController(
            QuestionService questionService,
            CheckInSnapshotService checkInSnapshotService,
            AnswerSubmissionService answerSubmissionService,
            SecurityUtil securityUtil,
            AuthorizationService authorizationService
    ) {
        this.questionService = questionService;
        this.checkInSnapshotService = checkInSnapshotService;
        this.answerSubmissionService = answerSubmissionService;
        this.securityUtil = securityUtil;
        this.authorizationService = authorizationService;
    }

    /**
     * GET /api/checkins/{checkInId}/questions
     * GET /v1/api/checkins/{checkInId}/questions
     */
    @RequirePermission(Permission.VIEW_HEALTH_DATA)

    @GetMapping("/{checkInId}/questions")
    public ResponseEntity<List<QuestionDTO>> getQuestions(
            @PathVariable("checkInId") Long checkInId,
            HttpServletRequest request
    ) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        Long patientId = checkInSnapshotService.getPatientIdForCheckIn(checkInId);
        authorizationService.requirePatientAccess(currentUser, patientId);

        String uri = request.getRequestURI();
        String contextPath = request.getContextPath();
        if (contextPath != null && !contextPath.isEmpty() && uri.startsWith(contextPath)) {
            uri = uri.substring(contextPath.length());
        }
        if (uri.startsWith("/v1/api/")) {
            // Backward compatibility for legacy clients.
            return ResponseEntity.ok(questionService.findActiveOrdered());
        }
        List<QuestionDTO> questions = checkInSnapshotService.getSnapshotQuestions(checkInId);
        return ResponseEntity.ok(questions);
    }

    /**
     * GET /api/checkins/patients/{patientId}
     * GET /v1/api/checkins/patients/{patientId}
     */
    @RequirePermission(Permission.VIEW_HEALTH_DATA)
    @GetMapping("/patients/{patientId}")
    public ResponseEntity<List<CheckInSummaryDTO>> listPatientCheckIns(
            @PathVariable("patientId") Long patientId
    ) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requirePatientAccess(currentUser, patientId);
        return ResponseEntity.ok(checkInSnapshotService.listCheckInsForPatient(patientId));
    }

    /**
     * GET /api/checkins/patients/{patientId}/latest
     * GET /v1/api/checkins/patients/{patientId}/latest
     */
    @RequirePermission(Permission.VIEW_HEALTH_DATA)
    @GetMapping("/patients/{patientId}/latest")
    public ResponseEntity<CheckInSummaryDTO> getLatestPatientCheckIn(
            @PathVariable("patientId") Long patientId
    ) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requirePatientAccess(currentUser, patientId);
        Optional<CheckInSummaryDTO> latest = checkInSnapshotService.getLatestCheckInForPatient(patientId);
        return latest.map(ResponseEntity::ok).orElseGet(() -> ResponseEntity.noContent().build());
    }

    /**
     * POST /api/checkins
     * POST /v1/api/checkins
     */
    @RequirePermission(Permission.CREATE_TASKS)
    @PostMapping
    public ResponseEntity<CheckInCreateResponseDTO> createCheckIn(
            @Valid @RequestBody CheckInCreateRequestDTO request
    ) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requirePatientAccess(currentUser, request.patientId());
        CheckInCreateResponseDTO created = checkInSnapshotService.createCheckInWithSnapshot(request);
        return ResponseEntity.status(HttpStatus.CREATED).body(created);
    }

    /**
     * POST /api/checkins/{checkInId}/answers
     * POST /v1/api/checkins/{checkInId}/answers
     */
    @RequirePermission(Permission.COMPLETE_TASKS)
    @PostMapping("/{checkInId}/answers")
    public ResponseEntity<SubmitAnswersResponseDTO> submitAnswers(
            @PathVariable Long checkInId,
            @Valid @RequestBody SubmitAnswersRequestDTO request
    ) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        Long patientId = checkInSnapshotService.getPatientIdForCheckIn(checkInId);
        authorizationService.requirePatientAccess(currentUser, patientId);
        
        SubmitAnswersResponseDTO result = answerSubmissionService.submitAnswers(checkInId, request);
        return ResponseEntity.status(HttpStatus.CREATED).body(result);
    }
}
