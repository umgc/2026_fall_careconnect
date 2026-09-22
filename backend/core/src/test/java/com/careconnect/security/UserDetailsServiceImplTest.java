package com.careconnect.security;

import com.careconnect.model.User;
import com.careconnect.repository.UserRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.security.core.userdetails.UsernameNotFoundException;
import org.springframework.security.oauth2.core.user.OAuth2User;

import java.util.ArrayList;
import java.util.Collection;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class UserDetailsServiceImplTest {

    @Mock
    private UserRepository userRepository;

    @InjectMocks
    private UserDetailsServiceImpl userDetailsService;

    private User testUser;

    @BeforeEach
    void setUp() throws Exception {
        testUser = new User();
        testUser.setEmail("test@example.com");
        testUser.setPassword("password");
        testUser.setRole(Role.PATIENT);
    }

    @Test
    void loadUserByEmailAndRole_ShouldReturnUserDetails_WhenUserExists() throws Exception {
        // Arrange
        when(userRepository.findByEmailAndRole("test@example.com", Role.PATIENT))
                .thenReturn(Optional.of(testUser));

        // Act
        UserDetails result = userDetailsService.loadUserByEmailAndRole("test@example.com", "PATIENT");

        // Assert
        assertNotNull(result);
        assertEquals("test@example.com", result.getUsername());
        assertEquals("password", result.getPassword());
        assertTrue(result.getAuthorities().contains(new SimpleGrantedAuthority("ROLE_PATIENT")));
        verify(userRepository).findByEmailAndRole("test@example.com", Role.PATIENT);
    }

    @Test
    void loadUserByEmailAndRole_ShouldThrowException_WhenUserNotFound() throws Exception {
        // Arrange
        when(userRepository.findByEmailAndRole("test@example.com", Role.PATIENT))
                .thenReturn(Optional.empty());

        // Act & Assert
        UsernameNotFoundException exception = assertThrows(UsernameNotFoundException.class,
                () -> userDetailsService.loadUserByEmailAndRole("test@example.com", "PATIENT"));
        assertEquals("User not found with email: test@example.com and role: PATIENT", exception.getMessage());
        verify(userRepository).findByEmailAndRole("test@example.com", Role.PATIENT);
    }

    @Test
    void loadUserByUsername_ShouldReturnUserDetails_WhenUserExists() throws Exception {
        // Arrange
        when(userRepository.findByEmail("test@example.com")).thenReturn(Optional.of(testUser));

        // Act
        UserDetails result = userDetailsService.loadUserByUsername("test@example.com");

        // Assert
        assertNotNull(result);
        assertEquals("test@example.com", result.getUsername());
        assertEquals("password", result.getPassword());
        assertTrue(result.getAuthorities().contains(new SimpleGrantedAuthority("ROLE_PATIENT")));
        verify(userRepository).findByEmail("test@example.com");
    }

    @Test
    void loadUserByUsername_ShouldThrowException_WhenUserNotFound() throws Exception {
        // Arrange
        when(userRepository.findByEmail("test@example.com")).thenReturn(Optional.empty());

        // Act & Assert
        UsernameNotFoundException exception = assertThrows(UsernameNotFoundException.class,
                () -> userDetailsService.loadUserByUsername("test@example.com"));
        assertEquals("User not found", exception.getMessage());
        verify(userRepository).findByEmail("test@example.com");
    }

    @SuppressWarnings({"unchecked", "deprecation"})
    @Test
    void extractUserProfile_ShouldReturnOAuth2UserProfile_WhenPrincipalIsOAuth2User() throws Exception {
        // Arrange
        OAuth2User oAuth2User = mock(OAuth2User.class);
        when(oAuth2User.getAttribute("email")).thenReturn("oauth@example.com");
        when(oAuth2User.getAttribute("name")).thenReturn("OAuth User");
        @SuppressWarnings("rawtypes")
        Collection authorities = new ArrayList<>();
        authorities.add(new SimpleGrantedAuthority("ROLE_USER"));
        when(oAuth2User.getAuthorities()).thenReturn(authorities);

        // Act
        ResponseEntity<?> response = userDetailsService.extractUserProfile(oAuth2User);

        // Assert
        assertEquals(200, response.getStatusCodeValue());
        Map<String, Object> body = (Map<String, Object>) response.getBody();
        assertEquals("oauth@example.com", body.get("email"));
        assertEquals("OAuth User", body.get("name"));
        assertEquals("ROLE_USER", body.get("role"));
    }

    @SuppressWarnings("deprecation")
    @Test
    void extractUserProfile_ShouldReturnUserDetailsProfile_WhenPrincipalIsUserDetails() throws Exception {
        // Arrange
        UserDetails userDetails = new org.springframework.security.core.userdetails.User(
                "user@example.com", "password", List.of(new SimpleGrantedAuthority("ROLE_PATIENT")));

        // Act
        ResponseEntity<?> response = userDetailsService.extractUserProfile(userDetails);

        // Assert
        assertEquals(200, response.getStatusCodeValue());
        @SuppressWarnings("unchecked")
        Map<String, Object> body = (Map<String, Object>) response.getBody();
        assertEquals("user@example.com", body.get("email"));
        assertEquals("ROLE_PATIENT", body.get("role"));
    }

    @SuppressWarnings("deprecation")
    @Test
    void extractUserProfile_ShouldReturnUnauthorized_WhenPrincipalIsInvalid() throws Exception {
        // Act
        ResponseEntity<?> response = userDetailsService.extractUserProfile("invalid");

        // Assert
        assertEquals(401, response.getStatusCodeValue());
        assertEquals("No authenticated user", response.getBody());
    }
}