package com.careconnect.service;

import org.junit.jupiter.api.Assumptions;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.lang.reflect.Field;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Drift guard for the duplicated telemetry event allowlist (DEF-TEL-07).
 *
 * <p>PR #63 introduced {@code TelemetryService.allowedEvents} as a hand-copied duplicate of the
 * Flutter client's {@code TelemetryGuardrails.allowedEvents}. Nothing in the build keeps the two
 * in sync, so a client-side addition silently becomes a server-side rejection. This test fails the
 * moment either list changes without the other.
 *
 * <p>Test ID TC-TEL-21 is permanent. Never renumber, never reuse.
 *
 * <p>Skips (rather than fails) when the Flutter sources are not present, so the backend module
 * still builds standalone.
 */
@DisplayName("Telemetry allowlist parity - backend vs Flutter guardrails")
class TelemetryAllowlistParityTest {

    /** Path to the Flutter guardrails file, relative to candidate repository roots. */
    private static final String GUARDRAILS_RELATIVE_PATH =
            "frontend/lib/features/telemetry/telemetry_guardrails.dart";

    /**
     * Candidate roots. Surefire runs with the working directory set to {@code backend/core}, but
     * the test is also runnable from the repository root inside an IDE.
     */
    private static final List<String> CANDIDATE_ROOTS = List.of("../..", ".", "../../..");

    /** Matches the body of {@code static const Set<String> allowedEvents = { ... };}. */
    private static final Pattern ALLOWED_EVENTS_BLOCK = Pattern.compile(
            "static\\s+const\\s+Set<String>\\s+allowedEvents\\s*=\\s*\\{(.*?)\\};",
            Pattern.DOTALL);

    /** Matches a single-quoted Dart string literal. */
    private static final Pattern DART_STRING = Pattern.compile("'([^']*)'");

    @Test
    @DisplayName("TC-TEL-21: backend allowedEvents matches TelemetryGuardrails.allowedEvents exactly")
    void tcTel21_allowlistsAreInSync() throws Exception {
        final Path guardrails = locateGuardrails();
        Assumptions.assumeTrue(
                guardrails != null,
                "Flutter sources not available from this working directory; parity check skipped");

        final Set<String> flutterEvents = parseDartAllowedEvents(guardrails);
        final Set<String> backendEvents = readBackendAllowedEvents();

        assertThat(flutterEvents)
                .as("sanity check: the Dart allowlist was parsed")
                .isNotEmpty();

        assertThat(backendEvents)
                .as("backend TelemetryService.allowedEvents must match "
                        + "TelemetryGuardrails.allowedEvents in " + guardrails)
                .containsExactlyInAnyOrderElementsOf(flutterEvents);
    }

    private static Path locateGuardrails() {
        for (final String root : CANDIDATE_ROOTS) {
            final Path candidate = Paths.get(root, GUARDRAILS_RELATIVE_PATH).normalize();
            if (Files.isRegularFile(candidate)) {
                return candidate;
            }
        }
        return null;
    }

    private static Set<String> parseDartAllowedEvents(final Path guardrails) throws IOException {
        final String source = Files.readString(guardrails, StandardCharsets.UTF_8);
        final Matcher block = ALLOWED_EVENTS_BLOCK.matcher(source);
        assertThat(block.find())
                .as("could not locate 'static const Set<String> allowedEvents' in " + guardrails
                        + "; the Dart declaration was renamed or restructured")
                .isTrue();

        final Set<String> events = new LinkedHashSet<>();
        final Matcher literal = DART_STRING.matcher(block.group(1));
        while (literal.find()) {
            events.add(literal.group(1));
        }
        return events;
    }

    @SuppressWarnings("unchecked")
    private static Set<String> readBackendAllowedEvents() throws ReflectiveOperationException {
        final Field field = TelemetryService.class.getDeclaredField("allowedEvents");
        field.setAccessible(true);
        return new LinkedHashSet<>((List<String>) field.get(null));
    }
}
