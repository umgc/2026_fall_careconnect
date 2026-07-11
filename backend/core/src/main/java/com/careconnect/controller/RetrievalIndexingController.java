package com.careconnect.controller;

import com.careconnect.model.User;
import com.careconnect.repository.UserRepository;
import com.careconnect.service.ai.RetrievalIndexingService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import com.careconnect.exception.AppException;
import org.springframework.http.HttpStatus;

import java.util.Map;

/**
 * Triggers Ask AI retrieval indexing for a patient (Task 4.2).
 * POST /v1/api/ai/index/{patientId}
 */
@Slf4j
@RestController
@RequestMapping("/v1/api/ai/index")
@RequiredArgsConstructor
public class RetrievalIndexingController {

    private final RetrievalIndexingService retrievalIndexingService;
    private final UserRepository userRepository;

    private User getCurrentUser() {
        Authentication auth = SecurityContextHolder.getContext().getAuthentication();
        return userRepository.findByEmail(auth.getName())
                .orElseThrow(() -> new AppException(HttpStatus.UNAUTHORIZED, "User not authenticated"));
    }

    @PostMapping("/{patientId}")
    public ResponseEntity<Map<String, Object>> index(@PathVariable Long patientId) {
        User caller = getCurrentUser();
        log.info("POST /v1/api/ai/index/{} — caller={}", patientId, caller.getId());

        int chunksIndexed = retrievalIndexingService.indexPatient(patientId);

        return ResponseEntity.ok(Map.of(
                "patientId", patientId,
                "chunksIndexed", chunksIndexed,
                "status", "ok"
        ));
    }
}