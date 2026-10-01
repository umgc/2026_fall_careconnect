package com.careconnect.controller;

import com.careconnect.model.ConnectionRequest;
import com.careconnect.security.AuthorizationService;
import com.careconnect.service.ConnectionRequestService;
import com.careconnect.util.SecurityUtil;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import java.util.List;

import static org.mockito.Mockito.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

@ExtendWith(MockitoExtension.class)
        /*
         * MockitoExtension enables strict stubbing and automatic mock initialization.
         * Strict mode ensures we do not create unused or incorrect stubs.
         */
class ConnectionRequestControllerTest {

    private MockMvc mockMvc;

    @Mock
    private ConnectionRequestService connectionRequestService;
    /*
     * We mock the service to isolate controller behavior.
     * This ensures:
     * - No database calls
     * - No business logic execution
     * - Fast and deterministic unit tests
     */

    @Mock
    private SecurityUtil securityUtil;
    @Mock
    private AuthorizationService authorizationService;

    @InjectMocks
    private ConnectionRequestController controller;
    /*
     * Injects the mocked service into the controller.
     * Allows us to test controller behavior in isolation.
     */

    @BeforeEach
    void setUp() throws Exception {
        mockMvc = MockMvcBuilders
                .standaloneSetup(controller)
                .build();
        /*
         * standaloneSetup avoids loading the full Spring context.
         * This keeps the test lightweight and focused strictly
         * on HTTP mapping + controller logic.
         */
    }

    @Test
    void createConnectionRequest_shouldReturnSuccess() throws Exception {

        final ConnectionRequest saved = new ConnectionRequest();
        saved.setId(10L);

        when(connectionRequestService.createRequest(
                eq(1L),
                eq("patient@example.com"),
                eq("FAMILY"),
                eq("Hello")
        )).thenReturn(saved);
        /*
         * We stub the service call to return a saved entity.
         * eq(...) ensures exact argument matching.
         */

        mockMvc.perform(post("/v1/api/connection-requests/create")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "caregiverId": 1,
                                  "patientEmail": "patient@example.com",
                                  "relationshipType": "FAMILY",
                                  "message": "Hello"
                                }
                                """))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.message")
                        .value("Connection request sent successfully"))
                .andExpect(jsonPath("$.requestId").value(10L));
        /*
         * Validates:
         * - HTTP 200 status
         * - Correct success message
         * - Correct requestId returned from service
         */

        verify(connectionRequestService)
                .createRequest(1L, "patient@example.com", "FAMILY", "Hello");
        /*
         * Ensures the controller properly delegates to the service.
         */
    }

    @Test
    void createConnectionRequest_shouldReturnBadRequest_whenException() throws Exception {

        when(connectionRequestService.createRequest(any(), any(), any(), any()))
                .thenThrow(new RuntimeException("Invalid request"));
        /*
         * Simulates a service-layer failure.
         * The controller should catch this and return 400.
         */

        mockMvc.perform(post("/v1/api/connection-requests/create")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "caregiverId": 1,
                                  "patientEmail": "bad",
                                  "relationshipType": "FAMILY",
                                  "message": "Hello"
                                }
                                """))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error").value("Invalid request"));
        /*
         * Confirms:
         * - Exception is translated into HTTP 400
         * - Error message is returned in JSON body
         */
    }

    @Test
    void processConnectionRequest_shouldReturnAcceptedMessage() throws Exception {

        mockMvc.perform(get("/v1/api/connection-requests/process")
                        .param("token", "abc123")
                        .param("accept", "true"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.message")
                        .value("Connection request accepted successfully"));
        /*
         * Validates:
         * - Query parameters are correctly mapped
         * - Accept=true returns accepted message
         */

        verify(connectionRequestService)
                .processResponse("abc123", true);
        /*
         * Confirms correct delegation with boolean parameter.
         */
    }

    @Test
    void processConnectionRequest_shouldReturnRejectedMessage() throws Exception {

        mockMvc.perform(get("/v1/api/connection-requests/process")
                        .param("token", "abc123")
                        .param("accept", "false"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.message")
                        .value("Connection request rejected successfully"));

        verify(connectionRequestService)
                .processResponse("abc123", false);
        /*
         * Ensures boolean conversion from query parameter works correctly.
         */
    }

    @Test
    void processConnectionRequest_shouldReturnBadRequest_whenException() throws Exception {

        doThrow(new RuntimeException("Invalid token"))
                .when(connectionRequestService)
                .processResponse("bad", true);
        /*
         * doThrow() is required for stubbing void methods.
         * processResponse returns void, so when().thenThrow() cannot be used.
         */

        mockMvc.perform(get("/v1/api/connection-requests/process")
                        .param("token", "bad")
                        .param("accept", "true"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error").value("Invalid token"));
    }

    @Test
    void getPendingForPatient_shouldReturnList() throws Exception {

        when(connectionRequestService.getPendingRequestsForPatient(1L))
                .thenReturn(List.of(new ConnectionRequest()));

        mockMvc.perform(get("/v1/api/connection-requests/pending/patient/1"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(1));
        /*
         * Ensures:
         * - Path variable mapping works
         * - List serialization works
         * - HTTP 200 returned
         */

        verify(connectionRequestService)
                .getPendingRequestsForPatient(1L);
    }

    @Test
    void getPendingForPatient_shouldReturnBadRequest_whenException() throws Exception {

        when(connectionRequestService.getPendingRequestsForPatient(1L))
                .thenThrow(new RuntimeException());

        mockMvc.perform(get("/v1/api/connection-requests/pending/patient/1"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.length()").value(0));
        /*
         * On service failure, controller returns:
         * - HTTP 400
         * - Empty list
         */
    }

    @Test
    void getPendingByCaregiver_shouldReturnList() throws Exception {

        when(connectionRequestService.getPendingRequestsByCaregiver(2L))
                .thenReturn(List.of(new ConnectionRequest()));

        mockMvc.perform(get("/v1/api/connection-requests/pending/caregiver/2"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(1));

        verify(connectionRequestService)
                .getPendingRequestsByCaregiver(2L);
    }

    @Test
    void getPendingByCaregiver_shouldReturnBadRequest_whenException() throws Exception {

        when(connectionRequestService.getPendingRequestsByCaregiver(2L))
                .thenThrow(new RuntimeException());

        mockMvc.perform(get("/v1/api/connection-requests/pending/caregiver/2"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.length()").value(0));
    }
}