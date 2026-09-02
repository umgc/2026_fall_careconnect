package com.careconnect.controller;

import com.careconnect.security.Permission;
import com.careconnect.security.RequirePermission;

import com.careconnect.model.User;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.service.DeepSeekService;
import com.careconnect.service.DeepSeekService.DeepSeekChatRequest;
import com.careconnect.service.DeepSeekService.DeepSeekResponse;
import com.careconnect.service.DeepSeekService.Message;
import com.careconnect.util.SecurityUtil;
import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.NotNull;
import lombok.Data;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;

import org.springframework.web.bind.annotation.*;

import java.util.List;

@Slf4j
@RestController
@RequestMapping("/v1/api/ai/deepseek")
@RequiredArgsConstructor
@ConditionalOnProperty(name = "careconnect.deepseek.enabled", havingValue = "true", matchIfMissing = true)
public class DeepSeekController {

    private final DeepSeekService deepSeekService;
    private final SecurityUtil securityUtil;
    private final AuthorizationService authorizationService;

    // Full JSON in/out (Option B)
    @RequirePermission(Permission.CREATE_TASKS)

    @PostMapping("/chat")
    public ResponseEntity<?> chat(@Valid @RequestBody ChatBody body) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        if (currentUser.isFamilyMember()) {
            throw new UnauthorizedException("This feature requires ADMIN, CAREGIVER, or PATIENT role");
        }
        try {
            DeepSeekChatRequest req = new DeepSeekChatRequest();
            req.setModel(body.getModel());
            req.setMessages(body.getMessages());
            req.setTemperature(body.getTemperature());
            req.setMaxTokens(body.getMaxTokens());
            req.setStream(false);

            DeepSeekResponse resp = deepSeekService.sendChatRequest(req);
            return ResponseEntity.ok(resp); // return provider-style JSON
        } catch (Exception e) {
            log.error("DeepSeek chat error", e);
            return ResponseEntity.status(HttpStatus.BAD_GATEWAY)
                    .body(new ErrorPayload("DEEPSEEK_ERROR", e.getMessage()));
        }
    }

    // --- Request/Response DTOs for the controller ---

    @Data
    public static class ChatBody {
        @NotNull
        private String model;                      // e.g. "deepseek-chat" / "deepseek-reasoner"
        @NotEmpty
        private List<Message> messages;           // [{role:"system|user|assistant", content:"..."}]
        @Min(0)
        @Max(2)
        private Double temperature = 0.7;         // optional
        @Min(1)
        @Max(4096)
        private Integer maxTokens = 512;          // optional
    }

    @Data
    public static class ErrorPayload {
        private final String code;
        private final String message;
    }
}
