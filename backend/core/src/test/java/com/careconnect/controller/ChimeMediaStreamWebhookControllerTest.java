package com.careconnect.controller;

import static org.mockito.ArgumentMatchers.anyMap;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.careconnect.service.ChimeMediaStreamEventService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

@ExtendWith(MockitoExtension.class)
@DisplayName("ChimeMediaStreamWebhookController")
class ChimeMediaStreamWebhookControllerTest {

    private static final String SECRET = "careconnect-dev-kvs-discovery";

    @Mock
    private ChimeMediaStreamEventService chimeMediaStreamEventService;

    private MockMvc mockMvc;

    @BeforeEach
    void setUp() {
        final ChimeMediaStreamWebhookController controller =
                new ChimeMediaStreamWebhookController(chimeMediaStreamEventService, SECRET);
        mockMvc = MockMvcBuilders.standaloneSetup(controller).build();
    }

    @Test
    @DisplayName("rejects request with missing X-EventBridge-Connection header")
    void missingHeader_returnsUnauthorized() throws Exception {
        mockMvc
                .perform(
                        post("/api/internal/chime/media-stream-events")
                                .contentType(MediaType.APPLICATION_JSON)
                                .content("{\"detail\":{}}"))
                .andExpect(status().isUnauthorized());
        verify(chimeMediaStreamEventService, never()).handleEventDetail(anyMap());
    }

    @Test
    @DisplayName("rejects request with wrong X-EventBridge-Connection header")
    void wrongSecret_returnsUnauthorized() throws Exception {
        mockMvc
                .perform(
                        post("/api/internal/chime/media-stream-events")
                                .header(
                                        ChimeMediaStreamWebhookController.EVENT_BRIDGE_CONNECTION_HEADER,
                                        "wrong-secret")
                                .contentType(MediaType.APPLICATION_JSON)
                                .content("{\"detail\":{\"meetingId\":\"m-1\"}}"))
                .andExpect(status().isUnauthorized());
        verify(chimeMediaStreamEventService, never()).handleEventDetail(anyMap());
    }

    @Test
    @DisplayName("accepts request with matching shared secret and forwards detail")
    void correctSecret_invokesService() throws Exception {
        mockMvc
                .perform(
                        post("/api/internal/chime/media-stream-events")
                                .header(
                                        ChimeMediaStreamWebhookController.EVENT_BRIDGE_CONNECTION_HEADER,
                                        SECRET)
                                .contentType(MediaType.APPLICATION_JSON)
                                .content("{\"detail\":{\"meetingId\":\"m-1\",\"attendeeId\":\"a-1\"}}"))
                .andExpect(status().isOk());
        verify(chimeMediaStreamEventService).handleEventDetail(anyMap());
    }

    @Test
    @DisplayName("blank configured secret rejects all requests (fail-closed)")
    void blankConfiguredSecret_returnsUnauthorized() throws Exception {
        final ChimeMediaStreamWebhookController openSecretController =
                new ChimeMediaStreamWebhookController(chimeMediaStreamEventService, "");
        final MockMvc blankSecretMvc = MockMvcBuilders.standaloneSetup(openSecretController).build();

        blankSecretMvc
                .perform(
                        post("/api/internal/chime/media-stream-events")
                                .header(
                                        ChimeMediaStreamWebhookController.EVENT_BRIDGE_CONNECTION_HEADER,
                                        "anything")
                                .contentType(MediaType.APPLICATION_JSON)
                                .content("{\"detail\":{}}"))
                .andExpect(status().isUnauthorized());
        verify(chimeMediaStreamEventService, never()).handleEventDetail(anyMap());
    }
}
