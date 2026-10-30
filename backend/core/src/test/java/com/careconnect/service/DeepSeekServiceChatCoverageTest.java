package com.careconnect.service;

import com.careconnect.dto.ChatRequest;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestClient;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withStatus;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;

/**
 * Drives {@link DeepSeekService} against a {@link MockRestServiceServer}; no external API is
 * contacted and the API key is a placeholder.
 */
class DeepSeekServiceChatCoverageTest {

    private DeepSeekService serviceWithMockServer(MockRestServiceServer[] holder) {
        DeepSeekService service = new DeepSeekService("placeholder-key", "http://deepseek.test/v1");
        RestClient.Builder builder = RestClient.builder().baseUrl("http://deepseek.test/v1");
        holder[0] = MockRestServiceServer.bindTo(builder).build();
        ReflectionTestUtils.setField(service, "restClient", builder.build());
        return service;
    }

    @Test
    void processChatReturnsFirstChoice() {
        MockRestServiceServer[] holder = new MockRestServiceServer[1];
        DeepSeekService service = serviceWithMockServer(holder);
        holder[0].expect(requestTo("http://deepseek.test/v1/chat/completions"))
                .andRespond(withSuccess("{\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\"Hi\"}}]}",
                        MediaType.APPLICATION_JSON));
        ChatRequest request = new ChatRequest();
        request.setMessage("Hello");
        assertThat(service.processChat(request).getAiResponse()).isEqualTo("Hi");
    }

    @Test
    void httpErrorsAndMissingKeyAreReported() {
        MockRestServiceServer[] holder = new MockRestServiceServer[1];
        DeepSeekService service = serviceWithMockServer(holder);
        holder[0].expect(requestTo("http://deepseek.test/v1/chat/completions"))
                .andRespond(withStatus(HttpStatus.TOO_MANY_REQUESTS).body("slow down"));
        assertThatThrownBy(() -> service.sendChatRequest(service.buildChatRequest("s", "u")))
                .isInstanceOf(RuntimeException.class);

        DeepSeekService noKey = new DeepSeekService("", "http://deepseek.test/v1");
        assertThatThrownBy(() -> noKey.sendChatRequest(noKey.buildChatRequest("s", "u")))
                .isInstanceOf(IllegalStateException.class);
        assertThatThrownBy(() -> noKey.getPatientConversations(1L)).isInstanceOf(UnsupportedOperationException.class);
        assertThatThrownBy(() -> noKey.getConversationMessages("c")).isInstanceOf(UnsupportedOperationException.class);
        assertThatThrownBy(() -> noKey.getRecentMessagesForUser(1L, 5))
                .isInstanceOf(UnsupportedOperationException.class);
        assertThatThrownBy(() -> noKey.deactivateConversation("c")).isInstanceOf(UnsupportedOperationException.class);
    }
}
