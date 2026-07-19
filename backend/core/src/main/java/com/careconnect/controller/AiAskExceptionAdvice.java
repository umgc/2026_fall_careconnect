package com.careconnect.controller;

import com.careconnect.dto.ai.AiAskRequest;
import com.careconnect.dto.ai.AiAskResponse;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.service.ai.ask.AiAskService;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

import java.util.UUID;

/** Keeps failures raised before {@link AiAskController#ask} on the Ask AI response contract. */
@RestControllerAdvice(assignableTypes = AiAskController.class)
public class AiAskExceptionAdvice {

    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<AiAskResponse> handleValidation(
            final MethodArgumentNotValidException exception) {
        final UUID sessionId = exception.getBindingResult().getTarget() instanceof AiAskRequest request
                ? request.sessionId()
                : null;
        return withheld(
                HttpStatus.BAD_REQUEST,
                sessionId,
                "INVALID_REQUEST",
                "Request validation failed");
    }

    @ExceptionHandler(HttpMessageNotReadableException.class)
    public ResponseEntity<AiAskResponse> handleMalformedJson(
            final HttpMessageNotReadableException exception) {
        return withheld(
                HttpStatus.BAD_REQUEST,
                null,
                "INVALID_REQUEST",
                "Request body is malformed");
    }

    @ExceptionHandler(UnauthorizedException.class)
    public ResponseEntity<AiAskResponse> handleUnauthorized(
            final UnauthorizedException exception) {
        return withheld(
                HttpStatus.FORBIDDEN,
                null,
                "FORBIDDEN",
                "Ask AI access is not permitted");
    }

    private static ResponseEntity<AiAskResponse> withheld(
            final HttpStatus status,
            final UUID sessionId,
            final String errorCode,
            final String message) {
        return ResponseEntity.status(status)
                .body(AiAskService.withheld(
                        UUID.randomUUID(),
                        UUID.randomUUID(),
                        sessionId,
                        errorCode,
                        message,
                        null));
    }
}
