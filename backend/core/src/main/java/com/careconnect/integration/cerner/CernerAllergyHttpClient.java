package com.careconnect.integration.cerner;

import com.careconnect.integration.cerner.CernerAllergyService.CernerSourceException;
import com.fasterxml.jackson.databind.DeserializationFeature;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.io.IOException;
import java.net.HttpURLConnection;
import java.net.SocketTimeoutException;
import java.net.URI;
import java.time.Duration;
import java.util.List;

/**
 * Explicitly constructed, single-page client. No Spring bean or app wiring enables it.
 * The caller must supply a trusted vendor patient ID and a server-held token after access checks.
 * Error codes and limits are provisional pending the team's contract review.
 */
public final class CernerAllergyHttpClient {
  private static final String INVALID_RESPONSE = "CERNER_INVALID_RESPONSE";
  private static final int MAX_BYTES = 1_048_576;
  private static final int TOO_MANY_REQUESTS = 429;
  private final URI base;
  private final int timeoutMillis;
  private final ObjectMapper mapper = new ObjectMapper()
      .enable(DeserializationFeature.FAIL_ON_TRAILING_TOKENS);

  /**
   * Creates an inactive client with bounded connect and read inactivity timeouts.
   *
   * @param base server-controlled HTTPS FHIR base ending with a slash; loopback HTTP for tests
   * @param timeout positive timeout of at most 30 seconds for each blocking network operation
   */
  public CernerAllergyHttpClient(final URI base, final Duration timeout) {
    final String host = base.getHost();
    final boolean local = isLoopback(host);
    if (host == null || base.getUserInfo() != null || base.getQuery() != null
        || base.getFragment() != null || !base.getPath().endsWith("/")
        || !("https".equals(base.getScheme()) || local && "http".equals(base.getScheme()))) {
      throw new IllegalArgumentException(
          "HTTPS base URI with trailing slash required; HTTP is loopback-only");
    }
    final long millis = timeout.toMillis();
    if (millis < 1 || millis > 30_000) {
      throw new IllegalArgumentException("Timeout must be between 1 and 30000 milliseconds");
    }
    this.base = base;
    this.timeoutMillis = (int) millis;
  }

  // Exact loopback literals restrict the test exception; arbitrary private IPs are not allowed.
  @SuppressWarnings("PMD.AvoidUsingHardCodedIP")
  private static boolean isLoopback(final String host) {
    return "localhost".equals(host) || "127.0.0.1".equals(host) || "[::1]".equals(host);
  }

  /** Does not refresh tokens, retry, follow redirects, or return incomplete paginated results. */
  // Upstream exception messages may contain credentials; expose only fixed domain errors.
  @SuppressWarnings("PMD.PreserveStackTrace")
  public List<CernerAllergyMapper.Allergy> getAllergies(
      final String trustedPatientId, final String token) {
    if (trustedPatientId == null || !trustedPatientId.matches("[A-Za-z0-9.-]{1,64}")) {
      throw new IllegalArgumentException("Trusted FHIR patient ID required");
    }
    if (token == null || token.isBlank() || token.contains("\r") || token.contains("\n")) {
      throw failure("CERNER_AUTH_EXPIRED", false);
    }
    final HttpURLConnection connection = openConnection(trustedPatientId);
    try {
      connection.setInstanceFollowRedirects(false);
      connection.setConnectTimeout(timeoutMillis);
      connection.setReadTimeout(timeoutMillis);
      connection.setUseCaches(false);
      connection.setRequestProperty("Accept", "application/fhir+json");
      connection.setRequestProperty("Authorization", "Bearer " + token);
      final int status = connection.getResponseCode();
      if (status == HttpURLConnection.HTTP_UNAUTHORIZED) {
        throw failure("CERNER_AUTH_EXPIRED", false);
      }
      if (status == HttpURLConnection.HTTP_FORBIDDEN) {
        throw failure("CERNER_ACCESS_DENIED", false);
      }
      if (status == TOO_MANY_REQUESTS || status >= HttpURLConnection.HTTP_INTERNAL_ERROR) {
        throw failure("CERNER_UNAVAILABLE", true);
      }
      if (status != HttpURLConnection.HTTP_OK) {
        throw failure("CERNER_UNEXPECTED_RESPONSE", false);
      }
      byte[] body;
      try (var input = connection.getInputStream()) {
        body = input.readNBytes(MAX_BYTES + 1);
      }
      if (body.length > MAX_BYTES) {
        throw failure(INVALID_RESPONSE, false);
      }
      return mapResponse(body, trustedPatientId);
    } catch (SocketTimeoutException e) {
      throw failure("CERNER_TIMEOUT", true);
    } catch (IOException e) {
      throw failure("CERNER_UNAVAILABLE", true);
    } finally {
      connection.disconnect();
    }
  }

  // Do not retain a cause containing a server URL or patient query.
  @SuppressWarnings("PMD.PreserveStackTrace")
  private HttpURLConnection openConnection(final String trustedPatientId) {
    try {
      return (HttpURLConnection) base.resolve("AllergyIntolerance?patient=" + trustedPatientId)
          .toURL().openConnection();
    } catch (IOException e) {
      throw failure("CERNER_UNAVAILABLE", true);
    }
  }

  // Parser causes can contain clinical source text; keep them out of the error envelope.
  @SuppressWarnings("PMD.PreserveStackTrace")
  private List<CernerAllergyMapper.Allergy> mapResponse(
      final byte[] body, final String trustedPatientId) {
    try {
      // Parse bytes directly so malformed UTF-8 is rejected rather than silently replaced.
      final JsonNode bundle = mapper.readTree(body);
      if (bundle == null || !"Bundle".equals(bundle.path("resourceType").asText())
          || !"searchset".equals(bundle.path("type").asText())
          || bundle.has("entry") && !bundle.path("entry").isArray()
          || bundle.has("link") && !bundle.path("link").isArray()) {
        throw failure(INVALID_RESPONSE, false);
      }
      for (final JsonNode link : bundle.path("link")) {
        if ("next".equals(link.path("relation").asText())) {
          throw failure("CERNER_PAGINATION_UNSUPPORTED", false);
        }
      }
      return CernerAllergyMapper.map(bundle, trustedPatientId);
    } catch (IOException | IllegalArgumentException e) {
      // Byte-array parsing cannot perform a network read; all decoding failures are invalid data.
      throw failure(INVALID_RESPONSE, false);
    }
  }

  private static CernerSourceException failure(final String code, final boolean retryable) {
    // Deliberately discard upstream causes: their messages can contain tokens or patient data.
    return new CernerSourceException(code, retryable);
  }
}
