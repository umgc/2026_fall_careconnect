package com.careconnect.model.ehr;

import org.hl7.fhir.r4.model.Coverage;
import org.hl7.fhir.r4.model.DateTimeType;
import org.hl7.fhir.r4.model.ExplanationOfBenefit;
import org.hl7.fhir.r4.model.Period;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.time.LocalDate;
import java.util.Date;

import static org.assertj.core.api.Assertions.assertThat;

/** Building coverage and visit rows from Blue Button resources, including sparse ones. */
class EhrCoverageRecordTest {

    private static Coverage coverage() {
        final Coverage c = new Coverage();
        c.setId("part-a--1");
        c.getMeta().setLastUpdated(new Date());
        return c;
    }

    @Test
    @DisplayName("open coverage (no period end, the usual case for active Medicare) has no expiry and does not throw")
    void openCoverageHasNoExpiry() {
        final Coverage c = coverage();
        c.setPeriod(new Period().setStartElement(new DateTimeType("2015-01-01")));

        final EhrCoverageRecord record = new EhrCoverageRecord(2L, c, 9L);

        assertThat(record.getExpiresOn()).isNull();
        assertThat(record.getStatus()).isNull();
        assertThat(record.getExternalCoverageId()).isEqualTo("part-a--1");
    }

    @Test
    @DisplayName("a period end is read as the calendar date written (it used to throw DateTimeException)")
    void periodEndIsReadAsCalendarDate() {
        final Coverage c = coverage();
        c.setPeriod(new Period().setEndElement(new DateTimeType("2027-12-31")));

        assertThat(new EhrCoverageRecord(2L, c, 9L).getExpiresOn()).isEqualTo(LocalDate.of(2027, 12, 31));
    }

    @Test
    @DisplayName("an EOB without created or status still maps")
    void sparseEobMaps() {
        final ExplanationOfBenefit eob = new ExplanationOfBenefit();
        eob.setId("carrier--1");
        eob.getMeta().setLastUpdated(new Date());

        final EhrVisitRecord visit = new EhrVisitRecord(2L, eob, 9L);

        assertThat(visit.getServiceDate()).isNull();
        assertThat(visit.getStatus()).isNull();
        assertThat(visit.getExternalVisitId()).isEqualTo("carrier--1");
    }
}
