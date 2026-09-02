package com.careconnect.controller;

import static org.hamcrest.Matchers.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.isNull;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

import java.time.LocalDateTime;
import java.util.Collections;
import java.util.List;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;

import com.careconnect.dto.ChatConversationSummary;
import com.careconnect.dto.ChatMessageSummary;
import com.careconnect.dto.ChatRequest;
import com.careconnect.dto.ChatResponse;
import com.careconnect.dto.UserAIConfigDTO;
import com.careconnect.security.AuthorizationService;
import com.careconnect.model.ChatConversation.ChatType;
import com.careconnect.model.ChatMessage;
import com.careconnect.model.UserAIConfig.AIProvider;
import com.careconnect.repository.ChatConversationRepository;
import com.careconnect.service.AIChatService;
import com.careconnect.service.ChatCleanupService;
import com.careconnect.service.UserAIConfigService;
import com.careconnect.model.User;
import com.careconnect.security.Role;
import com.careconnect.util.SecurityUtil;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.context.bean.override.mockito.MockitoBean;

/**
 * Unit tests for {@link AIChatController}, covering the HTTP layer of all
 * AI-chat, conversation management, and user-config endpoints.
 *
 * <p><b>Why @WebMvcTest + MockMvc?</b><br>
 * {@code @WebMvcTest} spins up only the Spring MVC slice (controllers, filters,
 * argument resolvers) without loading a full application context or a real
 * database.  This makes the tests fast and focused: they verify that the
 * controller routes requests to the correct service methods, applies the right
 * HTTP status codes, and serialises/deserialises JSON correctly — without caring
 * about the actual AI or persistence logic inside the services.
 *
 * <p>All service and repository collaborators are replaced with Mockito mocks
 * via {@code @MockitoBean} so that each test exercises only the controller layer
 * in isolation.  Security filters are disabled with
 * {@code @AutoConfigureMockMvc(addFilters = false)} to keep tests focused on
 * request routing and response shaping rather than authentication concerns.
 *
 * <p>{@code @TestPropertySource} sets {@code careconnect.ai.enabled=true} so
 * that the controller's {@code @ConditionalOnProperty} guard is satisfied and
 * the bean is registered in the MVC slice.
 */
@WebMvcTest(AIChatController.class)
@AutoConfigureMockMvc(addFilters = false)
@TestPropertySource(properties = "careconnect.ai.enabled=true")
class AIChatControllerTest {

    @Autowired
    private MockMvc mockMvc;

    // --- Mocked collaborators ---
    // Each bean below is replaced with a Mockito stub so the controller can be
    // instantiated without real AI providers, databases, or cleanup schedulers.

    @MockitoBean
    private AIChatService aiChatService;

    @MockitoBean
    private UserAIConfigService userAIConfigService;

    @MockitoBean
    private ChatConversationRepository chatConversationRepository;

    @MockitoBean
    private ChatCleanupService chatCleanupService;

    @MockitoBean
    private SecurityUtil securityUtil;

    @MockitoBean
    private AuthorizationService authorizationService;

    @Autowired
    private ObjectMapper objectMapper;

    // --- Test fixtures ---
    // Pre-built objects reused across tests to avoid repetitive construction.

    private ChatRequest sampleRequest;
    private ChatResponse successResponse;
    private ChatConversationSummary sampleConversation;
    private ChatMessageSummary sampleMessage;
    private UserAIConfigDTO sampleConfig;

    @BeforeEach
    void setUp() throws Exception {
        objectMapper.registerModule(new JavaTimeModule());

        // Stub securityUtil.resolveCurrentUser() so that controller-level
        // role checks (e.g. isFamilyMember()) do not NPE.
        final User mockUser = new User();
        mockUser.setId(1L);
        mockUser.setEmail("testuser@test.com");
        mockUser.setRole(Role.PATIENT);
        Mockito.when(securityUtil.resolveCurrentUser()).thenReturn(mockUser);

        sampleRequest = ChatRequest.builder()
                .userId(1L)
                .patientId(2L)
                .message("How is my patient doing?")
                .chatType(ChatType.GENERAL_SUPPORT)
                .build();

        successResponse = ChatResponse.builder()
                .conversationId("conv-123")
                .aiResponse("Your patient is doing well.")
                .success(true)
                .isNewConversation(false)
                .timestamp(LocalDateTime.now())
                .build();

        sampleConversation = ChatConversationSummary.builder()
                .conversationId("conv-123")
                .title("General Chat")
                .chatType(ChatType.GENERAL_SUPPORT)
                .totalMessages(5)
                .isActive(true)
                .build();

        sampleMessage = ChatMessageSummary.builder()
                .messageId(10L)
                .content("Hello!")
                .messageType(ChatMessage.MessageType.USER)
                .createdAt(LocalDateTime.now())
                .build();

        sampleConfig = UserAIConfigDTO.builder()
                .id(1L)
                .userId(1L)
                .patientId(2L)
                .aiProvider(AIProvider.OPENAI)
                .build();
    }

