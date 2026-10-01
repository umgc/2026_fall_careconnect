package com.careconnect.dto.invoice;

import java.util.List;

public class InvoiceDto {
    public String id;
    public String invoiceNumber;

    public ProviderInfo provider;
    public PatientInfo patient;
    public InvoiceDates dates;
    public List<ServiceLine> services;

    public String paymentStatus;
    public boolean billedToInsurance;

    public Amounts amounts;
    public PaymentReferences paymentReferences;
    public CheckPayableTo checkPayableTo;

    public String aiSummary;
    public String createdBy;
    public String updatedBy;
    public String documentLink;
    public String createdAt;
    public String updatedAt;
    public List<HistoryEntry> history;
    public java.util.List<PaymentDto> payments;
    public List<String> recommendedActions;

    public static class ProviderInfo {
        public String name;
        public String address;
        public String phone;
        public String email;
    }

    public static class PatientInfo {
        public String name;
        public String address;
        public String accountNumber;
        public String billingAddress;
    }

    public static class InvoiceDates {
        public String statementDate;
        public String dueDate;
        public String paidDate;
    }

    public static class ServiceLine {
        public String description;
        public String serviceCode;
        public String serviceDate;
        public Double charge;
        public Double patientBalance;
        public Double insuranceAdjustments;
    }

    public static class Amounts {
        public Double totalCharges;
        public Double totalAdjustments;
        public Double total;
        public Double amountDue;
    }

    public static class PaymentReferences {
        public String paymentLink;
        public String qrCodeUrl;
        public String notes;
        public List<String> supportedMethods;
    }

    public static class CheckPayableTo {
        public String name;
        public String address;
        public String reference;
    }

    public static class HistoryEntry {
        public Integer version;
        public String changes;
        public String userId;
        public String action;
        public String details;
        public String timestamp;
    }
}
