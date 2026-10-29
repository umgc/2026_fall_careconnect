package com.careconnect.integration.cerner;

import com.careconnect.integration.cerner.CernerAllergyService.CernerSourceException;
import com.fasterxml.jackson.databind.DeserializationFeature;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.io.IOException;
import java.net.HttpURLConnection;
import java.net.SocketTimeoutException;
import java.net.URI;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

/** Bounded read-only transport for patient-scoped Cerner FHIR searchset Bundles. */
public final class CernerFhirBundleHttpClient {
    private static final int MAX_BYTES = 1_048_576;
    private static final int MAX_PAGES = 20;
    private static final int TOO_MANY_REQUESTS = 429;
    private static final String INVALID_RESPONSE = "CERNER_INVALID_RESPONSE";

    private final URI base;
    private final int timeoutMillis;
    private final ObjectMapper mapper = new ObjectMapper()
            .enable(DeserializationFeature.FAIL_ON_TRAILING_TOKENS);

    public enum ResourceType {
        CONDITION("Condition"),
        ENCOUNTER("Encounter"),
        APPOINTMENT("Appointment");

        private final String fhirName;

        ResourceType(final String fhirName) {
            this.fhirName = fhirName;
        }

        String fhirName() {
            return fhirName;
        }
    }

    public record Result(List<JsonNode> resources) {
        public Result {
            resources = resources.stream().map(node -> (JsonNode) node.deepCopy()).toList();
        }
    }