    // -----------------------------------------------------------------------
    // POST /v1/api/ai-chat/chat
    // -----------------------------------------------------------------------

    /**
     * Verifies that POST /v1/api/ai-chat/chat returns HTTP 200 and includes
     * the conversation ID and success flag in the response body when the AI
     * service processes the message successfully.
     *
     * <p>{@link AIChatService#processChat} is stubbed to return
     * {@code successResponse} containing {@code success=true}.  The test
     * confirms that the controller serialises the response object correctly
     * and maps a successful result to a 200 status.
     */
    @Test
    @DisplayName("POST /chat - success returns 200 with AI response body")
    void sendMessage_success_returns200() throws Exception {
        Mockito.when(aiChatService.processChat(any(ChatRequest.class))).thenReturn(successResponse);

        mockMvc.perform(post("/v1/api/ai-chat/chat")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(sampleRequest)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.conversationId", is("conv-123")))
                .andExpect(jsonPath("$.success", is(true)));

        Mockito.verify(aiChatService).processChat(any(ChatRequest.class));
    }

    /**
     * Verifies that POST /v1/api/ai-chat/chat returns HTTP 400 when the AI
     * service indicates a failure in its response (i.e., {@code success=false}).
     *
     * <p>The service is stubbed to return a failure {@link ChatResponse} with
     * {@code errorCode="AI_ERROR"}.  The test confirms that the controller maps
     * a service-reported failure to a 400 Bad Request and includes the error
     * details in the JSON body, allowing the client to surface a meaningful
     * error message.
     */
    @Test
    @DisplayName("POST /chat - service returns failure returns 400 with error details")
    void sendMessage_serviceReturnsFailure_returns400() throws Exception {
        final ChatResponse failResponse = ChatResponse.builder()
                .success(false)
                .errorMessage("AI unavailable")
                .errorCode("AI_ERROR")
                .build();
        Mockito.when(aiChatService.processChat(any(ChatRequest.class))).thenReturn(failResponse);

        mockMvc.perform(post("/v1/api/ai-chat/chat")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(sampleRequest)))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.success", is(false)))
                .andExpect(jsonPath("$.errorCode", is("AI_ERROR")));
    }

