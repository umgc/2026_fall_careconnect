package com.careconnect.service.invoice;

import com.careconnect.dto.invoice.PaymentDto;
import com.careconnect.mapper.InvoiceMapper;
import com.careconnect.dto.invoice.InvoiceDto;
import com.careconnect.model.invoice.Invoice;
import com.careconnect.model.invoice.InvoicePayment;
import com.careconnect.model.invoice.PaymentStatus;
import com.careconnect.repository.InvoicePaymentRepository;
import com.careconnect.repository.InvoiceRepository;
import com.careconnect.spec.InvoiceSpecs;
import org.springframework.data.domain.*;
import org.springframework.data.jpa.domain.Specification;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.*;
import java.util.stream.Collectors;

@Service
public class InvoiceService {

    private final InvoiceRepository repo;
    private final InvoicePaymentRepository paymentRepo;

    public InvoiceService(InvoiceRepository repo, InvoicePaymentRepository paymentRepo) {
        this.repo = repo;
        this.paymentRepo = paymentRepo;
    }

    public static Sort resolveSort(String sort) {
        if (sort == null || sort.isBlank()) {
            return Sort.by(Sort.Direction.DESC, "statementDate");
        }
        switch (sort) {
            case "due_desc":
                return Sort.by(Sort.Direction.DESC, "dueDate");
            case "due_asc":
                return Sort.by(Sort.Direction.ASC, "dueDate");
            case "amount_desc":
                return Sort.by(Sort.Direction.DESC, "amountDue");
            case "amount_asc":
                return Sort.by(Sort.Direction.ASC, "amountDue");
            default:
                return Sort.by(Sort.Direction.DESC, "statementDate");
        }
    }

    public static Set<PaymentStatus> parseStatuses(String csv) {
        if (csv == null || csv.isBlank()) return Collections.emptySet();
        return Arrays.stream(csv.split(","))
                .map(String::trim)
                .filter(s -> !s.isEmpty())
                .map(s -> {
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
                })
                .collect(Collectors.toSet());
    }

    private static BigDecimal nvl(BigDecimal v, BigDecimal def) {
        return v == null ? def : v;
    }

    @Transactional
    public InvoiceDto create(InvoiceDto dto) {
        if (dto.id == null || dto.id.isBlank()) {
            dto.id = UUID.randomUUID().toString();
        }
        OffsetDateTime now = OffsetDateTime.now(ZoneOffset.UTC);
        // set audit fields
        String user = currentUser();
        dto.createdBy = user;
        dto.updatedBy = user;

        Invoice entity = InvoiceMapper.toEntity(dto);
        entity.setCreatedAt(now);
        entity.setUpdatedAt(now);
        Invoice saved = repo.save(entity);
        return InvoiceMapper.toDto(saved);
    }

    @Transactional
    public InvoiceDto update(String id, InvoiceDto dto) {
        Invoice existing = repo.findById(id)
                .orElseThrow(() -> new NoSuchElementException("Invoice not found"));

        dto.id = id;

        // preserve createdBy, update updatedBy
        dto.createdBy = existing.getCreatedBy();
        dto.updatedBy = currentUser();

        Invoice rebuilt = InvoiceMapper.toEntity(dto);
        rebuilt.setCreatedAt(existing.getCreatedAt());
        rebuilt.setUpdatedAt(java.time.OffsetDateTime.now(java.time.ZoneOffset.UTC));
        Invoice saved = repo.save(rebuilt);
        return InvoiceMapper.toDto(saved);
    }

    @Transactional
    public void delete(String id) {
        repo.deleteById(id);
    }

    @Transactional(readOnly = true)
    public Optional<InvoiceDto> get(String id) {
        return repo.findById(id).map(inv -> {
            inv.getServices().size();
            inv.getHistory().size();
            inv.getRecommendedActions().size();
            return InvoiceMapper.toDto(inv);
        });
    }

    @Transactional(readOnly = true)
    public Page<InvoiceDto> list(
            String search,
            Set<PaymentStatus> statuses,
            String providerName,
            String patientName,
            OffsetDateTime dueStart,
            OffsetDateTime dueEnd,
            BigDecimal amountMin,
            BigDecimal amountMax,
            Pageable pageable
    ) {
        Specification<Invoice> spec = Specification.where(InvoiceSpecs.search(search))
                .and(InvoiceSpecs.statuses(statuses))
                .and(InvoiceSpecs.providerName(providerName))
                .and(InvoiceSpecs.patientName(patientName))
                .and(InvoiceSpecs.dueBetween(dueStart, dueEnd))
                .and(InvoiceSpecs.amountBetween(amountMin, amountMax));

        Page<Invoice> page = repo.findAll(spec, pageable);

        page.getContent().forEach(inv -> {
            inv.getServices().size();
            inv.getHistory().size();
            inv.getRecommendedActions().size();
        });

        return page.map(InvoiceMapper::toDto);
    }