    public CernerFhirBundleHttpClient(final URI base, final Duration timeout) {
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

    @SuppressWarnings("PMD.AvoidUsingHardCodedIP")
    private static boolean isLoopback(final String host) {
        return "localhost".equals(host) || "127.0.0.1".equals(host) || "[::1]".equals(host);
    }

    /** Fetches every bounded page and returns only validated resources of the requested type. */
    public Result getResources(
            final ResourceType type, final String trustedPatientId, final String token) {
        if (type == null) {
            throw new IllegalArgumentException("FHIR resource type required");
        }
        if (trustedPatientId == null || !trustedPatientId.matches("[A-Za-z0-9.-]{1,64}")) {
            throw new IllegalArgumentException("Trusted FHIR patient ID required");
        }
        if (token == null || token.isBlank() || token.contains("\r") || token.contains("\n")) {
            throw failure("CERNER_AUTH_EXPIRED", false);
        }

        final URI firstPage = base.resolve(type.fhirName() + "?patient=" + trustedPatientId);
        return getResources(type, trustedPatientId, token, firstPage);
    }

    /** Fetches proposed and scheduled appointments in one explicit, bounded period. */
    public Result getAppointments(
            final String trustedPatientId,
            final String token,
            final Instant startInclusive,
            final Instant endExclusive) {
        validatePatientAndToken(trustedPatientId, token);
        if (startInclusive == null || endExclusive == null
                || !startInclusive.isBefore(endExclusive)) {
            throw new IllegalArgumentException("A non-empty appointment date range is required");
        }
        final String query = "patient=" + encode(trustedPatientId)
                + "&-date-or-req-period=" + encode("ge" + startInclusive)
                + "&-date-or-req-period=" + encode("lt" + endExclusive);
        return getResources(
                ResourceType.APPOINTMENT,
                trustedPatientId,
                token,
                base.resolve("Appointment?" + query));
    }

    /** Reads the patient selected by the trusted crosswalk/SMART launch context. */
    public JsonNode getPatient(final String trustedPatientId, final String token) {
        validatePatientAndToken(trustedPatientId, token);
        final HttpURLConnection connection = openConnection(
                base.resolve("Patient/" + encode(trustedPatientId)));
        try {
            configure(connection, token);
            final int status = connection.getResponseCode();
            validateStatus(status);
            final JsonNode patient = parseJson(readBody(connection));
            if (!"Patient".equals(patient.path("resourceType").asText())
                    || !trustedPatientId.equals(patient.path("id").asText())) {
                throw failure(INVALID_RESPONSE, false);
            }
            return patient.deepCopy();
        } catch (SocketTimeoutException error) {
            throw failure("CERNER_TIMEOUT", true);
        } catch (IOException error) {
            throw failure("CERNER_UNAVAILABLE", true);
        } finally {
            connection.disconnect();
        }
    }

    private Result getResources(
            final ResourceType type,
            final String trustedPatientId,
            final String token,
            final URI firstPage) {
        final List<JsonNode> resources = new ArrayList<>();
        final Set<URI> visited = new HashSet<>();
        URI pageUri = firstPage;
        for (int pageNumber = 0; pageNumber < MAX_PAGES; pageNumber++) {
            if (!visited.add(pageUri)) {
                throw failure(INVALID_RESPONSE, false);
            }
            final Page page = fetchPage(pageUri, type, trustedPatientId, token);
            resources.addAll(page.resources());
            if (page.next() == null) {
                return new Result(resources);
            }
            pageUri = trustedNext(page.next());
        }
        throw failure("CERNER_PAGINATION_LIMIT", false);
    }

    private Page fetchPage(
            final URI pageUri,
            final ResourceType type,
            final String trustedPatientId,
            final String token) {
        final HttpURLConnection connection = openConnection(pageUri);
        try {
            configure(connection, token);
            final int status = connection.getResponseCode();
            validateStatus(status);
            return mapResponse(readBody(connection), type, trustedPatientId);
        } catch (SocketTimeoutException error) {
            throw failure("CERNER_TIMEOUT", true);
        } catch (IOException error) {
            throw failure("CERNER_UNAVAILABLE", true);
        } finally {
            connection.disconnect();
        }
    }

    private void configure(final HttpURLConnection connection, final String token) {
        connection.setInstanceFollowRedirects(false);
        connection.setConnectTimeout(timeoutMillis);
        connection.setReadTimeout(timeoutMillis);
        connection.setUseCaches(false);
        connection.setRequestProperty("Accept", "application/fhir+json");
        connection.setRequestProperty("Authorization", "Bearer " + token);
    }

    private static void validateStatus(final int status) {
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
    }

    private static byte[] readBody(final HttpURLConnection connection) throws IOException {
        final byte[] body;
        try (var input = connection.getInputStream()) {
            body = input.readNBytes(MAX_BYTES + 1);
        }
        if (body.length > MAX_BYTES) {
            throw failure(INVALID_RESPONSE, false);
        }
        return body;
    }

    @SuppressWarnings("PMD.PreserveStackTrace")
    private JsonNode parseJson(final byte[] body) {
        try {
            final JsonNode result = mapper.readTree(body);
            if (result == null) {
                throw failure(INVALID_RESPONSE, false);
            }
            return result;
        } catch (IOException error) {
            throw failure(INVALID_RESPONSE, false);
        }
    }

    @SuppressWarnings("PMD.PreserveStackTrace")
    private HttpURLConnection openConnection(final URI pageUri) {
        try {
            return (HttpURLConnection) pageUri.toURL().openConnection();
        } catch (IOException error) {
            throw failure("CERNER_UNAVAILABLE", true);
        }
    }

    @SuppressWarnings("PMD.PreserveStackTrace")
    private Page mapResponse(
            final byte[] body, final ResourceType type, final String trustedPatientId) {
        try {
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
                    final String value = link.path("url").asText(null);
                    if (value == null || next != null) {
                        throw failure(INVALID_RESPONSE, false);
                    }
                    next = URI.create(value);
                }
            }
            final List<JsonNode> resources = new ArrayList<>();
            for (final JsonNode entry : bundle.path("entry")) {
                final JsonNode resource = entry.path("resource");
                if (!type.fhirName().equals(resource.path("resourceType").asText())) {
                    continue;
                }
                if (resource.path("id").asText("").isBlank()
                        || !belongsToPatient(resource, type, trustedPatientId)) {
                    throw failure(INVALID_RESPONSE, false);
                }
                resources.add(resource.deepCopy());
            }
            return new Page(resources, next);
        } catch (IOException | IllegalArgumentException error) {
            throw failure(INVALID_RESPONSE, false);
        }
    }

    private static boolean belongsToPatient(
            final JsonNode resource,
            final ResourceType type,
            final String trustedPatientId) {
        final String expected = "Patient/" + trustedPatientId;
        if (type != ResourceType.APPOINTMENT) {
            return expected.equals(resource.path("subject").path("reference").asText());
        }
        for (final JsonNode participant : resource.path("participant")) {
            if (expected.equals(participant.path("actor").path("reference").asText())) {
                return true;
            }
        }
        return false;
    }

    private static void validatePatientAndToken(
            final String trustedPatientId, final String token) {
        if (trustedPatientId == null || !trustedPatientId.matches("[A-Za-z0-9.-]{1,64}")) {
            throw new IllegalArgumentException("Trusted FHIR patient ID required");
        }
        if (token == null || token.isBlank() || token.contains("\r") || token.contains("\n")) {
            throw failure("CERNER_AUTH_EXPIRED", false);
        }
    }

    private static String encode(final String value) {
        return URLEncoder.encode(value, StandardCharsets.UTF_8).replace("+", "%20");
    }

    private URI trustedNext(final URI next) {
        final URI resolved = next.isAbsolute() ? next : base.resolve(next);
        if (!base.getScheme().equalsIgnoreCase(resolved.getScheme())
                || !base.getHost().equalsIgnoreCase(resolved.getHost())
                || effectivePort(base) != effectivePort(resolved)
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

    private record Page(List<JsonNode> resources, URI next) { }

    private static CernerSourceException failure(final String code, final boolean retryable) {
        return new CernerSourceException(code, retryable);
    }
}
