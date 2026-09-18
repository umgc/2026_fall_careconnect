package com.careconnect.model.invoice;

import jakarta.persistence.*;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.math.BigDecimal;
import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.List;

@Builder
@Entity
@Table(name = "invoices")
@Data
@AllArgsConstructor
@NoArgsConstructor
public class Invoice {

    @Id
    private String id;

    @Column(name = "invoice_number", nullable = false)
    @Builder.Default
    private String invoiceNumber = "";

    // Provider snapshot
    @Column(name = "provider_name", nullable = false)
    @Builder.Default
    private String providerName = "";
    @Column(name = "provider_address", nullable = false)
    @Builder.Default
    private String providerAddress = "";
    @Column(name = "provider_phone", nullable = false)
    @Builder.Default
    private String providerPhone = "";
    @Column(name = "provider_email")
    private String providerEmail;

    // Patient snapshot
    @Column(name = "patient_name", nullable = false)
    @Builder.Default
    private String patientName = "";
    @Column(name = "patient_address")
    private String patientAddress;
    @Column(name = "patient_account_no")
    private String patientAccountNumber;
    @Column(name = "patient_billing_address")
    private String patientBillingAddress;

    // Dates
    @Column(name = "statement_date", nullable = false)
    private OffsetDateTime statementDate;
    @Column(name = "due_date", nullable = false)
    private OffsetDateTime dueDate;
    @Column(name = "paid_date")
    private OffsetDateTime paidDate;

    // Status and flags
    @Enumerated(EnumType.STRING)
    @Column(name = "payment_status", nullable = false)
    private PaymentStatus paymentStatus;
    @Column(name = "billed_to_insurance", nullable = false)
    private boolean billedToInsurance;

    // Amounts
    @Column(name = "total_charges")
    private BigDecimal totalCharges;
    @Column(name = "total_adjustments")
    private BigDecimal totalAdjustments;
    @Column(name = "total_total")
    private BigDecimal total;
    @Column(name = "amount_due")
    private BigDecimal amountDue;

    // Payment references
    @Column(name = "payment_link")
    private String paymentLink;
    @Column(name = "qr_code_url")
    private String qrCodeUrl;
    @Column(name = "payment_notes")
    private String paymentNotes;

    // New: supported methods stored as CSV
    @Column(name = "supported_methods")
    private String supportedMethodsCsv;

    // Check payable
    @Column(name = "check_name")
    private String checkName;
    @Column(name = "check_address")
    private String checkAddress;
    @Column(name = "check_reference")
    private String checkReference;

    // New: AI summary
    @Column(name = "ai_summary", columnDefinition = "text")
    private String aiSummary;

    // New: audit and document link
    @Column(name = "created_by")
    private String createdBy;
    @Column(name = "updated_by")
    private String updatedBy;
    @Column(name = "document_link")
    private String documentLink;

    @Column(name = "created_at", nullable = false)
    private OffsetDateTime createdAt;
    @Column(name = "updated_at", nullable = false)
    private OffsetDateTime updatedAt;

    // Children
    @OneToMany(mappedBy = "invoice", cascade = CascadeType.ALL, orphanRemoval = true)
    @Builder.Default
    private List<ServiceLine> services = new ArrayList<>();

    @OneToMany(mappedBy = "invoice", cascade = CascadeType.ALL, orphanRemoval = true)
    @Builder.Default
    private List<HistoryEntry> history = new ArrayList<>();

    @OneToMany(mappedBy = "invoice", cascade = CascadeType.ALL, orphanRemoval = true)
    @Builder.Default
    private List<RecommendedAction> recommendedActions = new ArrayList<>();
    @OneToMany(mappedBy = "invoice", cascade = CascadeType.ALL, orphanRemoval = true)
    @OrderBy("paymentDate ASC")
    @Builder.Default
    private java.util.List<InvoicePayment> payments = new java.util.ArrayList<>();

    public java.util.List<InvoicePayment> getPayments() {
        return payments;
    }

    public void setPayments(java.util.List<InvoicePayment> payments) {
        this.payments = payments;
    }

    public void addPayment(InvoicePayment p) {
        p.setInvoice(this);
        this.payments.add(p);
    }

    public void removePaymentById(String paymentId) {
        this.payments.removeIf(p -> p.getId().equals(paymentId));
    }
}
