package com.careconnect.controller;

import com.careconnect.dto.BillingVerifyRequest;
import com.careconnect.dto.BillingVerifyResponse;
import com.careconnect.model.BillingPlatform;
import com.careconnect.model.Subscription;
import com.careconnect.model.User;
import com.careconnect.repository.SubscriptionRepository;
import com.careconnect.repository.UserRepository;
import com.careconnect.security.JwtTokenProvider;
import com.careconnect.service.AppleBillingService;
import com.careconnect.service.GoogleBillingService;
import com.careconnect.service.PaymentService;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;

import java.time.Instant;
import java.util.Collections;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class BillingControllerTest {

    @Mock
    private AppleBillingService appleBillingService;
    @Mock
    private GoogleBillingService googleBillingService;
    @Mock
    private PaymentService paymentService;
    @Mock
    private SubscriptionRepository subscriptionRepository;
    @Mock
    private UserRepository userRepository;
    @Mock
    private JwtTokenProvider jwtTokenProvider;

    @InjectMocks
    private BillingController controller;

    // ---- Helpers ---------------------------------------------------------------

    private BillingVerifyRequest buildRequest(Long userId, String receipt) {
        BillingVerifyRequest req = new BillingVerifyRequest();
        req.setUserId(userId);
        req.setReceipt(receipt);
        return req;
    }

    private BillingVerifyResponse buildSuccessResponse() {
        BillingVerifyResponse resp = new BillingVerifyResponse();
        resp.setSuccess(true);
        resp.setPlatform("APPLE");
        resp.setExternalTransactionId("txn_123");
        resp.setExternalSubscriptionId("sub_orig_123");
        resp.setStatus("ACTIVE");
        resp.setPurchaseDate(Instant.parse("2026-01-01T00:00:00Z"));
        resp.setExpiryDate(Instant.parse("2026-02-01T00:00:00Z"));
        resp.setMessage("Verified with Apple");
        return resp;
    }

    private BillingVerifyResponse buildFailedResponse() {
        BillingVerifyResponse resp = new BillingVerifyResponse();
        resp.setSuccess(false);
        resp.setPlatform("APPLE");
        resp.setExternalTransactionId(null);
        resp.setStatus("FAILED");
        resp.setMessage("Verification failed");
        return resp;
    }

    private User buildUser(Long id) {
        User user = new User();
        user.setId(id);
        user.setEmail("test@example.com");
        return user;
    }

    // ---- verifyApple -----------------------------------------------------------

    @Test
    void verifyApple_successWithJwtAndUserId() throws Exception {
        BillingVerifyRequest request = buildRequest(10L, "apple_receipt_data");
        BillingVerifyResponse verifyResp = buildSuccessResponse();
        User user = buildUser(10L);

        when(jwtTokenProvider.validateToken("jwt_token")).thenReturn(true);
        when(jwtTokenProvider.getEmailFromToken("jwt_token")).thenReturn("test@example.com");
        when(userRepository.findByEmail("test@example.com")).thenReturn(Optional.of(user));
        when(appleBillingService.verifyReceipt(request)).thenReturn(verifyResp);
        when(subscriptionRepository.findAll()).thenReturn(Collections.emptyList());

        ResponseEntity<?> response = controller.verifyApple(request, "Bearer jwt_token");

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isEqualTo(verifyResp);
        verify(paymentService, times(2)).savePayment(any());
        verify(subscriptionRepository).save(any(Subscription.class));
    }

    @Test
    void verifyApple_successWithoutJwt_usesUserIdFallback() throws Exception {
        BillingVerifyRequest request = buildRequest(10L, "apple_receipt_data");
        BillingVerifyResponse verifyResp = buildSuccessResponse();
        User user = buildUser(10L);

        when(appleBillingService.verifyReceipt(request)).thenReturn(verifyResp);
        when(userRepository.findById(10L)).thenReturn(Optional.of(user));
        when(subscriptionRepository.findAll()).thenReturn(Collections.emptyList());

        ResponseEntity<?> response = controller.verifyApple(request, null);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        verify(paymentService, times(2)).savePayment(any());
        verify(subscriptionRepository).save(any(Subscription.class));
    }

    @Test
    void verifyApple_noUserResolved_skipsSubscription() throws Exception {
        BillingVerifyRequest request = buildRequest(null, "apple_receipt_data");
        BillingVerifyResponse verifyResp = buildSuccessResponse();

        when(appleBillingService.verifyReceipt(request)).thenReturn(verifyResp);

        ResponseEntity<?> response = controller.verifyApple(request, null);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        verify(paymentService, times(1)).savePayment(any());
        verify(subscriptionRepository, never()).save(any());
    }

    @Test
    void verifyApple_failedVerification_noUser_savesPaymentOnce() throws Exception {
        BillingVerifyRequest request = buildRequest(null, "bad_receipt");
        BillingVerifyResponse verifyResp = buildFailedResponse();

        when(appleBillingService.verifyReceipt(request)).thenReturn(verifyResp);

        ResponseEntity<?> response = controller.verifyApple(request, null);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        verify(paymentService, times(1)).savePayment(any());
    }

    @Test
    void verifyApple_existingSubscription_updatesIt() throws Exception {
        BillingVerifyRequest request = buildRequest(10L, "apple_receipt_data");
        BillingVerifyResponse verifyResp = buildSuccessResponse();
        User user = buildUser(10L);

        Subscription existingSub = new Subscription();
        existingSub.setId(50L);
        existingSub.setExternalSubscriptionId("sub_orig_123");

        when(appleBillingService.verifyReceipt(request)).thenReturn(verifyResp);
        when(userRepository.findById(10L)).thenReturn(Optional.of(user));
        when(subscriptionRepository.findAll()).thenReturn(List.of(existingSub));

        ResponseEntity<?> response = controller.verifyApple(request, null);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        verify(subscriptionRepository).save(existingSub);
        assertThat(existingSub.getStatus()).isEqualTo("ACTIVE");
        assertThat(existingSub.getPlatform()).isEqualTo(BillingPlatform.APPLE);
    }

    @Test
    void verifyApple_externalSubscriptionIdNull_createsNewSubscription() throws Exception {
        BillingVerifyRequest request = buildRequest(10L, "apple_receipt_data");
        BillingVerifyResponse verifyResp = buildSuccessResponse();
        verifyResp.setExternalSubscriptionId(null);
        User user = buildUser(10L);

        when(appleBillingService.verifyReceipt(request)).thenReturn(verifyResp);
        when(userRepository.findById(10L)).thenReturn(Optional.of(user));

        ResponseEntity<?> response = controller.verifyApple(request, null);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        verify(subscriptionRepository).save(any(Subscription.class));
    }

    @Test
    void verifyApple_jwtInvalid_proceedsWithoutResolvedUser() throws Exception {
        BillingVerifyRequest request = buildRequest(10L, "apple_receipt_data");
        BillingVerifyResponse verifyResp = buildSuccessResponse();
        User user = buildUser(10L);

        when(jwtTokenProvider.validateToken("bad_jwt")).thenReturn(false);
        when(appleBillingService.verifyReceipt(request)).thenReturn(verifyResp);
        when(userRepository.findById(10L)).thenReturn(Optional.of(user));
        when(subscriptionRepository.findAll()).thenReturn(Collections.emptyList());

        ResponseEntity<?> response = controller.verifyApple(request, "Bearer bad_jwt");

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        // Falls back to userId lookup
        verify(userRepository).findById(10L);
    }

    @Test
    void verifyApple_jwtValidationThrows_proceedsWithoutResolvedUser() throws Exception {
        BillingVerifyRequest request = buildRequest(10L, "apple_receipt_data");
        BillingVerifyResponse verifyResp = buildSuccessResponse();
        User user = buildUser(10L);

        when(jwtTokenProvider.validateToken("error_jwt")).thenThrow(new RuntimeException("JWT error"));
        when(appleBillingService.verifyReceipt(request)).thenReturn(verifyResp);
        when(userRepository.findById(10L)).thenReturn(Optional.of(user));
        when(subscriptionRepository.findAll()).thenReturn(Collections.emptyList());

        ResponseEntity<?> response = controller.verifyApple(request, "Bearer error_jwt");

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        verify(userRepository).findById(10L);
    }

    @Test
    void verifyApple_serviceThrows_returnsBadRequest() throws Exception {
        BillingVerifyRequest request = buildRequest(10L, "apple_receipt_data");

        when(appleBillingService.verifyReceipt(request)).thenThrow(new RuntimeException("Apple down"));

        ResponseEntity<?> response = controller.verifyApple(request, null);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
        @SuppressWarnings("unchecked")
        Map<String, Object> body = (Map<String, Object>) response.getBody();
        assertThat(body).containsEntry("error", "Apple down");
    }

    @Test
    void verifyApple_authHeaderNotBearer_noJwtResolution() throws Exception {
        BillingVerifyRequest request = buildRequest(null, "receipt");
        BillingVerifyResponse verifyResp = buildSuccessResponse();

        when(appleBillingService.verifyReceipt(request)).thenReturn(verifyResp);

        ResponseEntity<?> response = controller.verifyApple(request, "Basic abc123");

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        verify(jwtTokenProvider, never()).validateToken(anyString());
    }

    // ---- verifyGoogle ----------------------------------------------------------

    @Test
    void verifyGoogle_successWithJwtAndUserId() throws Exception {
        BillingVerifyRequest request = buildRequest(10L, "google_token");
        BillingVerifyResponse verifyResp = new BillingVerifyResponse();
        verifyResp.setSuccess(true);
        verifyResp.setPlatform("GOOGLE");
        verifyResp.setExternalTransactionId("order_456");
        verifyResp.setExternalSubscriptionId("order_456");
        verifyResp.setStatus("ACTIVE");
        verifyResp.setPurchaseDate(Instant.parse("2026-01-15T00:00:00Z"));
        verifyResp.setExpiryDate(Instant.parse("2026-02-15T00:00:00Z"));
        User user = buildUser(10L);

        when(jwtTokenProvider.validateToken("jwt_tok")).thenReturn(true);
        when(jwtTokenProvider.getEmailFromToken("jwt_tok")).thenReturn("test@example.com");
        when(userRepository.findByEmail("test@example.com")).thenReturn(Optional.of(user));
        when(googleBillingService.verifyReceipt(request)).thenReturn(verifyResp);
        when(subscriptionRepository.findAll()).thenReturn(Collections.emptyList());

        ResponseEntity<?> response = controller.verifyGoogle(request, "Bearer jwt_tok");

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isEqualTo(verifyResp);
        verify(paymentService, times(2)).savePayment(any());
        verify(subscriptionRepository).save(any(Subscription.class));
    }

    @Test
    void verifyGoogle_noUser_skipsSubscription() throws Exception {
        BillingVerifyRequest request = buildRequest(null, "google_token");
        BillingVerifyResponse verifyResp = new BillingVerifyResponse();
        verifyResp.setSuccess(true);
        verifyResp.setPlatform("GOOGLE");
        verifyResp.setExternalTransactionId("order_789");
        verifyResp.setStatus("ACTIVE");

        when(googleBillingService.verifyReceipt(request)).thenReturn(verifyResp);

        ResponseEntity<?> response = controller.verifyGoogle(request, null);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        verify(paymentService, times(1)).savePayment(any());
        verify(subscriptionRepository, never()).save(any());
    }

    @Test
    void verifyGoogle_serviceThrows_returnsBadRequest() throws Exception {
        BillingVerifyRequest request = buildRequest(10L, "google_token");

        when(googleBillingService.verifyReceipt(request)).thenThrow(new RuntimeException("Google down"));

        ResponseEntity<?> response = controller.verifyGoogle(request, null);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
        @SuppressWarnings("unchecked")
        Map<String, Object> body = (Map<String, Object>) response.getBody();
        assertThat(body).containsEntry("error", "Google down");
    }

    @Test
    void verifyGoogle_jwtValidationThrows_proceedsWithFallback() throws Exception {
        BillingVerifyRequest request = buildRequest(10L, "google_token");
        BillingVerifyResponse verifyResp = new BillingVerifyResponse();
        verifyResp.setSuccess(true);
        verifyResp.setPlatform("GOOGLE");
        verifyResp.setExternalTransactionId("order_000");
        verifyResp.setExternalSubscriptionId(null);
        verifyResp.setStatus("ACTIVE");
        User user = buildUser(10L);

        when(jwtTokenProvider.validateToken("err_jwt")).thenThrow(new RuntimeException("JWT exploded"));
        when(googleBillingService.verifyReceipt(request)).thenReturn(verifyResp);
        when(userRepository.findById(10L)).thenReturn(Optional.of(user));

        ResponseEntity<?> response = controller.verifyGoogle(request, "Bearer err_jwt");

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        verify(userRepository).findById(10L);
    }

    @Test
    void verifyGoogle_existingSubscription_updatesIt() throws Exception {
        BillingVerifyRequest request = buildRequest(10L, "google_token");
        BillingVerifyResponse verifyResp = new BillingVerifyResponse();
        verifyResp.setSuccess(true);
        verifyResp.setPlatform("GOOGLE");
        verifyResp.setExternalTransactionId("order_456");
        verifyResp.setExternalSubscriptionId("order_456");
        verifyResp.setStatus("ACTIVE");
        verifyResp.setPurchaseDate(Instant.parse("2026-01-15T00:00:00Z"));
        verifyResp.setExpiryDate(Instant.parse("2026-02-15T00:00:00Z"));
        User user = buildUser(10L);

        Subscription existingSub = new Subscription();
        existingSub.setId(70L);
        existingSub.setExternalSubscriptionId("order_456");

        when(googleBillingService.verifyReceipt(request)).thenReturn(verifyResp);
        when(userRepository.findById(10L)).thenReturn(Optional.of(user));
        when(subscriptionRepository.findAll()).thenReturn(List.of(existingSub));

        ResponseEntity<?> response = controller.verifyGoogle(request, null);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        verify(subscriptionRepository).save(existingSub);
        assertThat(existingSub.getPlatform()).isEqualTo(BillingPlatform.GOOGLE);
    }

    @Test
    void verifyGoogle_authHeaderNotBearer_noJwtResolution() throws Exception {
        BillingVerifyRequest request = buildRequest(null, "google_token");
        BillingVerifyResponse verifyResp = new BillingVerifyResponse();
        verifyResp.setSuccess(true);
        verifyResp.setPlatform("GOOGLE");
        verifyResp.setExternalTransactionId("order_x");
        verifyResp.setStatus("ACTIVE");

        when(googleBillingService.verifyReceipt(request)).thenReturn(verifyResp);

        ResponseEntity<?> response = controller.verifyGoogle(request, "Basic xyz");

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        verify(jwtTokenProvider, never()).validateToken(anyString());
    }

    // ---- Webhooks --------------------------------------------------------------

    @Test
    void appleWebhook_returnsOkWithMessage() {
        ResponseEntity<?> response = controller.appleWebhook("{\"type\":\"test\"}", null);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        @SuppressWarnings("unchecked")
        Map<String, Object> body = (Map<String, Object>) response.getBody();
        assertThat(body).containsEntry("message", "apple webhook received");
    }

    @Test
    void appleWebhook_withAuth_returnsOk() {
        ResponseEntity<?> response = controller.appleWebhook("{}", "Bearer some_auth");

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
    }

    @Test
    void googleWebhook_returnsOkWithMessage() {
        ResponseEntity<?> response = controller.googleWebhook("{\"type\":\"test\"}", null);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        @SuppressWarnings("unchecked")
        Map<String, Object> body = (Map<String, Object>) response.getBody();
        assertThat(body).containsEntry("message", "google webhook received");
    }

    @Test
    void googleWebhook_withAuth_returnsOk() {
        ResponseEntity<?> response = controller.googleWebhook("{}", "Bearer some_auth");

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
    }

    // ---- verifyApple: user found by email but not by id -----------------------

    @Test
    void verifyApple_jwtResolvesUser_userIdNotNeeded() throws Exception {
        BillingVerifyRequest request = buildRequest(null, "apple_receipt_data");
        BillingVerifyResponse verifyResp = buildSuccessResponse();
        User user = buildUser(10L);

        when(jwtTokenProvider.validateToken("jwt_token")).thenReturn(true);
        when(jwtTokenProvider.getEmailFromToken("jwt_token")).thenReturn("test@example.com");
        when(userRepository.findByEmail("test@example.com")).thenReturn(Optional.of(user));
        when(appleBillingService.verifyReceipt(request)).thenReturn(verifyResp);
        when(subscriptionRepository.findAll()).thenReturn(Collections.emptyList());

        ResponseEntity<?> response = controller.verifyApple(request, "Bearer jwt_token");

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        verify(userRepository, never()).findById(any());
        verify(subscriptionRepository).save(any(Subscription.class));
    }

    @Test
    void verifyGoogle_userIdFallback_userNotFound() throws Exception {
        BillingVerifyRequest request = buildRequest(999L, "google_token");
        BillingVerifyResponse verifyResp = new BillingVerifyResponse();
        verifyResp.setSuccess(true);
        verifyResp.setPlatform("GOOGLE");
        verifyResp.setExternalTransactionId("order_x");
        verifyResp.setStatus("ACTIVE");

        when(googleBillingService.verifyReceipt(request)).thenReturn(verifyResp);
        when(userRepository.findById(999L)).thenReturn(Optional.empty());

        ResponseEntity<?> response = controller.verifyGoogle(request, null);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        verify(subscriptionRepository, never()).save(any());
        verify(paymentService, times(1)).savePayment(any());
    }
}
