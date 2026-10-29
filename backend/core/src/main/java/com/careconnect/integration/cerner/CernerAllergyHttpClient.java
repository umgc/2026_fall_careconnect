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
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

/**
 * Explicitly constructed, single-page client. No Spring bean or app wiring enables it.
 * The caller must supply a trusted vendor patient ID and a server-held token after access checks.
 * Error codes and limits are provisional pending the team's contract review.
 */
public final class CernerAllergyHttpClient {
  private static final String INVALID_RESPONSE = "CERNER_INVALID_RESPONSE";
  private static final int MAX_BYTES = 1_048_576;
  private static final int MAX_PAGES = 20;
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

  public record Result(List<CernerAllergyMapper.Allergy> allergies, List<JsonNode> rawResources) {
    public Result {
      allergies = List.copyOf(allergies);
      rawResources = rawResources.stream()
          .map(node -> (JsonNode) node.deepCopy())
          .toList();
    }
  }

  /** Does not refresh tokens, retry failed requests, follow redirects, or return partial results. */
  // Upstream exception messages may contain credentials; expose only fixed domain errors.
  @SuppressWarnings("PMD.PreserveStackTrace")
  public List<CernerAllergyMapper.Allergy> getAllergies(
      final String trustedPatientId, final String token) {
    return getAllergyResult(trustedPatientId, token).allergies();
  }

  /** Fetches all bounded Bundle pages and returns mapped records plus validated raw resources. */
  public Result getAllergyResult(final String trustedPatientId, final String token) {
    if (trustedPatientId == null || !trustedPatientId.matches("[A-Za-z0-9.-]{1,64}")) {
      throw new IllegalArgumentException("Trusted FHIR patient ID required");
    }
    if (token == null || token.isBlank() || token.contains("\r") || token.contains("\n")) {
      throw failure("CERNER_AUTH_EXPIRED", false);
    }
    URI pageUri = base.resolve("AllergyIntolerance?patient=" + trustedPatientId);
    List<CernerAllergyMapper.Allergy> allergies = new ArrayList<>();
    List<JsonNode> rawResources = new ArrayList<>();
    Set<URI> visited = new HashSet<>();
    for (int pageNumber = 0; pageNumber < MAX_PAGES; pageNumber++) {
      if (!visited.add(pageUri)) {
        throw failure(INVALID_RESPONSE, false);
      }
      Page page = fetchPage(pageUri, trustedPatientId, token);
      allergies.addAll(page.allergies());
      rawResources.addAll(page.rawResources());
      if (page.next() == null) {
        return new Result(allergies, rawResources);
      }
      pageUri = trustedNext(page.next());
    }
    throw failure("CERNER_PAGINATION_LIMIT", false);
  }

  private Page fetchPage(final URI pageUri, final String trustedPatientId, final String token) {
    final HttpURLConnection connection = openConnection(pageUri);
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
  private HttpURLConnection openConnection(final URI pageUri) {
    try {
      return (HttpURLConnection) pageUri.toURL().openConnection();
    } catch (IOException e) {
      throw failure("CERNER_UNAVAILABLE", true);
    }
  }

  // Parser causes can contain clinical source text; keep them out of the error envelope.
  @SuppressWarnings("PMD.PreserveStackTrace")
  private Page mapResponse(
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
      URI next = null;
      for (final JsonNode link : bundle.path("link")) {
        if ("next".equals(link.path("relation").asText())) {
          String value = link.path("url").asText(null);
          if (value == null || next != null) {
            throw failure(INVALID_RESPONSE, false);
          }
          next = URI.create(value);
        }
      }
      List<CernerAllergyMapper.Allergy> allergies = CernerAllergyMapper.map(bundle, trustedPatientId);
      List<JsonNode> rawResources = new ArrayList<>();
      for (JsonNode entry : bundle.path("entry")) {
        JsonNode resource = entry.path("resource");
        if ("AllergyIntolerance".equals(resource.path("resourceType").asText())
            && !resource.path("id").asText("").isBlank()
            && ("Patient/" + trustedPatientId)
                .equals(resource.path("patient").path("reference").asText())) {
          rawResources.add(resource.deepCopy());
        }
      }
      return new Page(allergies, rawResources, next);
    } catch (IOException | IllegalArgumentException e) {
      // Byte-array parsing cannot perform a network read; all decoding failures are invalid data.
      throw failure(INVALID_RESPONSE, false);
    }
  }

  private URI trustedNext(final URI next) {
    URI resolved = next.isAbsolute() ? next : base.resolve(next);
    int basePort = effectivePort(base);
    int nextPort = effectivePort(resolved);
    if (!base.getScheme().equalsIgnoreCase(resolved.getScheme())
        || !base.getHost().equalsIgnoreCase(resolved.getHost())
        || basePort != nextPort
        || resolved.getUserInfo() != null
        || resolved.getFragment() != null
        || !resolved.getPath().startsWith(base.getPath())) {
      throw failure(INVALID_RESPONSE, false);
    }
    return resolved;
  }

  private static int effectivePort(final URI uri) {
    if (uri.getPort() >= 0) {
      return uri.getPort();
    }
    return "https".equalsIgnoreCase(uri.getScheme()) ? 443 : 80;
  }

  private record Page(
      List<CernerAllergyMapper.Allergy> allergies, List<JsonNode> rawResources, URI next) { }

  private static CernerSourceException failure(final String code, final boolean retryable) {
    // Deliberately discard upstream causes: their messages can contain tokens or patient data.
    return new CernerSourceException(code, retryable);
  }
}
