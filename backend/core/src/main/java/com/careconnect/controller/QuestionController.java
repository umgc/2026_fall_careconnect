package com.careconnect.controller;

import com.careconnect.security.Permission;
import com.careconnect.security.RequirePermission;

import com.careconnect.dto.QuestionDTO;
import com.careconnect.dto.QuestionUpsertDTO;
import com.careconnect.model.User;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.service.QuestionService;
import com.careconnect.util.SecurityUtil;
import jakarta.validation.Valid;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;

/**
 * REST controller for managing Question entities.
 *
 * Matches frontend routes:
 *   GET  /api/questions
 *   GET  /api/questions/{id}
 *   POST /api/questions
 *   PUT  /api/questions/{id}
 *   PATCH /api/questions/{id}/active
 *
 * Also supports /v1/api/... for backward compatibility.
 */
@RestController
@RequestMapping(path = {"/api/questions", "/v1/api/questions"}) // supports both
public class QuestionController {

    private final QuestionService questions;
    private final SecurityUtil securityUtil;
    private final AuthorizationService authorizationService;

    public QuestionController(QuestionService questions, SecurityUtil securityUtil, AuthorizationService authorizationService) {
        this.questions = questions;
        this.securityUtil = securityUtil;
        this.authorizationService = authorizationService;
    }

    /** GET /api/questions?active=true|false */
    @RequirePermission(Permission.VIEW_ASSIGNED_PATIENTS)

    @GetMapping
    public List<QuestionDTO> list(@RequestParam(required = false) Boolean active) {
        return questions.listQuestions(active);
    }

    /** GET /api/questions/{id} */
    @RequirePermission(Permission.VIEW_ASSIGNED_PATIENTS)

    @GetMapping("/{id}")
    public ResponseEntity<QuestionDTO> one(@PathVariable Long id) {
        return questions.getOne(id)
                .map(ResponseEntity::ok)
                .orElseGet(() -> ResponseEntity.notFound().build());
    }

    /** POST /api/questions */
    @RequirePermission(Permission.CREATE_TASKS)

    @PostMapping
    public ResponseEntity<QuestionDTO> create(@Valid @RequestBody QuestionUpsertDTO body) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireAdmin(currentUser);
        QuestionDTO created = questions.create(body);
        return ResponseEntity.ok(created);
    }

    /** PUT /api/questions/{id} */
    @RequirePermission(Permission.UPDATE_TASKS)

    @PutMapping("/{id}")
    public ResponseEntity<QuestionDTO> update(@PathVariable Long id,
                                              @Valid @RequestBody QuestionUpsertDTO body) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireAdmin(currentUser);
        return questions.update(id, body)
                .map(ResponseEntity::ok)
                .orElseGet(() -> ResponseEntity.notFound().build());
    }

    /** PATCH /api/questions/{id}/active?active=true|false */
    @RequirePermission(Permission.UPDATE_TASKS)

    @PatchMapping("/{id}/active")
    public ResponseEntity<QuestionDTO> setActive(@PathVariable Long id,
                                                 @RequestParam boolean active) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireAdmin(currentUser);
        return questions.setActive(id, active)
                .map(ResponseEntity::ok)
                .orElseGet(() -> ResponseEntity.notFound().build());
    }
}
