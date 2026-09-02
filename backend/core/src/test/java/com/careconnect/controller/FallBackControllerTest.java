package com.careconnect.controller;

import jakarta.servlet.RequestDispatcher;
import jakarta.servlet.http.HttpServletRequest;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
        /*
         * MockitoExtension enables strict stubbing and manages mock lifecycle.
         * No Spring context needed — the controller has no injected dependencies.
         */
class FallBackControllerTest {

    @InjectMocks
    private FallbackController controller;
    /*
     * No-arg constructor is used; no fields to inject.
     * @InjectMocks simply instantiates the controller under test.
     */

    @Mock
    private HttpServletRequest request;
    /*
     * Mocked to control what getAttribute() and getRequestURI() return
     * without requiring a real servlet container.
     */

    @Test
    void handleError_returns404_whenStatusIs404AndErrorUriIsPresent() throws Exception {
        /*
         * Covers:
         * - statusAttr instanceof Integer → true (status resolved from attribute)
         * - path != null branch (ERROR_REQUEST_URI is present, getRequestURI skipped)
         * - status == 404 → true (NOT_FOUND response path)
         */
        when(request.getAttribute(RequestDispatcher.ERROR_STATUS_CODE)).thenReturn(404);
        when(request.getAttribute(RequestDispatcher.ERROR_REQUEST_URI)).thenReturn("/api/unknown");

        final ResponseEntity<String> response = controller.handleError(request);

        assertEquals(HttpStatus.NOT_FOUND, response.getStatusCode());
        assertEquals("No endpoint found for path: /api/unknown", response.getBody());
    }

    @Test
    void handleError_returnsErrorStatus_whenStatusIsNot404AndErrorUriIsPresent() throws Exception {
        /*
         * Covers:
         * - statusAttr instanceof Integer → true
         * - path != null branch
         * - status == 404 → false (generic error response path)
         */
        when(request.getAttribute(RequestDispatcher.ERROR_STATUS_CODE)).thenReturn(500);
        when(request.getAttribute(RequestDispatcher.ERROR_REQUEST_URI)).thenReturn("/api/broken");

        final ResponseEntity<String> response = controller.handleError(request);

        assertEquals(HttpStatus.INTERNAL_SERVER_ERROR, response.getStatusCode());
        assertEquals("Error 500 for path: /api/broken", response.getBody());
    }

    @Test
    void handleError_defaults404AndUsesRequestUri_whenStatusAttributeAndErrorUriAreNull() throws Exception {
        /*
         * Covers:
         * - statusAttr instanceof Integer → false (null attribute, status defaults to 404)
         * - path == null → true (ERROR_REQUEST_URI absent, falls back to getRequestURI())
         * - status == 404 → true (NOT_FOUND response path via default)
         */
        when(request.getAttribute(RequestDispatcher.ERROR_STATUS_CODE)).thenReturn(null);
        when(request.getAttribute(RequestDispatcher.ERROR_REQUEST_URI)).thenReturn(null);
        when(request.getRequestURI()).thenReturn("/fallback/uri");

        final ResponseEntity<String> response = controller.handleError(request);

        assertEquals(HttpStatus.NOT_FOUND, response.getStatusCode());
        assertEquals("No endpoint found for path: /fallback/uri", response.getBody());
    }
}
