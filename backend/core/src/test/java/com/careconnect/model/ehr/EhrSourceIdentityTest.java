package com.careconnect.model.ehr;

import org.hl7.fhir.r4.model.Address;
import org.hl7.fhir.r4.model.ContactPoint;
import org.hl7.fhir.r4.model.DateType;
import org.hl7.fhir.r4.model.Patient;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.time.LocalDate;
import java.util.Date;

import static org.assertj.core.api.Assertions.assertThat;

/** Building the identity snapshot from a Blue Button {@code Patient}, including sparse ones. */
class EhrSourceIdentityTest {

    private static Patient patient() {
        final Patient p = new Patient();
        p.getMeta().setLastUpdated(new Date());
        return p;
    }

    @Test
    @DisplayName("the birth date is read as a calendar date (it used to throw DateTimeException for every patient)")
    void birthDateIsReadAsCalendarDate() {
        final Patient p = patient();
        p.setBirthDateElement(new DateType("1950-03-09"));

        assertThat(new EhrSourceIdentity(2L, p, 9L).getDateOfBirth()).isEqualTo(LocalDate.of(1950, 3, 9));
    }

    @Test
    @DisplayName("a partial or missing birth date is null, not a guessed day")
    void partialOrMissingBirthDateIsNull() {
        final Patient yearOnly = patient();
        yearOnly.setBirthDateElement(new DateType("1950"));

        assertThat(new EhrSourceIdentity(2L, yearOnly, 9L).getDateOfBirth()).isNull();
        assertThat(new EhrSourceIdentity(2L, patient(), 9L).getDateOfBirth()).isNull();
    }

    @Test
    @DisplayName("a one-line address, no gender and a contact point without a system do not throw")
    void sparsePatientDoesNotThrow() {
        final Patient p = patient();
        p.addAddress(new Address().addLine("1 Main St").setCity("Baltimore"));
        p.addTelecom(new ContactPoint().setValue("no system"));
        p.addTelecom(new ContactPoint().setSystem(ContactPoint.ContactPointSystem.PHONE).setValue("555-0102"));

        final EhrSourceIdentity identity = new EhrSourceIdentity(2L, p, 9L);

        assertThat(identity.getAddressLine1()).isEqualTo("1 Main St");
        assertThat(identity.getAddressLine2()).isNull();
        assertThat(identity.getGender()).isNull();
        assertThat(identity.getPhone()).isEqualTo("555-0102");
    }
}
