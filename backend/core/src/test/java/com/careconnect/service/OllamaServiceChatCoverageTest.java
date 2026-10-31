package com.careconnect.service;

import com.careconnect.dto.ChatRequest;
import com.careconnect.dto.ChatResponse;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestClient;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.method;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withStatus;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;

/**
 * Drives {@link OllamaService#processChat} against a {@link MockRestServiceServer}; no local
 * Ollama instance is contacted.
 */
class OllamaServiceChatCoverageTest {

    private OllamaService service;
    private MockRestServiceServer server;

    @BeforeEach
    void setUp() {
        service = new OllamaService("http://ollama.test/", "llama-test", 0.3, 5);
        RestClient.Builder builder = RestClient.builder().baseUrl("http://ollama.test");
        server = MockRestServiceServer.bindTo(builder).build();
        ReflectionTestUtils.setField(service, "restClient", builder.build());
    }

    private static ChatRequest request(String model) {
        ChatRequest r = new ChatRequest();
        r.setMessage("How is my blood pressure?");
        r.setPreferredModel(model);
        return r;
    }

    @Test
    void successfulChatMapsMessageContent() {
        server.expect(requestTo("http://ollama.test/api/chat")).andExpect(method(HttpMethod.POST))
                .andRespond(withSuccess("{\"message\":{\"role\":\"assistant\",\"content\":\"Looks stable.\"}}",
                        MediaType.APPLICATION_JSON));
        ChatResponse resp = service.processChat(request("custom-model"));
        assertThat(resp.getAiResponse()).isEqualTo("Looks stable.");
        assertThat(resp.getModelUsed()).isEqualTo("custom-model");
        server.verify();
    }

    @Test
    void emptyBodyAndHttpErrorsAreHandled() {
        server.expect(requestTo("http://ollama.test/api/chat"))
                .andRespond(withSuccess("{}", MediaType.APPLICATION_JSON));
        server.expect(requestTo("http://ollama.test/api/chat"))
                .andRespond(withStatus(HttpStatus.INTERNAL_SERVER_ERROR).body("model not loaded"));
        assertThat(service.processChat(request(null)).getAiResponse()).isEmpty();
        ChatResponse failed = service.processChat(request(null));
        assertThat(failed.getErrorCode()).isEqualTo("OLLAMA_CONNECTION_ERROR");
    }
}
