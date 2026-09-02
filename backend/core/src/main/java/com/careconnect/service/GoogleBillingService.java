package com.careconnect.service;

import org.springframework.stereotype.Service;
import com.careconnect.dto.BillingVerifyRequest;
import com.careconnect.dto.BillingVerifyResponse;

import java.time.Instant;

import org.springframework.beans.factory.annotation.Value;
import com.google.auth.oauth2.GoogleCredentials;

import java.io.FileInputStream;
import java.util.List;

import org.springframework.web.client.RestTemplate;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.JsonNode;

@Service
public class GoogleBillingService implements BillingService {

    @Value("${google.access-token:}")
    private String googleAccessToken;

    @Value("${google.service-account-file:}")
    private String googleServiceAccountFile;

    @Value("${google.package-name:edu.umgc.careconnect}")
    private String packageName;

    private String getAccessToken() throws Exception {
        if (googleAccessToken != null && !googleAccessToken.isEmpty()) {
            return googleAccessToken;
        }
        if (googleServiceAccountFile != null && !googleServiceAccountFile.isEmpty()) {
            try (FileInputStream fis = new FileInputStream(googleServiceAccountFile)) {
                GoogleCredentials creds = GoogleCredentials.fromStream(fis)
                        .createScoped(List.of("https://www.googleapis.com/auth/androidpublisher"));
                creds.refreshIfExpired();
                return creds.getAccessToken().getTokenValue();
            }
        }
        return null;
    }

    public void cancelSubscription(String productId, String purchaseToken) {
        try {
            String accessToken = getAccessToken();
            if (accessToken == null || accessToken.isEmpty()) {
                return;
            }

            String url = String.format(
                    "https://androidpublisher.googleapis.com/androidpublisher/v3/applications/%s/purchases/subscriptions/%s/tokens/%s:cancel",
                    packageName, productId, purchaseToken
            );

            RestTemplate rest = new RestTemplate();
            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);
            headers.setBearerAuth(accessToken);

            HttpEntity<String> entity = new HttpEntity<>(null, headers);
            rest.exchange(url, org.springframework.http.HttpMethod.POST, entity, String.class);
        } catch (Exception e) {
            System.err.println("Google Play subscription cancellation failed: " + e.getMessage());
        }
    }

    @Override
    public BillingVerifyResponse verifyReceipt(BillingVerifyRequest request) throws Exception {
        if (request.getPackageName() == null || request.getProductId() == null || request.getReceipt() == null) {
            throw new IllegalArgumentException("packageName, productId and receipt token are required for Google verification");
        }

        String url = String.format(
                "https://androidpublisher.googleapis.com/androidpublisher/v3/applications/%s/purchases/subscriptions/%s/tokens/%s",
                request.getPackageName(), request.getProductId(), request.getReceipt()
        );

        RestTemplate rest = new RestTemplate();
        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.APPLICATION_JSON);

        String accessToken = getAccessToken();
        if (accessToken != null && !accessToken.isEmpty()) {
            headers.setBearerAuth(accessToken);
        }

        HttpEntity<String> entity = new HttpEntity<>(null, headers);
        ResponseEntity<String> resp = rest.exchange(url, org.springframework.http.HttpMethod.GET, entity, String.class);
        String body = resp != null ? resp.getBody() : null;

        ObjectMapper mapper = new ObjectMapper();
        JsonNode root = body != null ? mapper.readTree(body) : null;

        BillingVerifyResponse out = new BillingVerifyResponse();
        out.setPlatform("GOOGLE");

        if (root != null) {
            long purchaseTime = root.has("startTimeMillis") ? root.get("startTimeMillis").asLong() :
                    (root.has("purchaseTimeMillis") ? root.get("purchaseTimeMillis").asLong() : Instant.now().toEpochMilli());
            long expiryTime = root.has("expiryTimeMillis") ? root.get("expiryTimeMillis").asLong() :
                    (purchaseTime + 30L * 24L * 3600L * 1000L);
            String orderId = root.has("orderId") ? root.get("orderId").asText() : null;
            String purchaseState = root.has("paymentState") ? String.valueOf(root.get("paymentState").asInt()) : "UNKNOWN";
            out.setSuccess(true);
            out.setExternalTransactionId(orderId != null ? orderId : request.getReceipt());
            out.setExternalSubscriptionId(orderId != null ? orderId : request.getReceipt());
            out.setPurchaseDate(Instant.ofEpochMilli(purchaseTime));
            out.setExpiryDate(Instant.ofEpochMilli(expiryTime));
            out.setStatus(expiryTime > Instant.now().toEpochMilli() ? "ACTIVE" : "EXPIRED");
            out.setMessage("Verified with Google Play. purchaseState=" + purchaseState);
            return out;
        }

        out.setSuccess(false);
        out.setMessage(body != null ? body : "Google verification failed or returned no body");
        out.setStatus("FAILED");
        return out;
    }
}
