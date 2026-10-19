package com.careconnect.spec;

import com.careconnect.model.invoice.Invoice;
import com.careconnect.model.invoice.PaymentStatus;
import org.springframework.data.jpa.domain.Specification;

import java.math.BigDecimal;
import java.time.OffsetDateTime;
import java.util.Set;

public final class InvoiceSpecs {
    private InvoiceSpecs() {
    }

    public static Specification<Invoice> search(String q) {
        if (q == null || q.trim().isEmpty()) return null;
        String like = "%" + q.toLowerCase() + "%";
        return (root, cq, cb) -> cb.or(
                cb.like(cb.lower(root.get("invoiceNumber")), like),
                cb.like(cb.lower(root.get("providerName")), like),
                cb.like(cb.lower(root.get("patientName")), like)
        );
    }

    public static Specification<Invoice> providerName(String p) {
        if (p == null || p.isEmpty()) return null;
        return (root, cq, cb) -> cb.equal(root.get("providerName"), p);
    }

    public static Specification<Invoice> patientName(String p) {
        if (p == null || p.isEmpty()) return null;
        return (root, cq, cb) -> cb.equal(root.get("patientName"), p);
    }

    public static Specification<Invoice> statuses(Set<PaymentStatus> ss) {
        if (ss == null || ss.isEmpty()) return null;
        return (root, cq, cb) -> root.get("paymentStatus").in(ss);
    }

    public static Specification<Invoice> dueBetween(OffsetDateTime start, OffsetDateTime end) {
        if (start == null || end == null) return null;
        return (root, cq, cb) -> cb.between(root.get("dueDate"), start, end);
    }

    public static Specification<Invoice> amountBetween(BigDecimal min, BigDecimal max) {
        if (min == null || max == null) return null;
        return (root, cq, cb) -> cb.between(root.get("amountDue"), min, max);
    }
}
