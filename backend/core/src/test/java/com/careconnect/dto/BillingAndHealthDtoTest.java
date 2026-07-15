package com.careconnect.dto;

// Tests for billing DTOs (BillingQuoteRequest/Response, BillingVerifyRequest/Response),
// AllergyDTO, AiAllergyDTO, and AiSymptomDTO.

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import java.time.Instant;

import static org.junit.jupiter.api.Assertions.*;

@DisplayName("Billing & Health DTOs")
class BillingAndHealthDtoTest {

    @Nested
    @DisplayName("BillingQuoteRequest")
    class BillingQuoteRequestTests {

        @Test
        @DisplayName("builder sets all fields")
        void builderSetsAll() {
            BillingQuoteRequest req = BillingQuoteRequest.builder()
                    .tierId(1L)
                    .userId(42L)
                    .state("CA")
                    .postalCode("90210")
                    .city("Beverly Hills")
                    .build();

            assertEquals(1L, req.getTierId());
            assertEquals(42L, req.getUserId());
            assertEquals("CA", req.getState());
            assertEquals("90210", req.getPostalCode());
            assertEquals("Beverly Hills", req.getCity());
        }

        @Test
        @DisplayName("no-arg constructor")
        void noArgConstructor() {
            BillingQuoteRequest req = new BillingQuoteRequest();
            assertNull(req.getTierId());
            assertNull(req.getState());
        }
    }

    @Nested
    @DisplayName("BillingQuoteResponse")
    class BillingQuoteResponseTests {

        @Test
        @DisplayName("builder sets itemized billing fields")
        void builderSetsAll() {
            BillingQuoteResponse resp = BillingQuoteResponse.builder()
                    .tierId(1L)
                    .tierName("Premium")
                    .subtotalCents(1999L)
                    .taxCents(165L)
                    .totalCents(2164L)
                    .currency("USD")
                    .taxRate(0.0825)
                    .taxJurisdiction("CA - California")
                    .build();

            assertEquals("Premium", resp.getTierName());
            assertEquals(1999L, resp.getSubtotalCents());
            assertEquals(165L, resp.getTaxCents());
            assertEquals(2164L, resp.getTotalCents());
            assertEquals("USD", resp.getCurrency());
            assertEquals(0.0825, resp.getTaxRate());
        }

        @Test
        @DisplayName("error message set when tax calc fails")
        void errorMessage() {
            BillingQuoteResponse resp = BillingQuoteResponse.builder()
                    .errorMessage("Tax service unavailable")
                    .build();
            assertEquals("Tax service unavailable", resp.getErrorMessage());
        }
    }

    @Nested
    @DisplayName("BillingVerifyRequest")
    class BillingVerifyRequestTests {

        @Test
        @DisplayName("setters populate all fields")
        void settersWork() {
            BillingVerifyRequest req = new BillingVerifyRequest();
            req.setUserId(42L);
            req.setPlatform("APPLE");
            req.setReceipt("base64receipt==");
            req.setProductId("com.careconnect.premium");
            req.setPackageName("com.careconnect.app");

            assertEquals(42L, req.getUserId());
            assertEquals("APPLE", req.getPlatform());
            assertEquals("base64receipt==", req.getReceipt());
            assertEquals("com.careconnect.premium", req.getProductId());
        }
    }

    @Nested
    @DisplayName("BillingVerifyResponse")
    class BillingVerifyResponseTests {

        @Test
        @DisplayName("successful verification")
        void successfulVerification() {
            BillingVerifyResponse resp = new BillingVerifyResponse();
            resp.setSuccess(true);
            resp.setPlatform("GOOGLE");
            resp.setExternalSubscriptionId("sub-123");
            resp.setExternalTransactionId("txn-456");
            resp.setStatus("ACTIVE");
            resp.setPurchaseDate(Instant.parse("2026-01-01T00:00:00Z"));
            resp.setExpiryDate(Instant.parse("2026-02-01T00:00:00Z"));
            resp.setMessage("Verified successfully");

            assertTrue(resp.isSuccess());
            assertEquals("ACTIVE", resp.getStatus());
            assertNotNull(resp.getPurchaseDate());
            assertNotNull(resp.getExpiryDate());
        }

        @Test
        @DisplayName("failed verification")
        void failedVerification() {
            BillingVerifyResponse resp = new BillingVerifyResponse();
            resp.setSuccess(false);
            resp.setStatus("EXPIRED");
            resp.setMessage("Receipt expired");

            assertFalse(resp.isSuccess());
            assertEquals("EXPIRED", resp.getStatus());
        }
    }

    @Nested
    @DisplayName("AllergyDTO")
    class AllergyDtoTests {

        @Test
        @DisplayName("builder sets all fields")
        void builderSetsAll() {
            AllergyDTO dto = AllergyDTO.builder()
                    .id(1L)
                    .patientId(42L)
                    .allergen("Penicillin")
                    .allergyType(com.careconnect.model.Allergy.AllergyType.MEDICATION)
                    .severity(com.careconnect.model.Allergy.AllergySeverity.SEVERE)
                    .reaction("Anaphylaxis")
                    .notes("Carry EpiPen")
                    .diagnosedDate("2020-06-15")
                    .isActive(true)
                    .build();

            assertEquals("Penicillin", dto.allergen());
            assertEquals(com.careconnect.model.Allergy.AllergyType.MEDICATION, dto.allergyType());
            assertEquals(com.careconnect.model.Allergy.AllergySeverity.SEVERE, dto.severity());
            assertEquals("Anaphylaxis", dto.reaction());
            assertTrue(dto.isActive());
        }
    }

    @Nested
    @DisplayName("AiAllergyDTO")
    class AiAllergyDtoTests {

        @Test
        @DisplayName("Request sets required fields")
        void requestSetsFields() {
            AiAllergyDTO.Request req = new AiAllergyDTO.Request();
            req.setPatientId(42L);
            req.setText("Patient reports allergy to shellfish");

            assertEquals(42L, req.getPatientId());
            assertEquals("Patient reports allergy to shellfish", req.getText());
            assertNull(req.getContext());
        }

        @Test
        @DisplayName("Result stores extraction output")
        void resultStoresOutput() {
            AiAllergyDTO.Result result = new AiAllergyDTO.Result();
            result.setAllergen("Shellfish");
            result.setReaction("Hives");
            result.setSeverity("MODERATE");

            assertEquals("Shellfish", result.getAllergen());
            assertEquals("Hives", result.getReaction());
            assertEquals("MODERATE", result.getSeverity());
        }
    }

    @Nested
    @DisplayName("AiSymptomDTO")
    class AiSymptomDtoTests {

        @Test
        @DisplayName("Request sets fields")
        void requestSetsFields() {
            AiSymptomDTO.Request req = new AiSymptomDTO.Request();
            req.setPatientId(10L);
            req.setText("I have a headache and feel dizzy");

            assertEquals(10L, req.getPatientId());
            assertNotNull(req.getText());
        }

        @Test
        @DisplayName("Result stores symptom extraction")
        void resultStoresExtraction() {
            AiSymptomDTO.Result result = new AiSymptomDTO.Result();
            result.setSymptomKey("headache");
            result.setSymptomValue("throbbing pain");
            result.setSeverity("MODERATE");
            result.setNotes("Patient also reports dizziness");

            assertEquals("headache", result.getSymptomKey());
            assertEquals("throbbing pain", result.getSymptomValue());
            assertEquals("MODERATE", result.getSeverity());
        }
    }
}
