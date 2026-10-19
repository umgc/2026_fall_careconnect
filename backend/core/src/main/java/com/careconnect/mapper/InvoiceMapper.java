package com.careconnect.mapper;

import com.careconnect.dto.invoice.InvoiceDto;
import com.careconnect.dto.invoice.PaymentDto;
import com.careconnect.model.invoice.*;
import com.careconnect.util.DateParsers;

import java.math.BigDecimal;
import java.time.OffsetDateTime;
import java.util.*;
import java.util.stream.Collectors;

public final class InvoiceMapper {

    private InvoiceMapper() {
    }

    // ---------- to entity ----------
    public static Invoice toEntity(InvoiceDto dto) {
        Invoice e = new Invoice();
        e.setId(dto.id);
        e.setInvoiceNumber(nz(dto.invoiceNumber));

        // Provider
        if (dto.provider != null) {
            e.setProviderName(nz(dto.provider.name));
            e.setProviderAddress(nz(dto.provider.address));
            e.setProviderPhone(nz(dto.provider.phone));
            e.setProviderEmail(dto.provider.email);
        }

        // Patient
        if (dto.patient != null) {
            e.setPatientName(nz(dto.patient.name));
            e.setPatientAddress(dto.patient.address);
            e.setPatientAccountNumber(dto.patient.accountNumber);
            e.setPatientBillingAddress(dto.patient.billingAddress);
        }

        // Dates
        if (dto.dates != null) {
            e.setStatementDate(DateParsers.parseOffsetOrLocalToUtc(dto.dates.statementDate));
            e.setDueDate(DateParsers.parseOffsetOrLocalToUtc(dto.dates.dueDate));
            e.setPaidDate(DateParsers.parseNullableOffsetOrLocalToUtc(dto.dates.paidDate));
        }

        // Status and flags
        e.setPaymentStatus(parseStatus(dto.paymentStatus));
        e.setBilledToInsurance(dto.billedToInsurance);

        // Amounts
        if (dto.amounts != null) {
            e.setTotalCharges(toBD(dto.amounts.totalCharges));
            e.setTotalAdjustments(toBD(dto.amounts.totalAdjustments));
            e.setTotal(toBD(dto.amounts.total));
            e.setAmountDue(toBD(dto.amounts.amountDue));
        }

        // Payment references including supported methods
        if (dto.paymentReferences != null) {
            e.setPaymentLink(dto.paymentReferences.paymentLink);
            e.setQrCodeUrl(dto.paymentReferences.qrCodeUrl);
            e.setPaymentNotes(dto.paymentReferences.notes);
            e.setSupportedMethodsCsv(joinCsv(dto.paymentReferences.supportedMethods));
        }

        // Check payable
        if (dto.checkPayableTo != null) {
            e.setCheckName(dto.checkPayableTo.name);
            e.setCheckAddress(dto.checkPayableTo.address);
            e.setCheckReference(dto.checkPayableTo.reference);
        }

        // New: AI and audit and doc link
        e.setAiSummary(dto.aiSummary);
        e.setCreatedBy(dto.createdBy);
        e.setUpdatedBy(dto.updatedBy);
        e.setDocumentLink(dto.documentLink);

        // Timestamps
        e.setCreatedAt(DateParsers.parseNullableOffsetOrLocalToUtc(dto.createdAt));
        e.setUpdatedAt(DateParsers.parseNullableOffsetOrLocalToUtc(dto.updatedAt));

        // Children
        List<ServiceLine> lines = new ArrayList<>();
        if (dto.services != null) {
            for (InvoiceDto.ServiceLine s : dto.services) {
                ServiceLine sl = new ServiceLine();
                sl.setInvoice(e);
                sl.setDescription(s.description);
                sl.setServiceCode(s.serviceCode);
                sl.setServiceDate(parseNullable(s.serviceDate));
                sl.setCharge(toBD(s.charge));
                sl.setPatientBalance(toBD(s.patientBalance));
                sl.setInsuranceAdjustments(toBD(s.insuranceAdjustments));
                lines.add(sl);
            }
        }
        e.setServices(lines);

        List<HistoryEntry> hist = new ArrayList<>();
        if (dto.history != null) {
            for (InvoiceDto.HistoryEntry h : dto.history) {
                HistoryEntry he = new HistoryEntry();
                he.setInvoice(e);
                he.setVersion(h.version == null ? 1 : h.version);
                he.setChanges(nz(h.changes));
                he.setUserId(nz(h.userId));
                he.setAction(nz(h.action));
                he.setDetails(nz(h.details));
                he.setTimestamp(parse(h.timestamp));
                hist.add(he);
            }
        }
        e.setHistory(hist);

        List<RecommendedAction> acts = new ArrayList<>();
        if (dto.recommendedActions != null) {
            for (String a : dto.recommendedActions) {
                RecommendedAction ra = new RecommendedAction();
                ra.setInvoice(e);
                ra.setActionText(a);
                acts.add(ra);
            }
        }
        e.setRecommendedActions(acts);

        if (dto.payments != null) {
            e.getPayments().clear();
            for (PaymentDto pd : dto.payments) {
                e.addPayment(toEntity(e, pd));
            }
        }
        return e;
    }

