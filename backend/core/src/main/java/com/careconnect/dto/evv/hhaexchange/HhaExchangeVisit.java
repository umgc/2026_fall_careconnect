package com.careconnect.dto.evv.hhaexchange;

import com.fasterxml.jackson.annotation.JsonInclude;
import lombok.*;

import java.util.List;

/**
 * Represents a single visit payload for the HHAExchange POST /api/v2/visits endpoint.
 * All nested static classes mirror the exact JSON structure required by the aggregator.
 */
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
@JsonInclude(JsonInclude.Include.NON_NULL)
public class HhaExchangeVisit {

    private String providerTaxId;
    private Office office;
    private Member member;
    private Caregiver caregiver;
    private String residingCaregiver;
    private String payerId;
    private String externalVisitId;
    private String evvmsid;
    private String procedureCode;
    private List<String> procedureModifierCode;
    private String timezone;
    private String scheduleStartTime;
    private String scheduleEndTime;
    private String visitStartDateTime;
    private String visitEndDateTime;
    private Boolean timesheetRequired;
    private Boolean timesheetApproved;
    private EvvData evv;
    private MissedVisit missedVisit;
    private EditVisit editVisit;
    private Billing billing;
    private List<SecondaryPayer> billSecondaryPayer;
    private ShiftSignOff shiftSignOff;

    // -------------------------------------------------------------------------
    // Nested types
    // -------------------------------------------------------------------------

    @Getter
    @Setter
    @NoArgsConstructor
    @AllArgsConstructor
    @Builder
    public static class Office {
        private String qualifier;
        private String identifier;
    }

    @Getter
    @Setter
    @NoArgsConstructor
    @AllArgsConstructor
    @Builder
    public static class Member {
        private String qualifier;
        private String identifier;
        private String admissionID;
    }

    @Getter
    @Setter
    @NoArgsConstructor
    @AllArgsConstructor
    @Builder
    public static class Caregiver {
        private String qualifier;
        private String identifier;
    }

    @Getter
    @Setter
    @NoArgsConstructor
    @AllArgsConstructor
    @Builder
    public static class EvvData {
        private ClockEvent clockIn;
        private ClockEvent clockOut;
    }

    @Getter
    @Setter
    @NoArgsConstructor
    @AllArgsConstructor
    @Builder
    @JsonInclude(JsonInclude.Include.NON_NULL)
    public static class ClockEvent {
        private String callDateTime;
        private String callType;
        private Double callLatitude;
        private Double callLongitude;
        private String originatingPhoneNumber;
        private String locationType;
        private ServiceAddress serviceAddress;
        /**
         * Populated only for clockOut events when tasks were completed.
         */
        private List<TaskCode> performedTasks;
        /**
         * Populated only for clockOut events when tasks were refused.
         */
        private List<TaskCode> refusedTasks;
    }

    @Getter
    @Setter
    @NoArgsConstructor
    @AllArgsConstructor
    @Builder
    public static class ServiceAddress {
        private String addressLine1;
        private String addressLine2;
        private String city;
        private String state;
        private String zipcode;
    }

    @Getter
    @Setter
    @NoArgsConstructor
    @AllArgsConstructor
    @Builder
    public static class TaskCode {
        private String code;
    }

    @Getter
    @Setter
    @NoArgsConstructor
    @AllArgsConstructor
    @Builder
    public static class MissedVisit {
        private Boolean missed;
        private String reasonCode;
        private String actionCode;
        private String notes;
    }

    @Getter
    @Setter
    @NoArgsConstructor
    @AllArgsConstructor
    @Builder
    public static class EditVisit {
        private Boolean edited;
        private String reasonCode;
        private String actionCode;
        private String notes;
    }

    @Getter
    @Setter
    @NoArgsConstructor
    @AllArgsConstructor
    @Builder
    @JsonInclude(JsonInclude.Include.NON_NULL)
    public static class Billing {
        private String externalInvoiceNumber;
        private Double totalBilledAmount;
        private Integer totalUnitsBilled;
        private Double contractRate;
        private List<String> diagnosisCodes;
    }

    @Getter
    @Setter
    @NoArgsConstructor
    @AllArgsConstructor
    @Builder
    @JsonInclude(JsonInclude.Include.NON_NULL)
    public static class SecondaryPayer {
        private Boolean enableSecondaryBilling;
        private String otherSubscriberId;
        private String primaryPayerId;
        private String primaryPayerName;
        private String relationshipToInsured;
        private String primaryPayerPolicyOrGroupNumber;
        private String primaryPayerProgramName;
        private String planType;
        private Double totalPaidAmount;
        private String paidDate;
        private Double deductible;
        private Double coinsurance;
        private Double copay;
        private Double contractedAdjustments;
        private Double notMedicallyNecessary;
        private Double nonCoveredCharges;
        private Double maxBenefitExhausted;
        private Integer payerResponsibilitySequence;
        private String claimFilingCode;
        private Double otherPayerPaidAmount;
    }

    @Getter
    @Setter
    @NoArgsConstructor
    @AllArgsConstructor
    @Builder
    public static class ShiftSignOff {
        private String employerInternalNumber;
        private String employerName;
    }
}
