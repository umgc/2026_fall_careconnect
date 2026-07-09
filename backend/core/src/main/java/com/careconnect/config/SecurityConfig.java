package com.careconnect.config;

import java.util.concurrent.TimeUnit;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Profile;
import org.springframework.core.annotation.Order;
import org.springframework.http.HttpMethod;
import org.springframework.security.config.annotation.method.configuration.EnableMethodSecurity;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configurers.AbstractHttpConfigurer;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.core.userdetails.UserDetailsService;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter;
import org.springframework.web.cors.CorsConfigurationSource;

import com.careconnect.security.JwtAuthenticationFilter;
import com.careconnect.security.JwtTokenProvider;

import jakarta.servlet.http.HttpServletResponse;

@Configuration
@EnableMethodSecurity
public class SecurityConfig {

    private static final String ROLE_ADMIN = "ADMIN";

    @Bean
    @Order(0)
    @Profile("dev")
    SecurityFilterChain devChain(
            HttpSecurity http,
            CorsConfigurationSource corsConfigurationSource
    ) throws Exception {

        return http
                .securityMatcher("/v1/api/dev/**")
                .csrf(AbstractHttpConfigurer::disable)
                .cors(cors -> cors.configurationSource(corsConfigurationSource))
                .sessionManagement(sm -> sm.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                .exceptionHandling(ex -> ex
                        .authenticationEntryPoint((req, res, e) ->
                                res.sendError(HttpServletResponse.SC_UNAUTHORIZED, "Unauthorized"))
                        .accessDeniedHandler((req, res, e) ->
                                res.sendError(HttpServletResponse.SC_FORBIDDEN, "Forbidden"))
                )
                .authorizeHttpRequests(auth -> auth
                        .requestMatchers(HttpMethod.OPTIONS, "/**").permitAll()
                        .requestMatchers(HttpMethod.POST, "/v1/api/dev/telemetry").permitAll()
                        .requestMatchers(HttpMethod.PUT, "/v1/api/dev/telemetry/enabled").hasRole(ROLE_ADMIN)
                        .requestMatchers(HttpMethod.GET, "/v1/api/dev/telemetry/enabled").hasRole(ROLE_ADMIN)
                        .requestMatchers(HttpMethod.GET, "/v1/api/dev/telemetry/recent").hasRole(ROLE_ADMIN)
                        .anyRequest().denyAll()
                )
                .build();
    }

    @Bean
    @Order(1)
    SecurityFilterChain apiChain(
            HttpSecurity http,
            JwtTokenProvider jwt,
            UserDetailsService uds,
            CorsConfigurationSource corsConfigurationSource) throws Exception {

        JwtAuthenticationFilter jwtFilter = new JwtAuthenticationFilter(jwt, uds);

        return http
                .csrf(AbstractHttpConfigurer::disable)
                .cors(cors -> cors.configurationSource(corsConfigurationSource))
                .headers(headers -> headers
                        .contentTypeOptions(contentType -> {
                        })
                        .frameOptions(frame -> frame.deny())
                        .httpStrictTransportSecurity(hsts -> hsts
                                .includeSubDomains(true)
                                .maxAgeInSeconds(TimeUnit.DAYS.toSeconds(365)))
                )
                .sessionManagement(sm -> sm.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                .httpBasic(basic -> basic.authenticationEntryPoint(
                        (req, res, e) -> res.sendError(HttpServletResponse.SC_UNAUTHORIZED, "Basic Authentication Required")))
                .addFilterBefore(jwtFilter, UsernamePasswordAuthenticationFilter.class)
                .exceptionHandling(ex -> ex
                        .authenticationEntryPoint((req, res, e) ->
                                res.sendError(HttpServletResponse.SC_UNAUTHORIZED, "Unauthorized"))
                        .accessDeniedHandler((req, res, e) ->
                                res.sendError(HttpServletResponse.SC_FORBIDDEN, "Forbidden"))
                )
                .authorizeHttpRequests(auth -> auth

                        /* =======================================================
                           ACTUATOR HEALTH ENDPOINT (CI/CD + AWS HEALTH CHECKS)
                           =======================================================
                           - Must be public (no auth)
                           - Used by:
                             • CI/CD pipeline gating
                             • AWS ALB / ECS / Fargate health checks
                             • Monitoring tools
                        */
                       .requestMatchers("/actuator/health").permitAll()
                        
                        /* ---------- Swagger / API docs ------------------------ */
                        .requestMatchers(
                                "/swagger-ui/**",
                                "/swagger-ui.html",
                                "/v3/api-docs/**",
                                "/v3/api-docs.yaml",
                                "/v3/api-docs",
                                "/swagger-resources/**",
                                "/webjars/**",
                                "/swagger-ui/index.html",
                                "/api-docs/**",
                                "/configuration/ui",
                                "/configuration/security"
                        ).permitAll()

                        /* ---------- Public API endpoints ---------------------- */
                        .requestMatchers(
                                "/v1/api/auth/**",
                                "/api/v1/auth/**",
                                "/api/auth/**",
                                "/v1/api/users/reset-password",
                                "/v1/api/users/setup-password",
                                "/v1/api/email-test/**",
                                "/v1/api/test/**",
                                "/v1/api/billing/quote",
                                "/v1/api/billing/pay/**",
                                "/v1/api/address/**",
                                "/oauth/**",
                                "/ws/**",
                                "/api/notifications/demo/**"
                        ).permitAll()

                        /* ---------- Actuator / health checks ------------------- */
                        .requestMatchers("/actuator/**").permitAll()

                        /* ---------- Public static assets ---------------------- */
                        .requestMatchers("/", "/index.html", "/favicon.ico", "/static/**").permitAll()
                        .requestMatchers(HttpMethod.OPTIONS, "/**").permitAll()

                        /* ---------- Admin-only endpoints ---------------------- */
                        .requestMatchers("/v1/api/debug/**").hasRole(ROLE_ADMIN)
                        .requestMatchers("/v1/api/email-test/**").hasRole(ROLE_ADMIN)

                        /* ---------- Authenticated endpoints ------------------- */
                        .requestMatchers("/v1/api/subscriptions/**").authenticated()
                        .requestMatchers("/v3/api/subscriptions/**").authenticated()
                        .requestMatchers("/v1/api/invoices/extract-llm").permitAll()
                        .requestMatchers("/v1/api/invoices/**").authenticated()
                        .requestMatchers("/v1/api/notification-settings/**").authenticated()
                        .requestMatchers("/v1/api/patients/**").authenticated()
                        .requestMatchers("/v1/api/caregivers/**").authenticated()
                        .requestMatchers("/v1/api/allergies/**").authenticated()
                        .requestMatchers("/v1/api/symptoms/**").authenticated()
                        .requestMatchers("/v1/api/ai/**", "/api/ai/**").authenticated()
                        .requestMatchers("/v1/api/ai/deepseek/**").authenticated()
                        .requestMatchers("/v1/api/family-members/**").authenticated()
                        .requestMatchers("/v1/api/ai-chat/**").authenticated()
                        .requestMatchers("/v1/api/users/**").authenticated()
                        .requestMatchers("/v1/api/tasks/**").authenticated()
                        .requestMatchers("/v2/api/tasks/**").authenticated()
                        .requestMatchers("/v1/api/messages/**").authenticated()
                        .requestMatchers("/v1/api/evv/**").authenticated()
                        .requestMatchers("/v1/api/notifications/**").authenticated()
                        .requestMatchers("/v1/api/friends/**").authenticated()
                        .requestMatchers("/v1/api/connection-requests/**").authenticated()
                        .requestMatchers("/v1/api/feed/**").authenticated()
                        .requestMatchers("/v1/api/comments/**").authenticated()
                        .requestMatchers("/v1/api/files/**").authenticated()
                        .requestMatchers("/v1/api/templates/**").authenticated()
                        .requestMatchers("/v1/api/analytics/**").authenticated()
                        .requestMatchers("/v1/api/scheduled-visits/**").authenticated()
                        .requestMatchers("/v1/api/patient-notetaker/**").authenticated()
                        .requestMatchers("/v1/api/link-management/**").authenticated()
                        .requestMatchers("/v1/api/caregiver-patient-links/**").authenticated()
                        .requestMatchers("/v1/api/symptoms-entry/**").authenticated()
                        .requestMatchers("/v1/api/alexa/**").authenticated()
                        .requestMatchers("/v1/api/usps/**", "/api/usps/**").authenticated()
                        .requestMatchers("/v1/api/questions/**", "/api/questions/**").authenticated()
                        .requestMatchers("/v1/checkins/**", "/api/checkins/**").authenticated()
                        .requestMatchers("/v1/api/patient/**").authenticated()
                        .requestMatchers("/api/patient/**").authenticated()
                        .requestMatchers("/api/gamification/**").authenticated()
                        .requestMatchers("/api/websocket/**").authenticated()
                        .requestMatchers("/api/email-credentials/**").authenticated()
                        .requestMatchers("/api/v3/calls/**").authenticated()
                        .requestMatchers("/v1/api/**", "/v2/api/**", "/v3/api/**").authenticated()
                        .requestMatchers("/api/**").authenticated()

                        /* ---------- Everything else: deny --------------------- */
                        .anyRequest().denyAll()
                )
                .build();
    }

    @Bean
    public org.springframework.security.crypto.password.PasswordEncoder passwordEncoder() {
        return new org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder();
    }
}
