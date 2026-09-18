package com.careconnect.controller;

import com.careconnect.model.User;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.Role;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.service.DeepSeekService;
import com.careconnect.service.DeepSeekService.DeepSeekResponse;
import com.careconnect.service.DeepSeekService.Message;
import com.careconnect.util.SecurityUtil;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;

import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class DeepSeekControllerTest {

    @Mock
    private DeepSeekService deepSeekService;
    @Mock
    private SecurityUtil securityUtil;
    @Mock
    private AuthorizationService authorizationService;

    @InjectMocks
    private DeepSeekController controller;

    private User adminUser;
    private User familyUser;

    @BeforeEach
    void setUp() {
        adminUser = User.builder().id(1L).email("admin@test.com").role(Role.ADMIN).build();
        familyUser = User.builder().id(3L).email("family@test.com").role(Role.FAMILY_MEMBER).build();
    }

    private DeepSeekController.ChatBody buildChatBody() {
        final DeepSeekController.ChatBody body = new DeepSeekController.ChatBody();
        body.setModel("deepseek-chat");
        body.setMessages(List.of(new Message("user", "Hello")));
        body.setTemperature(0.7);
        body.setMaxTokens(512);
        return body;
    }

    @Test
    @DisplayName("Should throw UnauthorizedException when user is family member")
    void chat_familyMember_throwsUnauthorized() {
        when(securityUtil.resolveCurrentUser()).thenReturn(familyUser);

        assertThatThrownBy(() -> controller.chat(buildChatBody()))
                .isInstanceOf(UnauthorizedException.class)
                .hasMessageContaining("ADMIN, CAREGIVER, or PATIENT role");
    }

    @Test
    @DisplayName("Should return OK with DeepSeek response on success")
    void chat_success_returnsOk() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(adminUser);

        final DeepSeekResponse mockResponse = new DeepSeekResponse();
        mockResponse.setId("chatcmpl-123");
        mockResponse.setModel("deepseek-chat");
        when(deepSeekService.sendChatRequest(any())).thenReturn(mockResponse);

        final ResponseEntity<?> response = controller.chat(buildChatBody());

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isInstanceOf(DeepSeekResponse.class);
        final DeepSeekResponse body = (DeepSeekResponse) response.getBody();
        assertThat(body.getId()).isEqualTo("chatcmpl-123");
    }

    @Test
    @DisplayName("Should return BAD_GATEWAY when DeepSeek service throws exception")
    void chat_serviceError_returnsBadGateway() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(adminUser);
        when(deepSeekService.sendChatRequest(any())).thenThrow(new RuntimeException("Connection refused"));

        final ResponseEntity<?> response = controller.chat(buildChatBody());

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.BAD_GATEWAY);
        assertThat(response.getBody()).isInstanceOf(DeepSeekController.ErrorPayload.class);
        final DeepSeekController.ErrorPayload error = (DeepSeekController.ErrorPayload) response.getBody();
        assertThat(error.getCode()).isEqualTo("DEEPSEEK_ERROR");
        assertThat(error.getMessage()).isEqualTo("Connection refused");
    }
}