    // ---------- to dto ----------
    public static InvoiceDto toDto(Invoice e) {
        InvoiceDto dto = new InvoiceDto();
        dto.id = e.getId();
        dto.invoiceNumber = e.getInvoiceNumber();

        InvoiceDto.ProviderInfo p = new InvoiceDto.ProviderInfo();
        p.name = e.getProviderName();
        p.address = e.getProviderAddress();
        p.phone = e.getProviderPhone();
        p.email = e.getProviderEmail();
        dto.provider = p;

        InvoiceDto.PatientInfo pt = new InvoiceDto.PatientInfo();
        pt.name = e.getPatientName();
        pt.address = e.getPatientAddress();
        pt.accountNumber = e.getPatientAccountNumber();
        pt.billingAddress = e.getPatientBillingAddress();
        dto.patient = pt;

        InvoiceDto.InvoiceDates d = new InvoiceDto.InvoiceDates();
        d.statementDate = fmt(e.getStatementDate());
        d.dueDate = fmt(e.getDueDate());
        d.paidDate = fmtNullable(e.getPaidDate());
        dto.dates = d;

        dto.paymentStatus = e.getPaymentStatus().name();
        dto.billedToInsurance = e.isBilledToInsurance();

        InvoiceDto.Amounts a = new InvoiceDto.Amounts();
        a.totalCharges = toD(e.getTotalCharges());
        a.totalAdjustments = toD(e.getTotalAdjustments());
        a.total = toD(e.getTotal());
        a.amountDue = toD(e.getAmountDue());
        dto.amounts = a;

        InvoiceDto.PaymentReferences r = new InvoiceDto.PaymentReferences();
        r.paymentLink = e.getPaymentLink();
        r.qrCodeUrl = e.getQrCodeUrl();
        r.notes = e.getPaymentNotes();
        r.supportedMethods = splitCsv(e.getSupportedMethodsCsv());
        dto.paymentReferences = r;

        if (e.getCheckName() != null || e.getCheckAddress() != null || e.getCheckReference() != null) {
            InvoiceDto.CheckPayableTo c = new InvoiceDto.CheckPayableTo();
            c.name = e.getCheckName();
            c.address = e.getCheckAddress();
            c.reference = e.getCheckReference();
            dto.checkPayableTo = c;
        }

        // New fields
        dto.aiSummary = e.getAiSummary();
        dto.createdBy = e.getCreatedBy();
        dto.updatedBy = e.getUpdatedBy();
        dto.documentLink = e.getDocumentLink();

        dto.createdAt = fmt(e.getCreatedAt());
        dto.updatedAt = fmt(e.getUpdatedAt());

        List<InvoiceDto.ServiceLine> sl = new ArrayList<>();
        for (ServiceLine s : e.getServices()) {
            InvoiceDto.ServiceLine x = new InvoiceDto.ServiceLine();
            x.description = s.getDescription();
            x.serviceCode = s.getServiceCode();
            x.serviceDate = fmtNullable(s.getServiceDate());
            x.charge = toD(s.getCharge());
            x.patientBalance = toD(s.getPatientBalance());
            x.insuranceAdjustments = toD(s.getInsuranceAdjustments());
            sl.add(x);
        }
        dto.services = sl;

        List<InvoiceDto.HistoryEntry> hh = new ArrayList<>();
        for (HistoryEntry h : e.getHistory()) {
            InvoiceDto.HistoryEntry x = new InvoiceDto.HistoryEntry();
            x.version = h.getVersion();
            x.changes = h.getChanges();
            x.userId = h.getUserId();
            x.action = h.getAction();
            x.details = h.getDetails();
            x.timestamp = fmt(h.getTimestamp());
            hh.add(x);
        }
        dto.history = hh;

        List<String> ra = new ArrayList<>();
        for (RecommendedAction ract : e.getRecommendedActions()) {
            ra.add(ract.getActionText());
        }
        dto.recommendedActions = ra;

        dto.payments = e.getPayments().stream()
                .map(InvoiceMapper::toDto)
                .collect(Collectors.toList());

        return dto;
    }

