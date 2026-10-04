package com.careconnect.config;

import lombok.Getter;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import java.util.Arrays;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Optional;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * athenahealth connection configuration.
 *
 * <p>Unlike Epic, the OAuth endpoints are NOT derivable from the FHIR base URL: athena serves
 * OAuth from {@code /oauth2/v1/*} while FHIR R4 lives at {@code /fhir/r4}. They are therefore
 * configured explicitly rather than derived. The values below were confirmed against athena's
 * published {@code .well-known/smart-configuration} on the preview host.
 *
 * <p>Immutable: every value is fixed at construction. The token service caches a token whose
 * granted scopes depend on this configuration, so a bean that could be mutated afterwards could
 * leave that cache describing configuration that no longer applies. Tests build instances
 * through the constructor rather than mutating the deployed bean.
 */
@Component
@Getter
public class AthenaProperties {

    /**
     * Discriminator stored on mirrored resources and audit rows. It is also the {@code ehr_source}
     * code SchemaPatchRunner seeds, so one value names athena in every EHR table.
     */
    public static final String SOURCE_ATHENA = "ATHENAHEALTH";

    /** athena's {@code ah-practice} form; group 1 is the practice number. */
    private static final Pattern PRACTICE_ID = Pattern.compile("a-\\d+\\.Practice-(\\d+)");

    private final boolean enabled;

    private final String tokenUrl;

    /** Unused by the 2-legged flow; present so the 3-legged leg has somewhere to read it from. */
    private final String authorizeUrl;

    private final String introspectUrl;

    private final String revokeUrl;

    private final String clientId;

    private final String clientSecret;

    /**
     * Space-delimited, case-sensitive scopes. athena rejects wildcards, so every resource is
     * listed explicitly, and requesting a scope the portal app is not configured for fails the
     * WHOLE request with 400 {@code Invalid Scope} rather than degrading. Keep this list in sync
     * with the app registration.
     */
    private final String scopes;

    private final String fhirBaseUrl;

    /**
     * The athena practices this deployment may search, each in athena's {@code ah-practice} form,
     * e.g. {@code a-1.Practice-195900} (the bare numeric id is rejected), from ATHENA_PRACTICE_ID:
     * one practice, or several separated by commas. athena is one database per practice and every
     * search must name one. With 2-legged OAuth the app can read only practices that have enabled
     * it, so this is that list. Linking searches each; a linked patient's own practice comes from
     * their chart id and must also be on the list.
     */
    private final List<String> practiceIds;

    public AthenaProperties(
            @Value("${careconnect.athena.enabled:false}") final boolean enabled,
            @Value("${athena.oauth.token-url:https://api.preview.platform.athenahealth.com/oauth2/v1/token}")
            final String tokenUrl,
            @Value("${athena.oauth.authorize-url:https://api.preview.platform.athenahealth.com/oauth2/v1/authorize}")
            final String authorizeUrl,
            @Value("${athena.oauth.introspect-url:https://api.preview.platform.athenahealth.com/oauth2/v1/introspect}")
            final String introspectUrl,
            @Value("${athena.oauth.revoke-url:https://api.preview.platform.athenahealth.com/oauth2/v1/revoke}")
            final String revokeUrl,
            @Value("${athena.oauth.client-id:}") final String clientId,
            @Value("${athena.oauth.client-secret:}") final String clientSecret,
            @Value("${athena.oauth.scopes:system/Patient.read}") final String scopes,
            @Value("${athena.fhir.base-url:https://api.preview.platform.athenahealth.com/fhir/r4}")
            final String fhirBaseUrl,
            @Value("${athena.fhir.practice-id:}") final String practiceIds) {
        final List<String> parsed = parsePracticeIds(practiceIds);
        if (enabled) {
            // There is deliberately no default practice: a default would silently point every
            // developer at whichever practice it named. Fail the boot instead of the first FHIR call.
            if (parsed.isEmpty()) {
                throw new IllegalStateException(
                        "careconnect.athena.enabled is true but athena.fhir.practice-id is blank. "
                        + "Set ATHENA_PRACTICE_ID to the practice the app may search, or several separated "
                        + "by commas, e.g. a-1.Practice-195900 for the preview sandbox.");
            }
            for (final String practice : parsed) {
                if (!PRACTICE_ID.matcher(practice).matches()) {
                    throw new IllegalStateException("athena.fhir.practice-id entry '" + practice
                            + "' is not in athena's ah-practice form, e.g. a-1.Practice-195900.");
                }
            }
        }
        this.enabled = enabled;
        this.tokenUrl = tokenUrl;
        this.authorizeUrl = authorizeUrl;
        this.introspectUrl = introspectUrl;
        this.revokeUrl = revokeUrl;
        this.clientId = clientId;
        this.clientSecret = clientSecret;
        this.scopes = scopes;
        this.fhirBaseUrl = fhirBaseUrl;
        this.practiceIds = parsed;
    }

    /**
     * The configured practice with this number, e.g. {@code 195900} gives {@code a-1.Practice-195900}.
     * Empty when the practice is not one this deployment may search.
     */
    public Optional<String> practiceWithNumber(final String practiceNumber) {
        for (final String practice : practiceIds) {
            final Matcher matcher = PRACTICE_ID.matcher(practice);
            if (matcher.matches() && matcher.group(1).equals(practiceNumber)) {
                return Optional.of(practice);
            }
        }
        return Optional.empty();
    }

    private static List<String> parsePracticeIds(final String raw) {
        if (raw == null || raw.isBlank()) {
            return List.of();
        }
        return Arrays.stream(raw.split(","))
                .map(String::trim)
                .filter(entry -> !entry.isEmpty())
                .distinct()
                .toList();
    }

    public boolean hasCredentials() {
        return clientId != null && !clientId.isBlank()
                && clientSecret != null && !clientSecret.isBlank();
    }

    /** Requested scopes as a set, for comparison against what athena actually granted. */
    public Set<String> requestedScopes() {
        if (scopes == null || scopes.isBlank()) {
            return Set.of();
        }
        return new LinkedHashSet<>(Arrays.asList(scopes.trim().split("\\s+")));
    }
}
