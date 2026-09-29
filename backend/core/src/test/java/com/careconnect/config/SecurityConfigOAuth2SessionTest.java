package com.careconnect.config;

import com.careconnect.exception.GlobalExceptionHandler;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.JwtTokenProvider;
import com.careconnect.util.SecurityUtil;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.ComponentScan.Filter;
import org.springframework.context.annotation.FilterType;
import org.springframework.context.annotation.Import;
import org.springframework.context.annotation.Primary;
import org.springframework.mock.web.MockHttpSession;
import org.springframework.security.core.userdetails.UserDetailsService;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.CorsConfigurationSource;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource;

import java.util.List;

import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.oauth2Login;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * Reproduces the /results 401 without touching CMS Blue Button or BluebuttonController:
 * isolates the filter-chain mechanic that actually breaks it -- an OAuth2 login on one
 * request does not carry over to the next request under SessionCreationPolicy.STATELESS,
 * even in the same session. A stand-in controller sits at the same "/results" path so the
 * real authorizeHttpRequests rule ("/results" -> authenticated()) is exercised unchanged.
 *
 * Drafted 2026-09-28 by Rich's Cowork session while investigating the 401 on Max's
 * feature/e-ehr-api / e-ehr-api-2 branch. Not committed to any branch -- run it with:
 *   mvnw test -Dtest=SecurityConfigOAuth2SessionTest
 *
 * Expected result if the STATELESS-session diagnosis is correct: the first assertion
 * passes (login succeeds), the second fails with 401 (this is the bug, reproduced).
 */
@WebMvcTest(
        controllers = {SecurityConfigOAuth2SessionTest.ResultsPingController.class},
        excludeFilters = @Filter(
                type = FilterType.ASSIGNABLE_TYPE,
                classes = GlobalExceptionHandler.class))
@Import({SecurityConfig.class, SecurityConfigOAuth2SessionTest.TestConfig.class})
class SecurityConfigOAuth2SessionTest {

    @Autowired MockMvc mockMvc;
    @MockitoBean JwtTokenProvider jwtTokenProvider;
    @MockitoBean UserDetailsService userDetailsService;
    @MockitoBean private SecurityUtil securityUtil;
    @MockitoBean private AuthorizationService authorizationService;

    @Test
    void oauth2Login_succeedsOnFirstRequest_butIsLostOnTheNext() throws Exception {
        MockHttpSession session = new MockHttpSession();

        // First request: the OAuth2 callback landing on /results, already authenticated --
        // this is what oauth2Login().successHandler()'s redirect target sees.
        mockMvc.perform(get("/results").session(session).with(oauth2Login()))
                .andExpect(status().isOk());

        // Second request: the browser's actual next request, same session, no fresh
        // token attached -- exactly what defaultSuccessUrl("/results", true) triggers.
        mockMvc.perform(get("/results").session(session))
                .andExpect(status().isUnauthorized()); // <- reproduces Max's 401
    }

    @TestConfiguration
    static class TestConfig {
        @Bean
        @Primary
        CorsConfigurationSource corsConfigurationSource() {
            UrlBasedCorsConfigurationSource source = new UrlBasedCorsConfigurationSource();
            CorsConfiguration config = new CorsConfiguration();
            config.setAllowedOrigins(List.of("http://localhost"));
            config.setAllowedMethods(List.of("GET"));
            source.registerCorsConfiguration("/**", config);
            return source;
        }
    }

    @RestController
    static class ResultsPingController {
        @GetMapping("/results")
        String results() {
            return "ok";
        }
    }
}
