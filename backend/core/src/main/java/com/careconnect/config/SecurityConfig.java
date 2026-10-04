package com.careconnect.config;

import com.careconnect.security.JwtAuthenticationFilter;
import com.careconnect.security.JwtTokenProvider;
import com.careconnect.service.OAuthHelperService;
import jakarta.servlet.http.HttpServletResponse;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.annotation.Order;
import org.springframework.http.HttpMethod;
import org.springframework.security.config.annotation.method.configuration.EnableMethodSecurity;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configurers.AbstractHttpConfigurer;
import org.springframework.security.config.annotation.web.configurers.HeadersConfigurer;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.core.userdetails.UserDetailsService;
import org.springframework.security.oauth2.client.registration.ClientRegistrationRepository;
import org.springframework.security.oauth2.client.web.DefaultOAuth2AuthorizationRequestResolver;
import org.springframework.security.oauth2.client.web.OAuth2AuthorizationRequestCustomizers;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter;
import org.springframework.web.cors.CorsConfigurationSource;

import java.util.concurrent.TimeUnit;

@Configuration
@EnableMethodSecurity
@Slf4j
public class SecurityConfig {

    private static final String ROLE_ADMIN = "ADMIN";

    @Autowired
    private ObjectProvider<OAuthHelperService> oauthHelperService;

    /**
     * The OAuth sign-in flows that link an external account, such as Medicare (Blue Button).
     * <p>
     * Separate from {@link #apiChain} because the two need opposite things. An OAuth sign-in has
     * to keep state in a session across the browser's trip to the provider and back (the
     * authorization request and our link token); the JWT API must not, or a session left behind by
     * that sign-in would authenticate later API calls. So only these paths may create or read a
     * session, and {@code apiChain} stays stateless. See CLAUDE.md: STATELESS and oauth2Login()
     * cannot share a chain.
     * <p>
     * Every path here is reachable without a JWT, because the browser doing the sign-in cannot send
     * one. Entry is guarded instead: {@code /oauth2/connect} requires a one-time link token issued
     * to a signed-in patient, the redirect is protected by OAuth {@code state} and PKCE, and the
     * success handler discards the session once the tokens are stored.
     * <p>
     * Where Spring's OAuth client auto-configuration is switched off, or a security test slice loads
     * this config without the services behind it, there is nothing to sign in with, so the chain is built without
     * {@code oauth2Login()}: the paths still exist and still cannot reach the API chain.
     */
    @Bean
    @Order(-1)
    SecurityFilterChain oauthLinkChain(
            HttpSecurity http,
            CorsConfigurationSource corsConfigurationSource,
            ObjectProvider<ClientRegistrationRepository> clientRegistrations) throws Exception {

        http
                .securityMatcher("/oauth2/**", "/login/oauth2/**")
                // A browser redirect flow: state and PKCE protect it, and nothing here accepts a form post.
                .csrf(AbstractHttpConfigurer::disable)
                .cors(cors -> cors.configurationSource(corsConfigurationSource))
                .headers(headers -> headers
                        .frameOptions(HeadersConfigurer.FrameOptionsConfig::deny)
                        .httpStrictTransportSecurity(hsts -> hsts
                                .includeSubDomains(true)
                                .maxAgeInSeconds(TimeUnit.DAYS.toSeconds(365))))
                .sessionManagement(sm -> sm.sessionCreationPolicy(SessionCreationPolicy.IF_REQUIRED))
                .authorizeHttpRequests(auth -> auth.anyRequest().permitAll());

        final ClientRegistrationRepository clientRegistrationRepository = clientRegistrations.getIfAvailable();
        final OAuthHelperService handler = oauthHelperService.getIfAvailable();
        if (clientRegistrationRepository != null && handler != null) {
            DefaultOAuth2AuthorizationRequestResolver resolver =
                    new DefaultOAuth2AuthorizationRequestResolver(
                            clientRegistrationRepository,
                            "/oauth2/authorization"
                    );
            resolver.setAuthorizationRequestCustomizer(
                    OAuth2AuthorizationRequestCustomizers.withPkce()
            );
            http.oauth2Login(oauth -> oauth
                    .authorizationEndpoint(endpoint -> endpoint.authorizationRequestResolver(resolver))
                    .successHandler(handler)
                    .failureHandler(handler));
        }
        return http.build();
    }

