package com.careconnect.spec;

import com.careconnect.model.invoice.Invoice;
import com.careconnect.model.invoice.PaymentStatus;
import jakarta.persistence.criteria.CriteriaBuilder;
import jakarta.persistence.criteria.CriteriaQuery;
import jakarta.persistence.criteria.Expression;
import jakarta.persistence.criteria.Path;
import jakarta.persistence.criteria.Predicate;
import jakarta.persistence.criteria.Root;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.data.jpa.domain.Specification;

import java.lang.reflect.Constructor;
import java.math.BigDecimal;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.EnumSet;
import java.util.Set;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@SuppressWarnings({"unchecked", "rawtypes"})
@ExtendWith(MockitoExtension.class)
class InvoiceSpecsTest {

    @Mock
    Root<Invoice> root;
    @Mock
    CriteriaQuery<?> cq;
    @Mock
    CriteriaBuilder cb;
    @Mock
    Path path;
    @Mock
    Expression expr;
    @Mock
    Predicate predicate;

    // ─── Private constructor ──────────────────────────────────────────────────

    @Test
    void privateConstructor_isInstantiableViaReflection() throws Exception {
        final Constructor<InvoiceSpecs> ctor = InvoiceSpecs.class.getDeclaredConstructor();
        ctor.setAccessible(true);
        assertThat(ctor.newInstance()).isNotNull();
    }

    // ─── search() ────────────────────────────────────────────────────────────

    @Test
    void search_null_returnsNull() throws Exception {
        assertThat(InvoiceSpecs.search(null)).isNull();
    }

    @Test
    void search_empty_returnsNull() throws Exception {
        assertThat(InvoiceSpecs.search("")).isNull();
    }

    @Test
    void search_blank_returnsNull() throws Exception {
        assertThat(InvoiceSpecs.search("   ")).isNull();
    }

    @Test
    void search_validQuery_buildsOrPredicateWithThreeLikes() throws Exception {
        final String q = "John";
        final String like = "%" + q.toLowerCase() + "%";

        when(root.get("invoiceNumber")).thenReturn(path);
        when(root.get("providerName")).thenReturn(path);
        when(root.get("patientName")).thenReturn(path);
        when(cb.lower(path)).thenReturn(expr);
        when(cb.like(expr, like)).thenReturn(predicate);
        when(cb.or(predicate, predicate, predicate)).thenReturn(predicate);

        final Specification<Invoice> spec = InvoiceSpecs.search(q);

        assertThat(spec).isNotNull();
        assertThat(spec.toPredicate(root, cq, cb)).isEqualTo(predicate);
        verify(cb).or(predicate, predicate, predicate);
    }

    // ─── providerName() ──────────────────────────────────────────────────────

    @Test
    void providerName_null_returnsNull() throws Exception {
        assertThat(InvoiceSpecs.providerName(null)).isNull();
    }

    @Test
    void providerName_empty_returnsNull() throws Exception {
        assertThat(InvoiceSpecs.providerName("")).isNull();
    }

    @Test
    void providerName_valid_buildsEqualPredicate() throws Exception {
        final String p = "Dr. Smith";

        when(root.get("providerName")).thenReturn(path);
        when(cb.equal(path, p)).thenReturn(predicate);

        final Specification<Invoice> spec = InvoiceSpecs.providerName(p);

        assertThat(spec).isNotNull();
        assertThat(spec.toPredicate(root, cq, cb)).isEqualTo(predicate);
        verify(cb).equal(path, p);
    }

    // ─── patientName() ───────────────────────────────────────────────────────

    @Test
    void patientName_null_returnsNull() throws Exception {
        assertThat(InvoiceSpecs.patientName(null)).isNull();
    }

    @Test
    void patientName_empty_returnsNull() throws Exception {
        assertThat(InvoiceSpecs.patientName("")).isNull();
    }

    @Test
    void patientName_valid_buildsEqualPredicate() throws Exception {
        final String p = "Jane Doe";

        when(root.get("patientName")).thenReturn(path);
        when(cb.equal(path, p)).thenReturn(predicate);

        final Specification<Invoice> spec = InvoiceSpecs.patientName(p);

        assertThat(spec).isNotNull();
        assertThat(spec.toPredicate(root, cq, cb)).isEqualTo(predicate);
        verify(cb).equal(path, p);
    }

    // ─── statuses() ──────────────────────────────────────────────────────────

    @Test
    void statuses_null_returnsNull() throws Exception {
        assertThat(InvoiceSpecs.statuses(null)).isNull();
    }

    @Test
    void statuses_emptySet_returnsNull() throws Exception {
        assertThat(InvoiceSpecs.statuses(Set.of())).isNull();
    }

    @Test
    void statuses_nonEmpty_buildsInPredicate() throws Exception {
        final Set<PaymentStatus> ss = EnumSet.of(PaymentStatus.PENDING, PaymentStatus.OVERDUE);

        when(root.get("paymentStatus")).thenReturn(path);
        when(path.in(ss)).thenReturn(predicate);

        final Specification<Invoice> spec = InvoiceSpecs.statuses(ss);

        assertThat(spec).isNotNull();
        assertThat(spec.toPredicate(root, cq, cb)).isEqualTo(predicate);
        verify(path).in(ss);
    }

    // ─── dueBetween() ────────────────────────────────────────────────────────

    @Test
    void dueBetween_nullStart_returnsNull() throws Exception {
        assertThat(InvoiceSpecs.dueBetween(null, OffsetDateTime.now())).isNull();
    }

    @Test
    void dueBetween_nullEnd_returnsNull() throws Exception {
        assertThat(InvoiceSpecs.dueBetween(OffsetDateTime.now(), null)).isNull();
    }

    @Test
    void dueBetween_bothValid_buildsBetweenPredicate() throws Exception {
        final OffsetDateTime start = OffsetDateTime.of(2024, 1, 1, 0, 0, 0, 0, ZoneOffset.UTC);
        final OffsetDateTime end = OffsetDateTime.of(2024, 12, 31, 23, 59, 59, 0, ZoneOffset.UTC);

        when(root.get("dueDate")).thenReturn(path);
        when(cb.between(path, start, end)).thenReturn(predicate);

        final Specification<Invoice> spec = InvoiceSpecs.dueBetween(start, end);

        assertThat(spec).isNotNull();
        assertThat(spec.toPredicate(root, cq, cb)).isEqualTo(predicate);
        verify(cb).between(path, start, end);
    }

    // ─── amountBetween() ─────────────────────────────────────────────────────

    @Test
    void amountBetween_nullMin_returnsNull() throws Exception {
        assertThat(InvoiceSpecs.amountBetween(null, BigDecimal.TEN)).isNull();
    }

    @Test
    void amountBetween_nullMax_returnsNull() throws Exception {
        assertThat(InvoiceSpecs.amountBetween(BigDecimal.ONE, null)).isNull();
    }

    @Test
    void amountBetween_bothValid_buildsBetweenPredicate() throws Exception {
        final BigDecimal min = BigDecimal.valueOf(10);
        final BigDecimal max = BigDecimal.valueOf(500);

        when(root.get("amountDue")).thenReturn(path);
        when(cb.between(path, min, max)).thenReturn(predicate);

        final Specification<Invoice> spec = InvoiceSpecs.amountBetween(min, max);

        assertThat(spec).isNotNull();
        assertThat(spec.toPredicate(root, cq, cb)).isEqualTo(predicate);
        verify(cb).between(path, min, max);
    }
}
