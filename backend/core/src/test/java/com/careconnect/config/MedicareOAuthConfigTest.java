package com.careconnect.config;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.util.PropertyPlaceholderHelper;

import java.io.IOException;
import java.io.Reader;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Properties;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;

/**
 * The Medicare OAuth registration in the shipped property files (src/main/resources), read as files:
 * the test classpath has its own application.properties, so a Spring context here would not see them.
 * <p>
 * Test IDs TC-MCR-LINK-032 and 033 are permanent (Testing Lead, 2026-10-06, PR #272 review). Never
 * renumber, never reuse.
 */
class MedicareOAuthConfigTest {

    private static final Path RESOURCES = Path.of("src", "main", "resources");
    private static final String SECRET = "spring.security.oauth2.client.registration.medicare.client-secret";

    private static Properties load(final String file) throws IOException {
        final Properties p = new Properties();
        try (Reader in = Files.newBufferedReader(RESOURCES.resolve(file), StandardCharsets.UTF_8)) {
            p.load(in);
        }
        return p;
    }

    @ParameterizedTest(name = "{0}")
    @ValueSource(strings = {"application.properties", "application-dev.properties",
            "application-prod.properties", "application-test.properties"})
    @DisplayName("TC-MCR-LINK-032: the Medicare client secret resolves with no environment variable set, so no profile fails to start without it (DEF-MCR-17)")
    void clientSecretHasADefault(final String file) throws IOException {
        final String value = load(file).getProperty(SECRET);
        assertThat(value).as(file).isNotNull();
        // Spring fails startup on an unresolvable placeholder; resolve with no variables at all.
        final PropertyPlaceholderHelper strict = new PropertyPlaceholderHelper("${", "}", ":", null, false);
        assertThatCode(() -> strict.replacePlaceholders(value, name -> null)).as(file).doesNotThrowAnyException();
    }

    @ParameterizedTest(name = "{0}")
    @ValueSource(strings = {"application.properties", "application-prod.properties", "application-test.properties"})
    @DisplayName("TC-MCR-LINK-033: OAuth token-exchange tracing (oauth2 TRACE, web.client DEBUG) is set in the dev profile only (DEF-MCR-18)")
    void tokenExchangeIsNotTracedOutsideDev(final String file) throws IOException {
        final Properties p = load(file);
        for (final String name : p.stringPropertyNames()) {
            if (name.startsWith("logging.level.org.springframework.security") || name.startsWith("logging.level.org.springframework.web.client")) {
                assertThat(p.getProperty(name).trim().toUpperCase()).as(file + ": " + name).isNotIn("TRACE", "DEBUG", "ALL");
            }
        }
    }
}
