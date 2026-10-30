package com.careconnect.security;

import ch.qos.logback.classic.Level;
import ch.qos.logback.classic.Logger;
import ch.qos.logback.classic.LoggerContext;
import ch.qos.logback.classic.spi.ILoggingEvent;
import ch.qos.logback.classic.spi.IThrowableProxy;
import ch.qos.logback.core.read.ListAppender;
import com.careconnect.config.SecurityConfig;
import com.careconnect.controller.emergency.EmergencyPassportController;
import com.careconnect.dto.emergency.PassportDtos.PublicPassport;
import com.careconnect.exception.GlobalExceptionHandler;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.UserRepository;
import com.careconnect.service.emergency.EmergencyPassportService;
import com.careconnect.service.emergency.PassportScanRateLimiter;
import com.careconnect.util.SecurityUtil;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.ComponentScan.Filter;
import org.springframework.context.annotation.FilterType;
import org.springframework.context.annotation.Import;
import org.springframework.context.annotation.Primary;
import org.springframework.security.core.userdetails.UserDetailsService;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.CorsConfigurationSource;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource;

import java.io.IOException;
import java.io.InputStream;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Properties;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * NFR-SEC-12, issue #460 (DEF-EMG-30): a public scan, driven through the real {@link SecurityConfig} filter chain and
 * {@link EmergencyPassportController}, with every logger at the level {@code application-dev.properties} sets (the
 * profile {@code env-entry.sh} uses by default). Every event any logger writes is captured, so this covers Spring
 * Security's own request lines as well as {@link JwtAuthenticationFilter}'s.
 *
 * <p>Test Plan: TC-EMG-496, 497 (Testing Lead). Test IDs are permanent. Never renumber, never reuse.
 */
@WebMvcTest(
        controllers = EmergencyPassportController.class,
        excludeFilters = @Filter(type = FilterType.ASSIGNABLE_TYPE, classes = GlobalExceptionHandler.class))
@Import({SecurityConfig.class, PassportScanTokenLoggingTest.TestConfig.class})
class PassportScanTokenLoggingTest {

    /** A synthetic code in the shape EmergencyPassportService issues. Not a real one. */
    private static final String SCAN_CODE = "Qx7pK2mZ9vR4tL8wN3sB6yH1cF5dJ0aE";

    @Autowired
    MockMvc mockMvc;
    @MockitoBean
    JwtTokenProvider jwtTokenProvider;
    @MockitoBean
    UserDetailsService userDetailsService;
    @MockitoBean
    SecurityUtil securityUtil;
    @MockitoBean
    AuthorizationService authorizationService;
    @MockitoBean
    EmergencyPassportService passports;
    @MockitoBean
    PassportScanRateLimiter rateLimiter;
    @MockitoBean
    UserRepository users;
    @MockitoBean
    PatientRepository patients;

    private final Map<Logger, Level> levelsBefore = new HashMap<>();
    private ListAppender<ILoggingEvent> appender;

    @BeforeEach
    void devProfileLogLevels() throws IOException {
        final LoggerContext context = (LoggerContext) LoggerFactory.getILoggerFactory();
        final Properties dev = new Properties();
        try (InputStream in = getClass().getClassLoader().getResourceAsStream("application-dev.properties")) {
            assertThat(in).as("application-dev.properties on the classpath").isNotNull();
            dev.load(in);
        }
        for (final String key : dev.stringPropertyNames()) {
            if (key.startsWith("logging.level.")) {
                final String name = key.substring("logging.level.".length());
                final Logger logger = context.getLogger("root".equals(name) ? Logger.ROOT_LOGGER_NAME : name);
                levelsBefore.putIfAbsent(logger, logger.getLevel());
                logger.setLevel(Level.toLevel(dev.getProperty(key).trim()));
            }
        }
        // The dev profile must still turn DEBUG on where issue #460 found the leak, or this test proves nothing.
        assertThat(context.getLogger(JwtAuthenticationFilter.class).isDebugEnabled()).isTrue();

        appender = new ListAppender<>();
        appender.start();
        context.getLogger(Logger.ROOT_LOGGER_NAME).addAppender(appender);
        when(rateLimiter.tryAcquire(anyString())).thenReturn(true);
    }

    @AfterEach
    void restoreLogLevels() {
        final LoggerContext context = (LoggerContext) LoggerFactory.getILoggerFactory();
        context.getLogger(Logger.ROOT_LOGGER_NAME).detachAppender(appender);
        levelsBefore.forEach(Logger::setLevel);
    }

    @Test
    @DisplayName("TC-EMG-496: issue #460: a scan of an active code (200) at the dev profile's log levels writes the raw "
            + "code to no log")
    void activeScanLogsNoRawCode() throws Exception {
        when(passports.scan(SCAN_CODE)).thenReturn(Optional.of(
                new PublicPassport("Jordan Miller", 41, null, null, null, null, null, null)));

        mockMvc.perform(get("/v1/api/passport/scan/" + SCAN_CODE)).andExpect(status().isOk());

        assertNoEventCarriesTheCode();
    }

    @Test
    @DisplayName("TC-EMG-497: issue #460: a scan of a code that is not active (404) at the dev profile's log levels "
            + "writes the raw code to no log")
    void inactiveScanLogsNoRawCode() throws Exception {
        when(passports.scan(anyString())).thenReturn(Optional.empty());

        mockMvc.perform(get("/v1/api/passport/scan/" + SCAN_CODE)).andExpect(status().isNotFound());

        assertNoEventCarriesTheCode();
    }

    private void assertNoEventCarriesTheCode() {
        final List<ILoggingEvent> events = List.copyOf(appender.list);
        // Not vacuous: the filter's masked line is among the captured events.
        assertThat(events).extracting(ILoggingEvent::getFormattedMessage)
                .contains("Processing JWT authentication for masked path /v1/api/passport/scan");
        for (final ILoggingEvent e : events) {
            final StringBuilder text = new StringBuilder(e.getFormattedMessage());
            if (e.getArgumentArray() != null) {
                for (final Object arg : e.getArgumentArray()) {
                    text.append(' ').append(arg);
                }
            }
            for (IThrowableProxy t = e.getThrowableProxy(); t != null; t = t.getCause()) {
                text.append(' ').append(t.getMessage());
            }
            assertThat(text.toString())
                    .as("%s logged the raw code: %s", e.getLoggerName(),
                            e.getFormattedMessage().replace(SCAN_CODE, "<code>"))
                    .doesNotContain(SCAN_CODE);
        }
    }

    @TestConfiguration
    static class TestConfig {

        /** Concrete, as in SecurityConfigFilterChainTest: a mock would replace mvcHandlerMappingIntrospector. */
        @Bean
        @Primary
        CorsConfigurationSource testCorsConfigurationSource() {
            final CorsConfiguration cfg = new CorsConfiguration();
            cfg.setAllowedOrigins(List.of("*"));
            cfg.setAllowedMethods(List.of("*"));
            cfg.setAllowedHeaders(List.of("*"));
            final UrlBasedCorsConfigurationSource source = new UrlBasedCorsConfigurationSource();
            source.registerCorsConfiguration("/**", cfg);
            return source;
        }
    }
}