    private String currentUser() {
        Authentication auth = SecurityContextHolder.getContext().getAuthentication();
        if (auth == null || !auth.isAuthenticated()) return "system";
        return auth.getName() == null ? "system" : auth.getName();
    }

    @Transactional
    public InvoiceDto recordPayment(String invoiceId, PaymentDto pdto, String actor) {
        Invoice invoice = repo.findById(invoiceId)
                .orElseThrow(() -> new NoSuchElementException("Invoice not found"));

        // Build and attach payment
        InvoicePayment p = InvoiceMapper.toEntity(invoice, pdto);
        if (p.getCreatedBy() == null || p.getCreatedBy().isBlank()) {
            p.setCreatedBy(actor);
        }
        invoice.addPayment(p);

        // Recalculate due and status
        BigDecimal total = nvl(invoice.getTotal(), BigDecimal.ZERO);
        BigDecimal paidSum = invoice.getPayments().stream()
                .map(InvoicePayment::getAmountPaid)
                .filter(Objects::nonNull)
                .reduce(BigDecimal.ZERO, BigDecimal::add);

        BigDecimal due = total.subtract(paidSum);
        if (due.signum() < 0) due = BigDecimal.ZERO;

        invoice.setAmountDue(due);
        invoice.setUpdatedAt(OffsetDateTime.now());

        if (due.signum() == 0) {
            invoice.setPaymentStatus(PaymentStatus.PAID);
            invoice.setPaidDate(p.getPaymentDate());
        } else if (paidSum.signum() > 0) {
            invoice.setPaymentStatus(PaymentStatus.PARTIAL_PAYMENT);
        }

        // Persist
        // Cascade on payments means repo.save(invoice) is enough
        Invoice saved = repo.save(invoice);
        return InvoiceMapper.toDto(saved);
    }

    @Transactional
    public InvoiceDto deletePayment(String invoiceId, String paymentId) {
        Invoice invoice = repo.findById(invoiceId)
                .orElseThrow(() -> new NoSuchElementException("Invoice not found"));

        Optional<InvoicePayment> found = invoice.getPayments().stream()
                .filter(p -> p.getId().equals(paymentId))
                .findFirst();

        if (found.isEmpty()) {
            throw new NoSuchElementException("Payment not found");
        }

        invoice.removePaymentById(paymentId);

        // Recompute amounts and status
        BigDecimal total = nvl(invoice.getTotal(), BigDecimal.ZERO);
        BigDecimal paidSum = invoice.getPayments().stream()
                .map(InvoicePayment::getAmountPaid)
                .filter(Objects::nonNull)
                .reduce(BigDecimal.ZERO, BigDecimal::add);

        BigDecimal due = total.subtract(paidSum);
        if (due.signum() < 0) due = BigDecimal.ZERO;

        invoice.setAmountDue(due);
        invoice.setUpdatedAt(OffsetDateTime.now());
        if (due.signum() == 0 && paidSum.signum() > 0) {
            invoice.setPaymentStatus(PaymentStatus.PAID);
            // set paidDate to latest payment date
            OffsetDateTime maxDate = invoice.getPayments().stream()
                    .map(InvoicePayment::getPaymentDate)
                    .filter(Objects::nonNull)
                    .max(OffsetDateTime::compareTo)
                    .orElse(null);
            invoice.setPaidDate(maxDate);
        } else if (paidSum.signum() > 0) {
            invoice.setPaymentStatus(PaymentStatus.PARTIAL_PAYMENT);
            invoice.setPaidDate(null);
        } else {
            invoice.setPaymentStatus(PaymentStatus.PENDING);
            invoice.setPaidDate(null);
        }

        Invoice saved = repo.save(invoice);
        return InvoiceMapper.toDto(saved);
    }

    public Optional<Invoice> findDuplicateByProviderAndTotal(String providerName, Double total, String invoiceNumber) {
        if (providerName == null || providerName.isBlank() || total == null) {
            return Optional.empty();
        }

        BigDecimal center = BigDecimal.valueOf(total).setScale(2, RoundingMode.HALF_UP);

        // Prefer strict match when invoiceNumber is present
        if (invoiceNumber != null && !invoiceNumber.isBlank()) {
            return repo.findTopByProviderNameIgnoreCaseAndTotalAndInvoiceNumberOrderByCreatedAtDesc(
                    providerName, center, invoiceNumber
            );
        }

        // Otherwise use a tiny window to tolerate rounding
        BigDecimal min = center.subtract(new BigDecimal("0.01"));
        BigDecimal max = center.add(new BigDecimal("0.01"));
        return repo.findTopByProviderNameIgnoreCaseAndTotalBetweenOrderByCreatedAtDesc(
                providerName, min, max
        );
    }
}
