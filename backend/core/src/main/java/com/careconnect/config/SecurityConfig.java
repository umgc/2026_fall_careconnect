package com.careconnect.config;

import com.careconnect.security.JwtAuthenticationFilter;
import com.careconnect.security.JwtTokenProvider;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.config.annotation.method.configuration.EnableMethodSecurity;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configurers.AbstractHttpConfigurer;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.core.userdetails.UserDetailsService;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter;
import org.springframework.web.cors.CorsConfiguration; // New Import
import org.springframework.web.cors.CorsConfigurationSource;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource; // New Import
import java.util.Arrays; // New Import
import java.util.List;   // New Import

@Configuration
@EnableMethodSecurity
public class SecurityConfig {

    @Bean
    SecurityFilterChain filterChain(HttpSecurity http,
                                    JwtTokenProvider jwt,
                                    UserDetailsService uds,
                                    CorsConfigurationSource corsConfigurationSource) throws Exception {

        JwtAuthenticationFilter jwtFilter = new JwtAuthenticationFilter(jwt, uds);

        return http
                .csrf(AbstractHttpConfigurer::disable)
                .cors(cors -> cors.configurationSource(corsConfigurationSource))
                .sessionManagement(sm -> sm.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                .httpBasic(basic -> basic.authenticationEntryPoint(
                        (req, res, e) -> res.sendError(HttpServletResponse.SC_UNAUTHORIZED, "Basic Authentication Required")))
                .addFilterBefore(jwtFilter, UsernamePasswordAuthenticationFilter.class)
                .exceptionHandling(ex -> ex.authenticationEntryPoint(
                        (req, res, e) -> res.sendError(HttpServletResponse.SC_UNAUTHORIZED, "Unauthorized")))
                .authorizeHttpRequests(auth -> auth
                        /* ---------- Swagger/OpenAPI docs ------------------------------ */
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

                        /* ---------- public API endpoints ------------------------ */
                        .requestMatchers(
                                "/v1/api/auth/**",
                                "/api/v1/auth/**",
                                "/api/auth/**",
                                "/v1/api/users/reset-password",
                                "/v1/api/users/setup-password",
                                "/v1/api/email-test/**",
                                "/v1/api/test/**",
                                "/oauth/**"
                        ).permitAll()

                        /* ---------- public static assets ------------------------ */
                        .requestMatchers(
                                "/", "/index.html", "/favicon.ico", "/static/**"
                        ).permitAll()

                        /* ---------- Require JWT for these APIs ------------------------ */
                        .requestMatchers("/v1/api/patients/**").authenticated()
                        .requestMatchers("/v1/api/caregivers/**").authenticated()
                        .requestMatchers("/v1/api/allergies/**").authenticated()
                        .requestMatchers("/v1/api/symptoms/**").authenticated()
                        .requestMatchers("/v1/api/ai/**", "/api/ai/**").authenticated()
                        .requestMatchers("/v1/api/ai/deepseek/**").authenticated()
                        .requestMatchers("/v1/api/family-members/**").authenticated()
                        .requestMatchers("/v1/api/ai-chat/**").authenticated()
                        .requestMatchers("/v1/api/tasks/**").authenticated()
                        .requestMatchers("/v1/api/stml/**").authenticated()
                        /* ---------- Everything else: deny ----------------------------- */
                        .anyRequest().denyAll()
                )
                .build();
    }

    // 🌟 Added structural CORS source bean to natively whitelist any local ports used by Flutter
    @Bean
    public CorsConfigurationSource corsConfigurationSource() {
        CorsConfiguration configuration = new CorsConfiguration();
        
        // Explicitly white list your Flutter development ports
        configuration.setAllowedOriginPatterns(List.of(
            "http://localhost:[*]", 
            "http://127.0.0.1:[*]"
        ));
        
        configuration.setAllowedMethods(Arrays.asList("GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"));
        configuration.setAllowedHeaders(Arrays.asList("Authorization", "Content-Type", "X-Requested-With", "Accept", "Origin"));
        configuration.setExposedHeaders(List.of("Authorization"));
        configuration.setAllowCredentials(true);
        
        UrlBasedCorsConfigurationSource source = new UrlBasedCorsConfigurationSource();
        source.registerCorsConfiguration("/**", configuration);
        return source;
    }

    @Bean
    public org.springframework.security.crypto.password.PasswordEncoder passwordEncoder() {
        return new org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder();
    }
}