    /**
     * Verifies that POST /v1/api/ai-chat/chat returns HTTP 500 with an
     * {@code INTERNAL_ERROR} code when the AI service throws an unexpected
     * exception.
     *
     * <p>The service is stubbed to throw a {@link RuntimeException}.  The test
     * confirms that the controller catches the exception and responds with a
     * standardised 500 error body rather than propagating the exception as an
     * unhandled server error, protecting the client from raw stack traces.
     */
    @Test
    @DisplayName("POST /chat - service throws exception returns 500 with INTERNAL_ERROR code")
    void sendMessage_serviceThrows_returns500() throws Exception {
        Mockito.when(aiChatService.processChat(any(ChatRequest.class)))
                .thenThrow(new RuntimeException("Unexpected error"));

        mockMvc.perform(post("/v1/api/ai-chat/chat")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(sampleRequest)))
                .andExpect(status().isInternalServerError())
                .andExpect(jsonPath("$.success", is(false)))
                .andExpect(jsonPath("$.errorCode", is("INTERNAL_ERROR")));
    }

    // -----------------------------------------------------------------------
    // GET /v1/api/ai-chat/conversations/{patientId}
    // -----------------------------------------------------------------------

    /**
     * Verifies that GET /v1/api/ai-chat/conversations/{patientId} returns HTTP
     * 200 and a JSON array containing the patient's conversation summaries.
     *
     * <p>{@link AIChatService#getPatientConversations} is stubbed with patient
     * ID {@code 2L} to return a list containing {@code sampleConversation}.
     * The test spot-checks {@code conversationId} and {@code title} to confirm
     * correct serialisation.
     */
    @Test
    @DisplayName("GET /conversations/{patientId} - success returns 200 with conversation list")
    void getPatientConversations_success_returns200() throws Exception {
        Mockito.when(aiChatService.getPatientConversations(2L)).thenReturn(List.of(sampleConversation));

        mockMvc.perform(get("/v1/api/ai-chat/conversations/2"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(1)))
                .andExpect(jsonPath("$[0].conversationId", is("conv-123")))
                .andExpect(jsonPath("$[0].title", is("General Chat")));

        Mockito.verify(aiChatService).getPatientConversations(2L);
    }

    /**
     * Verifies that GET /v1/api/ai-chat/conversations/{patientId} returns HTTP
     * 200 with an empty JSON array when the patient has no conversations.
     *
     * <p>An empty result is a valid, non-error state — the endpoint should
     * always return 200 for a known patient, even if they have not started any
     * conversations yet.  This test confirms that the controller does not
     * conflate "no data" with "error".
     */
    @Test
    @DisplayName("GET /conversations/{patientId} - empty list returns 200 with empty array")
    void getPatientConversations_empty_returns200() throws Exception {
        Mockito.when(aiChatService.getPatientConversations(99L)).thenReturn(Collections.emptyList());

        mockMvc.perform(get("/v1/api/ai-chat/conversations/99"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(0)));
    }

    /**
     * Verifies that GET /v1/api/ai-chat/conversations/{patientId} returns HTTP
     * 400 when the service throws a {@link RuntimeException}.
     *
     * <p>The service is stubbed to throw a runtime exception simulating a
     * downstream error (e.g., a database failure).  The test confirms that the
     * controller maps the exception to a 400 Bad Request response rather than
     * letting it propagate as an unhandled 500.
     */
    @Test
    @DisplayName("GET /conversations/{patientId} - service throws returns 400")
    void getPatientConversations_serviceThrows_returns400() throws Exception {
        Mockito.when(aiChatService.getPatientConversations(anyLong()))
                .thenThrow(new RuntimeException("DB error"));

        mockMvc.perform(get("/v1/api/ai-chat/conversations/2"))
                .andExpect(status().isBadRequest());
    }

    // -----------------------------------------------------------------------
    // GET /v1/api/ai-chat/conversation/{conversationId}/messages
    // -----------------------------------------------------------------------

    /**
     * Verifies that GET /v1/api/ai-chat/conversation/{conversationId}/messages
     * returns HTTP 200 and the list of message summaries for the specified
     * conversation.
     *
     * <p>{@link AIChatService#getConversationMessages} is stubbed with
     * {@code "conv-123"} to return a list containing {@code sampleMessage}.
     * The test asserts the {@code messageId} and {@code content} fields to
     * confirm that the response is correctly serialised.
     */
    @Test
    @DisplayName("GET /conversation/{conversationId}/messages - success returns 200 with messages")
    void getConversationMessages_success_returns200() throws Exception {
        Mockito.when(aiChatService.getConversationMessages("conv-123"))
                .thenReturn(List.of(sampleMessage));

        mockMvc.perform(get("/v1/api/ai-chat/conversation/conv-123/messages"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(1)))
                .andExpect(jsonPath("$[0].messageId", is(10)))
                .andExpect(jsonPath("$[0].content", is("Hello!")));

        Mockito.verify(aiChatService).getConversationMessages("conv-123");
    }

    /**
     * Verifies that GET /v1/api/ai-chat/conversation/{conversationId}/messages
     * returns HTTP 400 when the service throws a {@link RuntimeException}
     * (e.g., because the conversation ID does not exist).
     *
     * <p>The service is stubbed to throw for any string argument.  The test
     * confirms that an unknown conversation ID results in a 400 rather than a
     * raw 500 server error.
     */
    @Test
    @DisplayName("GET /conversation/{conversationId}/messages - service throws returns 400")
    void getConversationMessages_serviceThrows_returns400() throws Exception {
        Mockito.when(aiChatService.getConversationMessages(anyString()))
                .thenThrow(new RuntimeException("Conversation not found"));

        mockMvc.perform(get("/v1/api/ai-chat/conversation/bad-id/messages"))
                .andExpect(status().isBadRequest());
    }

    // -----------------------------------------------------------------------
    // GET /v1/api/ai-chat/history
    // -----------------------------------------------------------------------

    /**
     * Verifies that GET /v1/api/ai-chat/history returns HTTP 200 with the
     * messages for a specific conversation when {@code conversationId} is
     * supplied as a query parameter.
     *
     * <p>When {@code conversationId} is present, the controller delegates to
     * {@link AIChatService#getConversationMessages} rather than the
     * recent-messages variant.  The test confirms this routing decision by
     * stubbing the correct service method and asserting the response body.
     */
    @Test
    @DisplayName("GET /history - with conversationId fetches messages for that conversation")
    void getConversationHistory_withConversationId_returns200() throws Exception {
        Mockito.when(aiChatService.getConversationMessages("conv-123"))
                .thenReturn(List.of(sampleMessage));

        mockMvc.perform(get("/v1/api/ai-chat/history")
                        .param("userId", "1")
                        .param("conversationId", "conv-123"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.messages", hasSize(1)))
                .andExpect(jsonPath("$.messages[0].content", is("Hello!")));

        Mockito.verify(aiChatService).getConversationMessages("conv-123");
    }

    /**
     * Verifies that GET /v1/api/ai-chat/history calls
     * {@link AIChatService#getRecentMessagesForUser} with the default limit of
     * 50 when no {@code conversationId} is provided.
     *
     * <p>Omitting {@code conversationId} signals that the caller wants a
     * general history view rather than a specific conversation thread.  The
     * test confirms that the controller falls back to the recent-messages path
     * and uses the expected default limit.
     */
    @Test
    @DisplayName("GET /history - without conversationId calls getRecentMessagesForUser with default limit")
    void getConversationHistory_withoutConversationId_callsRecentMessages() throws Exception {
        Mockito.when(aiChatService.getRecentMessagesForUser(1L, 50))
                .thenReturn(Collections.emptyList());
        Mockito.when(chatConversationRepository
                        .findByUserIdAndIsActiveTrueOrderByUpdatedAtDesc(1L))
                .thenReturn(Collections.emptyList());

        mockMvc.perform(get("/v1/api/ai-chat/history")
                        .param("userId", "1"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.messages", hasSize(0)));

        Mockito.verify(aiChatService).getRecentMessagesForUser(1L, 50);
    }

    /**
     * Verifies that GET /v1/api/ai-chat/history forwards a custom {@code limit}
     * query parameter to {@link AIChatService#getRecentMessagesForUser}.
     *
     * <p>Clients may request a smaller or larger history window by passing
     * {@code limit}.  The test confirms that the controller reads the parameter
     * and passes it through to the service unchanged rather than always using
     * the default.
     */
    @Test
    @DisplayName("GET /history - custom limit is forwarded to service")
    void getConversationHistory_customLimit_passedToService() throws Exception {
        Mockito.when(aiChatService.getRecentMessagesForUser(1L, 10))
                .thenReturn(Collections.emptyList());
        Mockito.when(chatConversationRepository
                        .findByUserIdAndIsActiveTrueOrderByUpdatedAtDesc(1L))
                .thenReturn(Collections.emptyList());

        mockMvc.perform(get("/v1/api/ai-chat/history")
                        .param("userId", "1")
                        .param("limit", "10"))
                .andExpect(status().isOk());

        Mockito.verify(aiChatService).getRecentMessagesForUser(1L, 10);
    }

    /**
     * Verifies that GET /v1/api/ai-chat/history returns HTTP 400 when the
     * service throws a {@link RuntimeException}.
     *
     * <p>The service is stubbed to throw for any user ID and limit combination,
     * simulating a downstream failure.  The test confirms that the controller
     * translates the exception to a client-facing 400 error.
     */
    @Test
    @DisplayName("GET /history - service throws returns 400")
    void getConversationHistory_serviceThrows_returns400() throws Exception {
        Mockito.when(aiChatService.getRecentMessagesForUser(anyLong(), anyInt()))
                .thenThrow(new RuntimeException("Service error"));

        mockMvc.perform(get("/v1/api/ai-chat/history")
                        .param("userId", "1"))
                .andExpect(status().isBadRequest());
    }

    // -----------------------------------------------------------------------
    // POST /v1/api/ai-chat/conversation/{conversationId}/deactivate
    // -----------------------------------------------------------------------

    /**
     * Verifies that POST /v1/api/ai-chat/conversation/{conversationId}/deactivate
     * returns HTTP 200 when the conversation is successfully deactivated.
     *
     * <p>{@link AIChatService#deactivateConversation} is stubbed as a no-op
     * for {@code "conv-123"}.  The test confirms that the controller delegates
     * to the service and returns 200, indicating that the deactivation was
     * processed without error.
     */
    @Test
    @DisplayName("POST /conversation/{conversationId}/deactivate - success returns 200")
    void deactivateConversation_success_returns200() throws Exception {
        Mockito.doNothing().when(aiChatService).deactivateConversation("conv-123");

        mockMvc.perform(post("/v1/api/ai-chat/conversation/conv-123/deactivate"))
                .andExpect(status().isOk());

        Mockito.verify(aiChatService).deactivateConversation("conv-123");
    }

    /**
     * Verifies that POST /v1/api/ai-chat/conversation/{conversationId}/deactivate
     * returns HTTP 400 when the service throws a {@link RuntimeException}
     * (e.g., because the conversation ID is invalid or already inactive).
     *
     * <p>The service is stubbed to throw for any string argument.  The test
     * confirms that an error during deactivation results in a 400 Bad Request
     * rather than an unhandled 500.
     */
    @Test
    @DisplayName("POST /conversation/{conversationId}/deactivate - service throws returns 400")
    void deactivateConversation_serviceThrows_returns400() throws Exception {
        Mockito.doThrow(new RuntimeException("Conversation not found"))
                .when(aiChatService).deactivateConversation(anyString());

        mockMvc.perform(post("/v1/api/ai-chat/conversation/bad-id/deactivate"))
                .andExpect(status().isBadRequest());
    }

    // -----------------------------------------------------------------------
    // GET /v1/api/ai-chat/config
    // -----------------------------------------------------------------------

    /**
     * Verifies that GET /v1/api/ai-chat/config returns HTTP 200 and the user's
     * AI configuration when both {@code userId} and {@code patientId} are
     * provided.
     *
     * <p>{@link UserAIConfigService#getUserAIConfig} is stubbed for user ID
     * {@code 1L} and patient ID {@code 2L} to return {@code sampleConfig}.
     * The test confirms that the controller extracts both query parameters and
     * forwards them to the service correctly.
     */
    @Test
    @DisplayName("GET /config - with patientId returns 200 with AI config")
    void getUserAIConfig_withPatientId_returns200() throws Exception {
        Mockito.when(userAIConfigService.getUserAIConfig(1L, 2L)).thenReturn(sampleConfig);

        mockMvc.perform(get("/v1/api/ai-chat/config")
                        .param("userId", "1")
                        .param("patientId", "2"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.userId", is(1)))
                .andExpect(jsonPath("$.patientId", is(2)));

        Mockito.verify(userAIConfigService).getUserAIConfig(1L, 2L);
    }

    /**
     * Verifies that GET /v1/api/ai-chat/config passes {@code null} as the
     * patient ID to the service when the {@code patientId} query parameter is
     * omitted.
     *
     * <p>Not all callers are associated with a specific patient; omitting the
     * parameter is a valid use case.  The test confirms that the controller
     * defaults to {@code null} rather than throwing or substituting a default
     * value, and that the service is invoked with the correct signature.
     */
    @Test
    @DisplayName("GET /config - without patientId passes null to service")
    void getUserAIConfig_withoutPatientId_passesNullToService() throws Exception {
        Mockito.when(userAIConfigService.getUserAIConfig(eq(1L), isNull()))
                .thenReturn(sampleConfig);

        mockMvc.perform(get("/v1/api/ai-chat/config")
                        .param("userId", "1"))
                .andExpect(status().isOk());

        Mockito.verify(userAIConfigService).getUserAIConfig(eq(1L), isNull());
    }

    /**
     * Verifies that GET /v1/api/ai-chat/config returns HTTP 400 when the
     * service throws a {@link RuntimeException}.
     *
     * <p>The service is stubbed to throw for any combination of user ID and
     * patient ID.  The test confirms that a downstream failure during config
     * retrieval is surfaced as a 400 Bad Request.
     */
    @Test
    @DisplayName("GET /config - service throws returns 400")
    void getUserAIConfig_serviceThrows_returns400() throws Exception {
        Mockito.when(userAIConfigService.getUserAIConfig(anyLong(), any()))
                .thenThrow(new RuntimeException("Config not found"));

        mockMvc.perform(get("/v1/api/ai-chat/config")
                        .param("userId", "1"))
                .andExpect(status().isBadRequest());
    }

    // -----------------------------------------------------------------------
    // POST /v1/api/ai-chat/config
    // -----------------------------------------------------------------------

    /**
     * Verifies that POST /v1/api/ai-chat/config returns HTTP 201 Created when
     * the request body does not include an {@code id}, indicating a new config.
     *
     * <p>The absence of an {@code id} field signals that the caller wants to
     * create a fresh configuration.  The service is stubbed to return
     * {@code sampleConfig} and the test confirms that the controller correctly
     * maps this case to a 201 response.
     */
    @Test
    @DisplayName("POST /config - new config (no id) returns 201 Created")
    void saveUserAIConfig_newConfig_returns201() throws Exception {
        final UserAIConfigDTO newConfig = UserAIConfigDTO.builder()
                .userId(1L)
                .patientId(2L)
                .aiProvider(AIProvider.OPENAI)
                .build(); // id is null → treated as new

        Mockito.when(userAIConfigService.saveUserAIConfig(any(UserAIConfigDTO.class)))
                .thenReturn(sampleConfig);

        mockMvc.perform(post("/v1/api/ai-chat/config")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(newConfig)))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.id", is(1)));
    }

    /**
     * Verifies that POST /v1/api/ai-chat/config returns HTTP 200 OK when the
     * request body includes an existing {@code id}, indicating an update.
     *
     * <p>The presence of an {@code id} field signals that the caller is
     * updating an existing configuration.  The test confirms that the
     * controller maps this case to a 200 response rather than 201, correctly
     * distinguishing creation from update.
     */
    @Test
    @DisplayName("POST /config - existing config (with id) returns 200 OK")
    void saveUserAIConfig_existingConfig_returns200() throws Exception {
        Mockito.when(userAIConfigService.saveUserAIConfig(any(UserAIConfigDTO.class)))
                .thenReturn(sampleConfig);

        mockMvc.perform(post("/v1/api/ai-chat/config")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(sampleConfig)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.id", is(1)));
    }

    /**
     * Verifies that POST /v1/api/ai-chat/config returns HTTP 400 when the
     * service throws a {@link RuntimeException} (e.g., a validation failure).
     *
     * <p>The service is stubbed to throw for any config DTO.  The test
     * confirms that a service-level error during save is surfaced as a 400
     * Bad Request, allowing the client to identify and correct invalid input.
     */
    @Test
    @DisplayName("POST /config - service throws returns 400")
    void saveUserAIConfig_serviceThrows_returns400() throws Exception {
        Mockito.when(userAIConfigService.saveUserAIConfig(any(UserAIConfigDTO.class)))
                .thenThrow(new RuntimeException("Validation error"));

        mockMvc.perform(post("/v1/api/ai-chat/config")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(sampleConfig)))
                .andExpect(status().isBadRequest());
    }

    // -----------------------------------------------------------------------
    // DELETE /v1/api/ai-chat/config
    // -----------------------------------------------------------------------

    /**
     * Verifies that DELETE /v1/api/ai-chat/config returns HTTP 200 when both
     * {@code userId} and {@code patientId} are provided and the service
     * deactivates the config without error.
     *
     * <p>{@link UserAIConfigService#deactivateUserAIConfig} is stubbed as a
     * no-op for the given IDs.  The test confirms that the controller delegates
     * to the service with the correct arguments and returns 200 on success.
     */
    @Test
    @DisplayName("DELETE /config - with patientId returns 200")
    void deactivateUserAIConfig_withPatientId_returns200() throws Exception {
        Mockito.doNothing().when(userAIConfigService).deactivateUserAIConfig(1L, 2L);

        mockMvc.perform(delete("/v1/api/ai-chat/config")
                        .param("userId", "1")
                        .param("patientId", "2"))
                .andExpect(status().isOk());

        Mockito.verify(userAIConfigService).deactivateUserAIConfig(1L, 2L);
    }

    /**
     * Verifies that DELETE /v1/api/ai-chat/config passes {@code null} as the
     * patient ID to the service when the {@code patientId} query parameter is
     * omitted.
     *
     * <p>Analogous to the GET /config test, omitting {@code patientId} is a
     * valid call and should be forwarded to the service as {@code null} rather
     * than causing a binding error.
     */
    @Test
    @DisplayName("DELETE /config - without patientId passes null to service")
    void deactivateUserAIConfig_withoutPatientId_passesNullToService() throws Exception {
        Mockito.doNothing().when(userAIConfigService).deactivateUserAIConfig(eq(1L), isNull());

        mockMvc.perform(delete("/v1/api/ai-chat/config")
                        .param("userId", "1"))
                .andExpect(status().isOk());

        Mockito.verify(userAIConfigService).deactivateUserAIConfig(eq(1L), isNull());
    }

    /**
     * Verifies that DELETE /v1/api/ai-chat/config returns HTTP 400 when the
     * service throws a {@link RuntimeException}.
     *
     * <p>The service is stubbed to throw for any user ID and patient ID
     * combination.  The test confirms that a downstream failure during config
     * deactivation is surfaced as a 400 Bad Request.
     */
    @Test
    @DisplayName("DELETE /config - service throws returns 400")
    void deactivateUserAIConfig_serviceThrows_returns400() throws Exception {
        Mockito.doThrow(new RuntimeException("Config not found"))
                .when(userAIConfigService).deactivateUserAIConfig(anyLong(), any());

        mockMvc.perform(delete("/v1/api/ai-chat/config")
                        .param("userId", "1"))
                .andExpect(status().isBadRequest());
    }

    // -----------------------------------------------------------------------
    // GET /v1/api/ai-chat/retention-policy
    // -----------------------------------------------------------------------

    /**
     * Verifies that GET /v1/api/ai-chat/retention-policy returns HTTP 200 and
     * a JSON body containing the {@code retentionPolicy} field when the cleanup
     * service is available.
     *
     * <p>{@link ChatCleanupService#getRetentionPolicyInfo} is stubbed to return
     * a known policy string.  The test asserts that the controller wraps the
     * string in a JSON object under the key {@code retentionPolicy}, giving
     * clients a structured response.
     */
    @Test
    @DisplayName("GET /retention-policy - success returns 200 with policy info")
    void getRetentionPolicy_success_returns200() throws Exception {
        Mockito.when(chatCleanupService.getRetentionPolicyInfo())
                .thenReturn("Conversations are retained for 90 days.");

        mockMvc.perform(get("/v1/api/ai-chat/retention-policy"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.retentionPolicy",
                        is("Conversations are retained for 90 days.")));
    }

    /**
     * Verifies that GET /v1/api/ai-chat/retention-policy returns HTTP 500 and
     * a JSON body containing an {@code error} field when the cleanup service
     * throws a {@link RuntimeException}.
     *
     * <p>The service is stubbed to throw, simulating an infrastructure failure.
     * The test confirms that the controller catches the exception and responds
     * with a 500 Internal Server Error and a user-friendly error message rather
     * than an unhandled exception response.
     */
    @Test
    @DisplayName("GET /retention-policy - service throws returns 500 with error message")
    void getRetentionPolicy_serviceThrows_returns500() throws Exception {
        Mockito.when(chatCleanupService.getRetentionPolicyInfo())
                .thenThrow(new RuntimeException("Policy unavailable"));

        mockMvc.perform(get("/v1/api/ai-chat/retention-policy"))
                .andExpect(status().isInternalServerError())
                .andExpect(jsonPath("$.error",
                        is("Unable to retrieve retention policy information")));
    }
}
