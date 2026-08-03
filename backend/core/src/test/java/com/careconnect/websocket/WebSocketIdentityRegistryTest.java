package com.careconnect.websocket;

import com.careconnect.model.User;
import org.junit.jupiter.api.Test;
import org.springframework.web.socket.CloseStatus;
import org.springframework.web.socket.WebSocketSession;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class WebSocketIdentityRegistryTest {

    @Test
    void bind_detachesPriorSessionIdentityForSameUser() throws Exception {
        final WebSocketIdentityRegistry registry = new WebSocketIdentityRegistry();
        final User user = new User();
        user.setId(7L);
        user.setEmail("u@test.com");

        final WebSocketSession first = mock(WebSocketSession.class);
        when(first.getId()).thenReturn("s1");
        when(first.isOpen()).thenReturn(true);

        final WebSocketSession second = mock(WebSocketSession.class);
        when(second.getId()).thenReturn("s2");
        when(second.isOpen()).thenReturn(true);

        registry.bind(first, user);
        registry.bind(second, user);

        assertThat(registry.getUser("s1")).isNull();
        assertThat(registry.getUser("s2")).isSameAs(user);
        assertThat(registry.getSession("7")).isSameAs(second);
        verify(first).close(any(CloseStatus.class));
    }

    @Test
    void registerUserWithoutSession_doesNotPolluteSessionLookupKeys() {
        final WebSocketIdentityRegistry registry = new WebSocketIdentityRegistry();
        final User user = new User();
        user.setId(3L);
        user.setEmail("x@test.com");

        registry.registerUserWithoutSession("3", user);

        assertThat(registry.getUser("3")).isNull();
        assertThat(registry.getUser("user:3")).isSameAs(user);
    }
}
