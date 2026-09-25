package com.careconnect.security;

import org.springframework.security.oauth2.core.OAuth2AuthenticationException;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.oauth2.client.userinfo.*;
import org.springframework.security.oauth2.core.user.*;
import org.springframework.stereotype.Component;

import java.util.*;

@Component
public class CustomOAuth2UserService implements OAuth2UserService<OAuth2UserRequest, OAuth2User> {

    private final OAuth2UserService<OAuth2UserRequest, OAuth2User> delegate;

    public CustomOAuth2UserService() {
        this.delegate = new DefaultOAuth2UserService();
    }

    // Constructor for testing
    public CustomOAuth2UserService(OAuth2UserService<OAuth2UserRequest, OAuth2User> delegate) {
        this.delegate = delegate;
    }

    @Override
    public OAuth2User loadUser(OAuth2UserRequest userRequest) throws OAuth2AuthenticationException {
        OAuth2User oauthUser = delegate.loadUser(userRequest);

        String email = oauthUser.getAttribute("email");
        String role = determineRoleByEmail(email);

        String nameAttributeKey = (email != null) ? "email" : "name";

        return new DefaultOAuth2User(
                List.of(new SimpleGrantedAuthority("ROLE_" + role.toUpperCase())),
                oauthUser.getAttributes(),
                nameAttributeKey
        );
    }

    private String determineRoleByEmail(String email) {
        if (email != null && email.contains("caregiver")) return "CAREGIVER";
        return "PATIENT";
    }
}