    @Bean
    @Order(0)
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
                        .frameOptions(HeadersConfigurer.FrameOptionsConfig::deny)
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
                                "/api/notifications/demo/**",
                                "/api/internal/chime/**"
                        ).permitAll()

                        /* ---------- Actuator / health checks ------------------- */
                        .requestMatchers("/actuator/**").permitAll()

                        /* ---------- Public static assets ---------------------- */
                        .requestMatchers("/", "/index.html", "/favicon.ico", "/static/**").permitAll()
                        .requestMatchers(HttpMethod.OPTIONS, "/**").permitAll()

                        /* ---------- Admin-only endpoints ---------------------- */
                        .requestMatchers("/v1/api/debug/**",
                                "/v1/api/email-test/**",
                                "/v1/api/admin/analytics/**",
                                "/v1/api/admin/users/**"
                                ).hasRole(ROLE_ADMIN)
                        /* ---------- Telemetry Admin Endpoints ------------------ */
                        .requestMatchers(HttpMethod.PUT, "/v1/api/dev/telemetry/enabled").hasRole(ROLE_ADMIN)
                        .requestMatchers(HttpMethod.GET, "/v1/api/dev/telemetry/recent").hasRole(ROLE_ADMIN)

                        .requestMatchers(HttpMethod.GET, "/v1/api/invite/*").permitAll()
                        .requestMatchers(HttpMethod.POST, "/v1/api/invite/*/accept").authenticated()

                        // Kept from before the matcher list was collapsed: public on team-e-develop.
                        .requestMatchers("/v1/api/invoices/extract-llm").permitAll()

                        /* ---------- Telemetry: intentionally unauthenticated ----
                         * These two matchers are public in EVERY profile, prod
                         * included. That is deliberate, not an oversight:
                         *
                         *  - The Flutter client posts telemetry with no bearer
                         *    token (ApiService.sendTelemetryEventV3), and events
                         *    fire before login (screen_view on the login and
                         *    signup routes, session_start). Requiring auth here
                         *    does not harden the endpoint, it silently drops
                         *    every pre-login event and 401s the rest.
                         *  - Telemetry.getBackendEnabled() reads /enabled with no
                         *    token, so that GET must stay public or the client
                         *    fails open and keeps emitting after an opt-out.
                         *
                         * The endpoint is therefore defended by WHAT it accepts,
                         * not by WHO calls it:
                         *  - TelemetryService rejects any event outside its
                         *    allowlist and strips non-allowlisted detail keys.
                         *  - TelemetryController bounds payload size before the
                         *    body reaches the service or the database.
                         *
                         * Mutating and reading stored telemetry stays ADMIN-only
                         * (PUT /enabled and GET /recent, declared above).
                         *
                         * Rate limiting is NOT yet implemented. Until it is, this
                         * endpoint accepts unauthenticated writes at any rate from
                         * any source. Tracked as follow-up work.
                         */
                        .requestMatchers(HttpMethod.POST, "/v1/api/dev/telemetry").permitAll()
                        .requestMatchers(HttpMethod.GET, "/v1/api/dev/telemetry/enabled").permitAll()

                        // Explicit matcher before /v1/api/** and /api/** catch-alls; both paths require auth.
                        // Legacy /api/email-credentials/** kept for clients not yet on the /v1 prefix.
                        // /v1/checkins is not under /v1/api, so it needs its own matcher or it falls to denyAll.
                        .requestMatchers("/v1/checkins/**").authenticated()
                        .requestMatchers(
                                "/v1/api/**", "/v2/api/**", "/v3/api/**",
                                "/api/**"
                                ).authenticated()

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
