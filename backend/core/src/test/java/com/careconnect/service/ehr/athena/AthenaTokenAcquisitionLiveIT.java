package com.careconnect.service.ehr.athena;

import com.careconnect.config.AthenaProperties;
import com.careconnect.testsupport.fixtures.AthenaPropertiesFixtures;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.web.client.RestTemplate;

import java.util.Set;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * Live check against the athenahealth PREVIEW sandbox. NOT a unit test and NOT for CI.
 *
 * <p>Skipped unless {@code ATHENA_CLIENT_ID} and {@code ATHENA_CLIENT_SECRET} are present in the
 * environment, and named {@code *IT} so Surefire's default includes do not pick it up either.
 * Run it locally after loading backend/core/.env:
 *
 * <pre>
 *   export $(grep -E '^ATHENA_CLIENT_(ID|SECRET)=' backend/core/.env | xargs)
 *   ./mvnw test -Dtest=AthenaTokenAcquisitionLiveIT -DfailIfNoTests=false
 * </pre>
 *
 * <p>Deliberately makes ONE token request across the whole class. athena's token endpoint has a
 * quota well below the documented API rate limit: three rapid requests returned 429. The caching
 * assertion below is also what keeps this test cheap.
 */
@EnabledIfEnvironmentVariable(named = "ATHENA_CLIENT_ID", matches = ".+")
@EnabledIfEnvironmentVariable(named = "ATHENA_CLIENT_SECRET", matches = ".+")
class AthenaTokenAcquisitionLiveIT {

    private static AthenaClientCredentialsTokenService service() {
        // Only what the portal app currently grants. Adding an unconfigured scope fails the
        // whole request with 400 "Invalid Scope" rather than degrading to a subset.
        final String scopes = System.getenv("ATHENA_SCOPES");
        final AthenaProperties cfg = AthenaPropertiesFixtures.builder()
                .tokenUrl("https://api.preview.platform.athenahealth.com/oauth2/v1/token")
                .clientId(System.getenv("ATHENA_CLIENT_ID"))
                .clientSecret(System.getenv("ATHENA_CLIENT_SECRET"))
                .scopes(scopes != null && !scopes.isBlank() ? scopes : "system/Patient.read")
                .build();
        return new AthenaClientCredentialsTokenService(new RestTemplate(), cfg);
    }

    @Test
    void acquiresAndCachesARealToken() {
        // Arrange
        final AthenaClientCredentialsTokenService svc = service();

        // Act
        final String token = svc.accessToken();
        final Set<String> granted = svc.grantedScopes();
        final String again = svc.accessToken();

        // Assert: a real athena access token is a JWT of roughly 900 characters.
        assertNotNull(token, "no access token returned");
        assertFalse(token.isBlank(), "access token was blank");
        assertTrue(token.length() > 100, "token looks too short to be a real JWT: " + token.length());

        // The same instance must not re-request: that is what avoids the 429 quota.
        assertEquals(token, again, "second call re-requested instead of using the cache");

        // Granted scopes come from athena, not from configuration, and may be narrower.
        assertFalse(granted.isEmpty(), "athena returned no scopes");
        assertTrue(granted.contains("system/Patient.read"),
                "expected system/Patient.read to be granted, got " + granted);

        System.out.println("athena token OK (len " + token.length() + "), granted scopes: " + granted);
    }
}
