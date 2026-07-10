package com.careconnect.dto.evv.hhaexchange;

// Tests for HhaExchangeVisit and HhaExchangeVisitRequest.
// Covers the top-level DTO, all 11 nested static classes, and builder patterns.

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import java.util.List;

import static org.junit.jupiter.api.Assertions.*;

@DisplayName("HHAExchange Visit DTOs")
class HhaExchangeVisitTest {

    @Nested
    @DisplayName("HhaExchangeVisitRequest")
    class RequestTests {

        @Test
        @DisplayName("builder sets visits list")
        void builderSetsVisits() {
            var visit = HhaExchangeVisit.builder().providerTaxId("12-3456789").build();
            var req = HhaExchangeVisitRequest.builder()
                    .visits(List.of(visit))
                    .build();
            assertEquals(1, req.getVisits().size());
        }

        @Test
        @DisplayName("no-arg constructor creates null list")
        void noArgConstructor() {
            var req = new HhaExchangeVisitRequest();
            assertNull(req.getVisits());
        }
    }

    @Nested
    @DisplayName("HhaExchangeVisit")
    class VisitTests {

        @Test
        @DisplayName("builder sets all top-level fields")
        void builderSetsAll() {
            var visit = HhaExchangeVisit.builder()
                    .providerTaxId("12-3456789")
                    .payerId("PAYER-001")
                    .externalVisitId("EVV-42")
                    .procedureCode("T1019")
                    .procedureModifierCode(List.of("U1", "HN"))
                    .timezone("America/New_York")
                    .scheduleStartTime("2026-03-17T10:00:00-04:00")
                    .scheduleEndTime("2026-03-17T12:00:00-04:00")
                    .visitStartDateTime("2026-03-17T10:05:00-04:00")
                    .visitEndDateTime("2026-03-17T11:55:00-04:00")
                    .timesheetRequired(true)
                    .timesheetApproved(false)
                    .build();

            assertEquals("12-3456789", visit.getProviderTaxId());
            assertEquals("T1019", visit.getProcedureCode());
            assertEquals(2, visit.getProcedureModifierCode().size());
            assertTrue(visit.getTimesheetRequired());
            assertFalse(visit.getTimesheetApproved());
        }

        @Test
        @DisplayName("no-arg constructor creates null fields")
        void noArgConstructor() {
            var visit = new HhaExchangeVisit();
            assertNull(visit.getProviderTaxId());
            assertNull(visit.getEvv());
        }
    }

    @Nested
    @DisplayName("Office")
    class OfficeTests {
        @Test
        void builderSetsFields() {
            var office = HhaExchangeVisit.Office.builder()
                    .qualifier("NPI")
                    .identifier("1234567890")
                    .build();
            assertEquals("NPI", office.getQualifier());
            assertEquals("1234567890", office.getIdentifier());
        }
    }

    @Nested
    @DisplayName("Member")
    class MemberTests {
        @Test
        void builderSetsFields() {
            var member = HhaExchangeVisit.Member.builder()
                    .qualifier("MA")
                    .identifier("MA-99999")
                    .admissionID("ADM-001")
                    .build();
            assertEquals("MA", member.getQualifier());
            assertEquals("ADM-001", member.getAdmissionID());
        }
    }

    @Nested
    @DisplayName("Caregiver")
    class CaregiverTests {
        @Test
        void builderSetsFields() {
            var cg = HhaExchangeVisit.Caregiver.builder()
                    .qualifier("SSN")
                    .identifier("***-**-1234")
                    .build();
            assertEquals("SSN", cg.getQualifier());
        }
    }

    @Nested
    @DisplayName("EvvData")
    class EvvDataTests {
        @Test
        void builderSetsClockEvents() {
            var clockIn = HhaExchangeVisit.ClockEvent.builder()
                    .callDateTime("2026-03-17T10:00:00")
                    .callType("GPS")
                    .callLatitude(38.9)
                    .callLongitude(-77.0)
                    .build();
            var clockOut = HhaExchangeVisit.ClockEvent.builder()
                    .callDateTime("2026-03-17T12:00:00")
                    .callType("TELEPHONY")
                    .build();
            var evv = HhaExchangeVisit.EvvData.builder()
                    .clockIn(clockIn)
                    .clockOut(clockOut)
                    .build();
            assertNotNull(evv.getClockIn());
            assertNotNull(evv.getClockOut());
            assertEquals(38.9, evv.getClockIn().getCallLatitude());
        }
    }