    // ---------- helpers ----------
    private static String nz(String s) {
        return s == null ? "" : s;
    }

    // tolerant parsing and normalized formatting
    private static OffsetDateTime parse(String s) {
        return DateParsers.parseOffsetOrLocalToUtc(s);
    }

    private static OffsetDateTime parseNullable(String s) {
        return DateParsers.parseNullableOffsetOrLocalToUtc(s);
    }

    private static String fmt(OffsetDateTime t) {
        return DateParsers.format(t);
    }

    private static String fmtNullable(OffsetDateTime t) {
        return DateParsers.formatNullable(t);
    }

    private static BigDecimal toBD(Double d) {
        return d == null ? null : BigDecimal.valueOf(d);
    }

    private static Double toD(BigDecimal bd) {
        return bd == null ? null : bd.doubleValue();
    }

    private static PaymentStatus parseStatus(String s) {
        if (s == null) return PaymentStatus.PENDING;
        switch (s) {
            case "pending":
                return PaymentStatus.PENDING;
            case "overdue":
                return PaymentStatus.OVERDUE;
            case "pendingInsurance":
                return PaymentStatus.PENDING_INSURANCE;
            case "sent":
                return PaymentStatus.SENT;
            case "paid":
                return PaymentStatus.PAID;
            case "partialPayment":
                return PaymentStatus.PARTIAL_PAYMENT;
            case "rejectedInsurance":
                return PaymentStatus.REJECTED_INSURANCE;
            default:
                return PaymentStatus.PENDING;
        }
    }

    private static String joinCsv(List<String> list) {
        if (list == null || list.isEmpty()) return null;
        return list.stream()
                .map(String::trim)
                .filter(s -> !s.isEmpty())
                .collect(Collectors.joining(","));
    }

    private static List<String> splitCsv(String csv) {
        if (csv == null || csv.isBlank()) return List.of();
        return Arrays.stream(csv.split(","))
                .map(String::trim)
                .filter(s -> !s.isEmpty())
                .collect(Collectors.toList());
    }

    public static PaymentDto toDto(InvoicePayment p) {
        PaymentDto d = new PaymentDto();
        d.id = p.getId();
        d.confirmationNumber = p.getConfirmationNumber();
        d.date = DateParsers.formatNullable(p.getPaymentDate());
        d.methodKey = p.getMethodKey();
        d.amountPaid = p.getAmountPaid();
        d.planEnabled = p.isPlanEnabled();
        d.planDurationMonths = p.getPlanMonths();
        d.createdBy = p.getCreatedBy();
        return d;
    }

    public static InvoicePayment toEntity(Invoice invoice, PaymentDto d) {
        InvoicePayment p = new InvoicePayment();
        if (d.id != null && !d.id.isBlank()) p.setId(d.id);
        p.setInvoice(invoice);
        p.setConfirmationNumber(d.confirmationNumber);
        p.setPaymentDate(DateParsers.parseOffsetOrLocalToUtc(d.date));
        p.setMethodKey(Objects.requireNonNullElse(d.methodKey, "online"));
        p.setAmountPaid(d.amountPaid);
        p.setPlanEnabled(Boolean.TRUE.equals(d.planEnabled));
        p.setPlanMonths(d.planDurationMonths);
        p.setCreatedBy(d.createdBy);
        return p;
    }
}
