package com.careconnect.model.invoice;

import lombok.Builder;
import lombok.Data;

import java.time.LocalDate;

@Data
@Builder
public class InvoiceDates {
    private LocalDate statementDate;
    private LocalDate dueDate;
    private LocalDate paidDate;
}