    @Nested
    @DisplayName("ClockEvent")
    class ClockEventTests {
        @Test
        void builderSetsAllFields() {
            var addr = HhaExchangeVisit.ServiceAddress.builder()
                    .addressLine1("123 Main St")
                    .city("Arlington")
                    .state("VA")
                    .zipcode("22201")
                    .build();
            var event = HhaExchangeVisit.ClockEvent.builder()
                    .callDateTime("2026-03-17T10:00:00")
                    .callType("GPS")
                    .callLatitude(38.88)
                    .callLongitude(-77.07)
                    .originatingPhoneNumber("555-555-1234")
                    .locationType("HOME")
                    .serviceAddress(addr)
                    .performedTasks(List.of(
                        HhaExchangeVisit.TaskCode.builder().code("BATH").build()))
                    .refusedTasks(List.of())
                    .build();

            assertEquals("GPS", event.getCallType());
            assertEquals("555-555-1234", event.getOriginatingPhoneNumber());
            assertNotNull(event.getServiceAddress());
            assertEquals("Arlington", event.getServiceAddress().getCity());
            assertEquals(1, event.getPerformedTasks().size());
            assertEquals("BATH", event.getPerformedTasks().get(0).getCode());
            assertTrue(event.getRefusedTasks().isEmpty());
        }
    }

    @Nested
    @DisplayName("ServiceAddress")
    class ServiceAddressTests {
        @Test
        void builderSetsAllFields() {
            var addr = HhaExchangeVisit.ServiceAddress.builder()
                    .addressLine1("456 Oak Ave")
                    .addressLine2("Suite 200")
                    .city("Richmond")
                    .state("VA")
                    .zipcode("23220")
                    .build();
            assertEquals("456 Oak Ave", addr.getAddressLine1());
            assertEquals("Suite 200", addr.getAddressLine2());
            assertEquals("23220", addr.getZipcode());
        }
    }

    @Nested
    @DisplayName("MissedVisit")
    class MissedVisitTests {
        @Test
        void builderSetsFields() {
            var missed = HhaExchangeVisit.MissedVisit.builder()
                    .missed(true)
                    .reasonCode("NO_SHOW")
                    .actionCode("RESCHEDULED")
                    .notes("Patient not home")
                    .build();
            assertTrue(missed.getMissed());
            assertEquals("NO_SHOW", missed.getReasonCode());
            assertEquals("Patient not home", missed.getNotes());
        }
    }

    @Nested
    @DisplayName("EditVisit")
    class EditVisitTests {
        @Test
        void builderSetsFields() {
            var edit = HhaExchangeVisit.EditVisit.builder()
                    .edited(true)
                    .reasonCode("TIME_CORRECTION")
                    .notes("Adjusted clock-out time")
                    .build();
            assertTrue(edit.getEdited());
            assertEquals("TIME_CORRECTION", edit.getReasonCode());
        }
    }

    @Nested
    @DisplayName("Billing")
    class BillingTests {
        @Test
        void builderSetsFields() {
            var billing = HhaExchangeVisit.Billing.builder()
                    .externalInvoiceNumber("INV-2026-001")
                    .totalBilledAmount(199.99)
                    .totalUnitsBilled(4)
                    .contractRate(50.0)
                    .diagnosisCodes(List.of("Z00.00", "I10"))
                    .build();
            assertEquals("INV-2026-001", billing.getExternalInvoiceNumber());
            assertEquals(199.99, billing.getTotalBilledAmount());
            assertEquals(4, billing.getTotalUnitsBilled());
            assertEquals(2, billing.getDiagnosisCodes().size());
        }
    }

    @Nested
    @DisplayName("SecondaryPayer")
    class SecondaryPayerTests {
        @Test
        void builderSetsFields() {
            var payer = HhaExchangeVisit.SecondaryPayer.builder()
                    .enableSecondaryBilling(true)
                    .primaryPayerId("PAYER-002")
                    .primaryPayerName("Medicare")
                    .totalPaidAmount(150.0)
                    .deductible(25.0)
                    .copay(10.0)
                    .build();
            assertTrue(payer.getEnableSecondaryBilling());
            assertEquals("Medicare", payer.getPrimaryPayerName());
            assertEquals(150.0, payer.getTotalPaidAmount());
            assertEquals(25.0, payer.getDeductible());
        }
    }

    @Nested
    @DisplayName("ShiftSignOff")
    class ShiftSignOffTests {
        @Test
        void builderSetsFields() {
            var signOff = HhaExchangeVisit.ShiftSignOff.builder()
                    .employerInternalNumber("EMP-42")
                    .employerName("CareConnect Health LLC")
                    .build();
            assertEquals("EMP-42", signOff.getEmployerInternalNumber());
            assertEquals("CareConnect Health LLC", signOff.getEmployerName());
        }
    }
}
