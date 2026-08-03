package com.careconnect.security;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import java.net.MalformedURLException;
import java.net.URL;
import java.util.LinkedHashSet;
import java.util.Locale;
import java.util.Set;

/**
 * Restricts OAuth return URLs to trusted frontend origins.
 */
@Component
public class OAuthRedirectValidator {

    private final Set<String> allowedHosts;

    public OAuthRedirectValidator(
            @Value("${google.oauth.frontend-url:http://localhost}") String googleFrontendUrl,
            @Value("${frontend.base-url:http://localhost:3000}") String appFrontendUrl,
            @Value("${google.oauth.allowed-return-hosts:}") String extraHosts) {
        this.allowedHosts = new LinkedHashSet<>();
        addHostFromUrl(googleFrontendUrl, allowedHosts);
        addHostFromUrl(appFrontendUrl, allowedHosts);
        if (extraHosts != null && !extraHosts.isBlank()) {
            for (String host : extraHosts.split(",")) {
                String trimmed = host.trim().toLowerCase(Locale.ROOT);
                if (!trimmed.isEmpty()) {
                    allowedHosts.add(trimmed);
                }
            }
        }
    }

    /**
     * @return sanitized URL when allowed, or {@code null} when blank
     * @throws IllegalArgumentException when the URL is present but not allowed
     */
    public String sanitizeReturnUrl(String returnUrl) {
        if (returnUrl == null || returnUrl.isBlank()) {
            return null;
        }
        URL url = parseUrl(returnUrl.trim());
        if (!isAllowedHost(url)) {
            throw new IllegalArgumentException("returnUrl host is not allowed: " + url.getHost());
        }
        return url.toString();
    }

    public String defaultReturnUrl(String frontendBaseUrl) {
        return normalizeBase(frontendBaseUrl) + "/usps-test";
    }

    public String resolveRedirect(String returnUrl, String frontendBaseUrl) {
        String sanitized = sanitizeReturnUrl(returnUrl);
        if (sanitized != null) {
            return sanitized;
        }
        return defaultReturnUrl(frontendBaseUrl);
    }

    private boolean isAllowedHost(URL url) {
        String scheme = url.getProtocol().toLowerCase(Locale.ROOT);
        if (!"http".equals(scheme) && !"https".equals(scheme)) {
            return false;
        }
        String host = url.getHost().toLowerCase(Locale.ROOT);
        if ("localhost".equals(host) || "127.0.0.1".equals(host)) {
            return true;
        }
        return allowedHosts.contains(host);
    }

    private static URL parseUrl(String value) {
        try {
            return new URL(value);
        } catch (MalformedURLException e) {
            throw new IllegalArgumentException("returnUrl is malformed", e);
        }
    }

    private static void addHostFromUrl(String baseUrl, Set<String> hosts) {
        if (baseUrl == null || baseUrl.isBlank()) {
            return;
        }
        try {
            hosts.add(new URL(normalizeBase(baseUrl)).getHost().toLowerCase(Locale.ROOT));
        } catch (MalformedURLException ignored) {
            // Ignore invalid configuration; localhost fallback still works in dev.
        }
    }

    private static String normalizeBase(String baseUrl) {
        String trimmed = baseUrl.trim();
        return trimmed.endsWith("/") ? trimmed.substring(0, trimmed.length() - 1) : trimmed;
    }
}
