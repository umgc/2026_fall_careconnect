package com.careconnect.controller;

import com.careconnect.dto.conditiondetection.ConditionFlagsResponse;
import com.careconnect.exception.AppException;
import com.careconnect.model.User;
import com.careconnect.repository.UserRepository;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.service.conditiondetection.ConditionFlagQueryService;
import io.swagger.v3.oas.annotations.Operation;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/** AI condition screening flags for a call. Never available to patients. */
@RestController
@RequestMapping("/api/v3/calls")
@RequiredArgsConstructor
public class ConditionFlagController {

    private final ConditionFlagQueryService queryService;
    private final UserRepository userRepository;

    @GetMapping("/{callId}/condition-flags")
    @PreAuthorize("hasAnyRole('CAREGIVER','FAMILY_MEMBER','ADMIN')")
    @Operation(summary = "Get AI condition screening flags and per-model status for a call")
    public ResponseEntity<ConditionFlagsResponse> getConditionFlags(@PathVariable final String callId)
            throws UnauthorizedException {
        return ResponseEntity.ok(queryService.getFlags(currentUser(), callId));
    }

    private User currentUser() {
        final Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        if (authentication == null) {
            throw new AppException(HttpStatus.UNAUTHORIZED, "User not authenticated");
        }
        return userRepository.findByEmail(authentication.getName())
                .orElseThrow(() -> new AppException(HttpStatus.UNAUTHORIZED, "User not authenticated"));
    }
}
