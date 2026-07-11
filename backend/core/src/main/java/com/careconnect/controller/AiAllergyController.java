package com.careconnect.controller;

import com.careconnect.security.Permission;
import com.careconnect.security.RequirePermission;

import com.careconnect.dto.AiAllergyDTO;
import com.careconnect.model.Allergy;
import com.careconnect.repository.AllergyRepository;
import com.careconnect.model.User;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.service.AiAllergyService;
import com.careconnect.util.SecurityUtil;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;

import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;

@Slf4j
@RestController
@RequiredArgsConstructor
@ConditionalOnProperty(name = "careconnect.ai.provider", havingValue = "bedrock")
@RequestMapping({"/api/ai", "/v1/api/ai"})
public class AiAllergyController {

    private final AiAllergyService aiAllergyService;
    private final AllergyRepository allergyRepository;
    private final SecurityUtil securityUtil;
    private final AuthorizationService authorizationService;

    @RequirePermission(Permission.USE_AI_FEATURES)


    @PostMapping(
            value = "/analyze/allergy",
            consumes = MediaType.APPLICATION_JSON_VALUE,
            produces = MediaType.APPLICATION_JSON_VALUE
    )
    public ResponseEntity<?> analyze(@Valid @RequestBody AiAllergyDTO.Request body) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        if (currentUser.isFamilyMember()) {
            throw new UnauthorizedException("This feature requires ADMIN, CAREGIVER, or PATIENT role");
        }
        Long pid = body.getPatientId();
        if (pid != null) {
            authorizationService.requirePatientAccess(currentUser, pid);
        }
        try {
            List<Allergy> history = pid == null
                    ? List.of()
                    : allergyRepository.findActiveAllergiesByPatientId(pid);

            AiAllergyDTO.Result result = aiAllergyService.analyze(body, history);

            return ResponseEntity.ok(Map.of(
                    "data", Map.of(
                            "allergen", result.getAllergen(),
                            "reaction", result.getReaction(),
                            "severity", result.getSeverity()
                    )
            ));
        } catch (Exception e) {
            log.error("AI allergy analyze failed", e);
            return ResponseEntity.badRequest().body(Map.of(
                    "error", "AI_ANALYZE_FAILED",
                    "message", e.getMessage()
            ));
        }
    }
}

