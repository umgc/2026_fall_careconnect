package com.careconnect.model.invoice;

import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;

import static org.assertj.core.api.Assertions.assertThat;

class InvoicePaymentTest {

    // ─── No-arg constructor ───────────────────────────────────────────────────

    @Test
    void noArgConstructor_createsInstance() throws Exception {
        final InvoicePayment payment = new InvoicePayment();

        assertThat(payment).isNotNull();
        // id defaults to a UUID string
        assertThat(payment.getId()).isNotNull();
        assertThat(payment.getId()).isNotBlank();
        assertThat(payment.getInvoice()).isNull();
        assertThat(payment.getConfirmationNumber()).isNull();
        assertThat(payment.getPaymentDate()).isNull();
        assertThat(payment.getMethodKey()).isNull();
        assertThat(payment.getAmountPaid()).isNull();
        assertThat(payment.isPlanEnabled()).isFalse();
        assertThat(payment.getPlanMonths()).isNull();
        // createdAt defaults to now
        assertThat(payment.getCreatedAt()).isNotNull();
        assertThat(payment.getCreatedBy()).isNull();
    }

    @Test
    void noArgConstructor_idIsUUID() throws Exception {
        final InvoicePayment p1 = new InvoicePayment();
        final InvoicePayment p2 = new InvoicePayment();

        // Each new instance gets a different UUID
        assertThat(p1.getId()).isNotEqualTo(p2.getId());
    }

    // ─── Setters ──────────────────────────────────────────────────────────────

    @Test
    void setters_updateFields() throws Exception {
        final InvoicePayment payment = new InvoicePayment();
        final Invoice invoice = Invoice.builder().id("INV-500").build();
        final OffsetDateTime paymentDate = OffsetDateTime.of(2025, 4, 10, 12, 0, 0, 0, ZoneOffset.UTC);
        final OffsetDateTime createdAt = OffsetDateTime.of(2025, 4, 10, 12, 0, 0, 0, ZoneOffset.UTC);

        payment.setId("custom-id-123");
        payment.setInvoice(invoice);
        payment.setConfirmationNumber("CONF-9876");
        payment.setPaymentDate(paymentDate);
        payment.setMethodKey("credit_card");
        payment.setAmountPaid(new BigDecimal("250.00"));
        payment.setPlanEnabled(true);
        payment.setPlanMonths(12);
        payment.setCreatedAt(createdAt);
        payment.setCreatedBy("user-99");

        assertThat(payment.getId()).isEqualTo("custom-id-123");
        assertThat(payment.getInvoice()).isSameAs(invoice);
        assertThat(payment.getConfirmationNumber()).isEqualTo("CONF-9876");
        assertThat(payment.getPaymentDate()).isEqualTo(paymentDate);
        assertThat(payment.getMethodKey()).isEqualTo("credit_card");
        assertThat(payment.getAmountPaid()).isEqualByComparingTo(new BigDecimal("250.00"));
        assertThat(payment.isPlanEnabled()).isTrue();
        assertThat(payment.getPlanMonths()).isEqualTo(12);
        assertThat(payment.getCreatedAt()).isEqualTo(createdAt);
        assertThat(payment.getCreatedBy()).isEqualTo("user-99");
    }

    // ─── planEnabled default ──────────────────────────────────────────────────

    @Test
    void planEnabled_defaultsFalse() throws Exception {
        final InvoicePayment payment = new InvoicePayment();
        assertThat(payment.isPlanEnabled()).isFalse();
    }

    @Test
    void planEnabled_canBeSetTrue() throws Exception {
        final InvoicePayment payment = new InvoicePayment();
        payment.setPlanEnabled(true);
        assertThat(payment.isPlanEnabled()).isTrue();
    }

    // ─── methodKey values ─────────────────────────────────────────────────────

    @Test
    void methodKey_check_setsCorrectly() throws Exception {
        final InvoicePayment payment = new InvoicePayment();
        payment.setMethodKey("check");
        assertThat(payment.getMethodKey()).isEqualTo("check");
    }

    @Test
    void methodKey_online_setsCorrectly() throws Exception {
        final InvoicePayment payment = new InvoicePayment();
        payment.setMethodKey("online");
        assertThat(payment.getMethodKey()).isEqualTo("online");
    }

    @Test
    void methodKey_telephone_setsCorrectly() throws Exception {
        final InvoicePayment payment = new InvoicePayment();
        payment.setMethodKey("telephone");
        assertThat(payment.getMethodKey()).isEqualTo("telephone");
    }
}
