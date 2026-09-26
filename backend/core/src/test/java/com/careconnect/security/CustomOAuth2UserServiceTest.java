package com.careconnect.security;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.oauth2.client.registration.ClientRegistration;
import org.springframework.security.oauth2.client.registration.InMemoryClientRegistrationRepository;
import org.springframework.security.oauth2.client.userinfo.OAuth2UserRequest;
import org.springframework.security.oauth2.client.userinfo.OAuth2UserService;
import org.springframework.security.oauth2.core.OAuth2AuthenticationException;
import org.springframework.security.oauth2.core.OAuth2AccessToken;
import org.springframework.security.oauth2.core.user.DefaultOAuth2User;
import org.springframework.security.oauth2.core.user.OAuth2User;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class CustomOAuth2UserServiceTest {

    @Mock
    private OAuth2UserService<OAuth2UserRequest, OAuth2User> delegateService;

    private CustomOAuth2UserService customOAuth2UserService;

    private OAuth2UserRequest userRequest;
    private ClientRegistration clientRegistration;

    @BeforeEach
    void setUp() throws Exception {
        clientRegistration = mock(ClientRegistration.class);

        OAuth2AccessToken accessToken = mock(OAuth2AccessToken.class);
        userRequest = new OAuth2UserRequest(clientRegistration, accessToken);

        customOAuth2UserService = new CustomOAuth2UserService(delegateService);
    }

    @Test
    void loadUser_ShouldReturnOAuth2UserWithPatientRole_WhenEmailDoesNotContainCaregiver() throws OAuth2AuthenticationException {
        // Arrange
        Map<String, Object> attributes = new HashMap<>();
        attributes.put("email", "test@example.com");
        attributes.put("name", "Test User");
        OAuth2User oauthUser = new DefaultOAuth2User(List.of(), attributes, "email");
        when(delegateService.loadUser(userRequest)).thenReturn(oauthUser);

        // Act
        OAuth2User result = customOAuth2UserService.loadUser(userRequest);

        // Assert
        assertNotNull(result);
        assertEquals("test@example.com", result.getAttribute("email"));
        assertEquals("Test User", result.getAttribute("name"));
        assertTrue(result.getAuthorities().contains(new SimpleGrantedAuthority("ROLE_PATIENT")));
        verify(delegateService).loadUser(userRequest);
    }

    @Test
    void loadUser_ShouldReturnOAuth2UserWithCaregiverRole_WhenEmailContainsCaregiver() throws OAuth2AuthenticationException {
        // Arrange
        Map<String, Object> attributes = new HashMap<>();
        attributes.put("email", "caregiver@example.com");
        attributes.put("name", "Caregiver User");
        OAuth2User oauthUser = new DefaultOAuth2User(List.of(), attributes, "email");
        when(delegateService.loadUser(userRequest)).thenReturn(oauthUser);

        // Act
        OAuth2User result = customOAuth2UserService.loadUser(userRequest);

        // Assert
        assertNotNull(result);
        assertEquals("caregiver@example.com", result.getAttribute("email"));
        assertEquals("Caregiver User", result.getAttribute("name"));
        assertTrue(result.getAuthorities().contains(new SimpleGrantedAuthority("ROLE_CAREGIVER")));
        verify(delegateService).loadUser(userRequest);
    }

    @Test
    void loadUser_ShouldReturnOAuth2UserWithPatientRole_WhenEmailIsNull() throws OAuth2AuthenticationException {
        // Arrange
        Map<String, Object> attributes = new HashMap<>();
        attributes.put("name", "User Without Email");
        OAuth2User oauthUser = new DefaultOAuth2User(List.of(), attributes, "name");
        when(delegateService.loadUser(userRequest)).thenReturn(oauthUser);

        // Act
        OAuth2User result = customOAuth2UserService.loadUser(userRequest);

        // Assert
        assertNotNull(result);
        assertNull(result.getAttribute("email"));
        assertEquals("User Without Email", result.getAttribute("name"));
        assertTrue(result.getAuthorities().contains(new SimpleGrantedAuthority("ROLE_PATIENT")));
        verify(delegateService).loadUser(userRequest);
    }

    @Test
    void loadUser_ShouldThrowException_WhenDelegateThrowsException() throws OAuth2AuthenticationException {
        // Arrange
        OAuth2AuthenticationException exception = new OAuth2AuthenticationException("OAuth2 error");
        when(delegateService.loadUser(userRequest)).thenThrow(exception);

        // Act & Assert
        assertThrows(OAuth2AuthenticationException.class,
                () -> customOAuth2UserService.loadUser(userRequest));
        verify(delegateService).loadUser(userRequest);
    }
}