package com.careconnect.model.invoice;

import org.junit.jupiter.api.Test;

import java.time.LocalDate;

import static org.assertj.core.api.Assertions.assertThat;

class InvoiceDatesTest {

    // ─── Builder ──────────────────────────────────────────────────────────────

    @Test
    void builder_allFields_setsCorrectly() throws Exception {
        final LocalDate statement = LocalDate.of(2025, 1, 1);
        final LocalDate due = LocalDate.of(2025, 1, 31);
        final LocalDate paid = LocalDate.of(2025, 1, 20);

        final InvoiceDates dates = InvoiceDates.builder()
                .statementDate(statement)
                .dueDate(due)
                .paidDate(paid)
                .build();

        assertThat(dates.getStatementDate()).isEqualTo(statement);
        assertThat(dates.getDueDate()).isEqualTo(due);
        assertThat(dates.getPaidDate()).isEqualTo(paid);
    }

    @Test
    void builder_defaults_nullFields() throws Exception {
        final InvoiceDates dates = InvoiceDates.builder().build();

        assertThat(dates.getStatementDate()).isNull();
        assertThat(dates.getDueDate()).isNull();
        assertThat(dates.getPaidDate()).isNull();
    }

    // ─── Setters ──────────────────────────────────────────────────────────────

    @Test
    void setters_updateFields() throws Exception {
        final InvoiceDates dates = InvoiceDates.builder().build();

        final LocalDate statement = LocalDate.of(2025, 6, 1);
        final LocalDate due = LocalDate.of(2025, 6, 30);

        dates.setStatementDate(statement);
        dates.setDueDate(due);
        dates.setPaidDate(null);

        assertThat(dates.getStatementDate()).isEqualTo(statement);
        assertThat(dates.getDueDate()).isEqualTo(due);
        assertThat(dates.getPaidDate()).isNull();
    }

    // ─── equals() and hashCode() ──────────────────────────────────────────────

    @Test
    void equals_sameFields_returnsTrue() throws Exception {
        final LocalDate date = LocalDate.of(2025, 3, 15);
        final InvoiceDates d1 = InvoiceDates.builder().statementDate(date).build();
        final InvoiceDates d2 = InvoiceDates.builder().statementDate(date).build();

        assertThat(d1).isEqualTo(d2);
        assertThat(d1.hashCode()).isEqualTo(d2.hashCode());
    }

    @Test
    void equals_differentFields_returnsFalse() throws Exception {
        final InvoiceDates d1 = InvoiceDates.builder().statementDate(LocalDate.of(2025, 1, 1)).build();
        final InvoiceDates d2 = InvoiceDates.builder().statementDate(LocalDate.of(2025, 12, 31)).build();

        assertThat(d1).isNotEqualTo(d2);
    }
}
