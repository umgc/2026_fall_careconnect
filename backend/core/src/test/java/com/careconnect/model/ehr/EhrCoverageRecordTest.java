package com.careconnect.model.ehr;

import ca.uhn.fhir.context.FhirContext;
import ca.uhn.fhir.parser.IParser;
import org.hl7.fhir.r4.model.Bundle;
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

    private static final String BASE = "https://sandbox.bluebutton.cms.gov/v3/fhir/";

    private static Coverage coverage() {
        final Coverage c = new Coverage();
        c.setId("part-a--1");
        c.getMeta().setLastUpdated(new Date());
        return c;
    }

    @Test
    @DisplayName("TC-MCR-CACHE-014: open coverage (no period end, the usual case for active Medicare) has no expiry and does not throw")
    void openCoverageHasNoExpiry() {
        final Coverage c = coverage();
        c.setPeriod(new Period().setStartElement(new DateTimeType("2015-01-01")));

        final EhrCoverageRecord record = new EhrCoverageRecord(2L, c, 9L);

        assertThat(record.getExpiresOn()).isNull();
        assertThat(record.getStatus()).isNull();
        assertThat(record.getExternalCoverageId()).isEqualTo("part-a--1");
    }

    @Test
    @DisplayName("TC-MCR-CACHE-015: a period end is read as the calendar date written (it used to throw DateTimeException)")
    void periodEndIsReadAsCalendarDate() {
        final Coverage c = coverage();
        c.setPeriod(new Period().setEndElement(new DateTimeType("2027-12-31")));

        assertThat(new EhrCoverageRecord(2L, c, 9L).getExpiresOn()).isEqualTo(LocalDate.of(2027, 12, 31));
    }

    @Test
    @DisplayName("TC-MCR-CACHE-016: an EOB without created or status still maps")
    void sparseEobMaps() {
        final ExplanationOfBenefit eob = new ExplanationOfBenefit();
        eob.setId("carrier--1");
        eob.getMeta().setLastUpdated(new Date());

        final EhrVisitRecord visit = new EhrVisitRecord(2L, eob, 9L);

        assertThat(visit.getServiceDate()).isNull();
        assertThat(visit.getStatus()).isNull();
        assertThat(visit.getExternalVisitId()).isEqualTo("carrier--1");
    }

    @Test
    @DisplayName("TC-MCR-CACHE-025: coverage and visit rows built from Bundle entries keep the id part, not the full URL and version")
    void bundleEntriesKeepTheIdPart() {
        // Testing Lead, 2026-10-06: 014 and 016 set a bare id, so they pass with getId() too.
        final Coverage c = coverage();
        c.getMeta().setVersionId("7");
        final ExplanationOfBenefit eob = new ExplanationOfBenefit();
        eob.setId("carrier--1");
        eob.getMeta().setLastUpdated(new Date()).setVersionId("7");
        final Bundle bundle = new Bundle().setType(Bundle.BundleType.SEARCHSET);
        bundle.addEntry().setFullUrl(BASE + "Coverage/part-a--1").setResource(c);
        bundle.addEntry().setFullUrl(BASE + "ExplanationOfBenefit/carrier--1").setResource(eob);
        final IParser parser = FhirContext.forR4().newJsonParser();
        final Bundle parsed = parser.parseResource(Bundle.class, parser.encodeResourceToString(bundle));
        final Coverage readCoverage = (Coverage) parsed.getEntry().get(0).getResource();
        final ExplanationOfBenefit readEob = (ExplanationOfBenefit) parsed.getEntry().get(1).getResource();
        assertThat(readCoverage.getId()).startsWith(BASE).contains("_history/7");

        assertThat(new EhrCoverageRecord(2L, readCoverage, 9L).getExternalCoverageId()).isEqualTo("part-a--1");
        assertThat(new EhrVisitRecord(2L, readEob, 9L).getExternalVisitId()).isEqualTo("carrier--1");
    }
}
