package com.careconnect.service;

import org.springframework.stereotype.Service;
import org.springframework.web.client.RestTemplate;
import org.springframework.http.*;
import com.careconnect.dto.BillingVerifyRequest;
import com.careconnect.dto.BillingVerifyResponse;

import java.time.Instant;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.JsonNode;
import org.springframework.beans.factory.annotation.Value;

@Service
public class AppleBillingService implements BillingService {

    // Apple production and sandbox endpoints
    private static final String APPLE_VERIFY_URL = "https://buy.itunes.apple.com/verifyReceipt";
    private static final String APPLE_VERIFY_SANDBOX_URL = "https://sandbox.itunes.apple.com/verifyReceipt";

    @Value("${apple.shared-secret:}")
    private String appleSharedSecret;

    @Override
    public BillingVerifyResponse verifyReceipt(BillingVerifyRequest request) throws Exception {
        RestTemplate rest = new RestTemplate();
        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.APPLICATION_JSON);

        ObjectMapper mapper = new ObjectMapper();

        // Build request JSON with shared secret when available
        String body = mapper.createObjectNode()
                .put("receipt-data", request.getReceipt())
                .put("password", appleSharedSecret != null ? appleSharedSecret : "")
                .toString();

        HttpEntity<String> entity = new HttpEntity<>(body, headers);

        ResponseEntity<String> resp = rest.postForEntity(APPLE_VERIFY_URL, entity, String.class);
        String responseBody = resp != null ? resp.getBody() : null;

        JsonNode root = responseBody != null ? mapper.readTree(responseBody) : null;
        int status = root != null && root.has("status") ? root.get("status").asInt() : -1;

        // If 21007 -> use sandbox endpoint
        if (status == 21007) {
            ResponseEntity<String> sandboxResp = rest.postForEntity(APPLE_VERIFY_SANDBOX_URL, entity, String.class);
            responseBody = sandboxResp != null ? sandboxResp.getBody() : responseBody;
            root = responseBody != null ? mapper.readTree(responseBody) : root;
            status = root != null && root.has("status") ? root.get("status").asInt() : status;
        }

        BillingVerifyResponse out = new BillingVerifyResponse();
        out.setPlatform("APPLE");

        if (status == 0 && root != null) {
            // success - extract latest receipt info for subscriptions
            JsonNode latest = null;
            if (root.has("latest_receipt_info") && root.get("latest_receipt_info").isArray()) {
                JsonNode arr = root.get("latest_receipt_info");
                latest = arr.get(arr.size() - 1);
            } else if (root.has("receipt") && root.get("receipt").has("in_app")) {
                JsonNode arr = root.get("receipt").get("in_app");
                latest = arr.get(arr.size() - 1);
            }

            if (latest != null) {
                String transactionId = latest.has("transaction_id") ? latest.get("transaction_id").asText() : null;
                String originalTransactionId = latest.has("original_transaction_id") ? latest.get("original_transaction_id").asText() : transactionId;
                long purchaseMs = latest.has("purchase_date_ms") ? latest.get("purchase_date_ms").asLong() : Instant.now().toEpochMilli();
                long expiryMs = latest.has("expires_date_ms") ? latest.get("expires_date_ms").asLong() : (purchaseMs + 30L * 24L * 3600L * 1000L);

                out.setSuccess(true);
                out.setExternalTransactionId(transactionId != null ? transactionId : originalTransactionId);
                out.setExternalSubscriptionId(originalTransactionId);
                out.setPurchaseDate(Instant.ofEpochMilli(purchaseMs));
                out.setExpiryDate(Instant.ofEpochMilli(expiryMs));
                out.setStatus(expiryMs > Instant.now().toEpochMilli() ? "ACTIVE" : "EXPIRED");
                out.setMessage("Verified with Apple");
                return out;
            }
        }

        out.setSuccess(false);
        out.setMessage(responseBody != null ? responseBody : "Apple verification failed or returned unknown status");
        out.setStatus("FAILED");
        return out;
    }
}
