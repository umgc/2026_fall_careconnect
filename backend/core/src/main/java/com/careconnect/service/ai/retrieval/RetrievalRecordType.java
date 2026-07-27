package com.careconnect.service.ai.retrieval;

import com.careconnect.security.Role;

import java.util.Collections;
import java.util.EnumSet;
import java.util.Set;
import java.util.stream.Collectors;

/**
 * Canonical Ask AI retrieval source types indexed on {@code retrieval_index_chunk.record_type}.
 */
public enum RetrievalRecordType {
    TRANSCRIPT_SEGMENT,
    CALL_SUMMARY,
    VISIT_SUMMARY,
    UPLOADED_DOCUMENT,
    CLINICAL_NOTE,
    USPS_MAIL,
    SUMMARY_ACTION_ITEM,
    SUMMARY_APPOINTMENT,
    SUMMARY_CARE_INSTRUCTION,
    SUMMARY_CONDITION,
    SUMMARY_SOAP,
    SUMMARY_CLINICAL_OBSERVATION,
    /** Derived from careInstructions type=medication (FR-AI-11 / Task 4.5). */
    MEDICATION_TIMELINE_EVENT,
    MEDICATION,
    TASK,
    EVV_RECORD,
    VITAL_SIGN;

    private static final Set<RetrievalRecordType> ALL = Collections.unmodifiableSet(EnumSet.allOf(RetrievalRecordType.class));

    private static final Set<RetrievalRecordType> PATIENT_DEFAULTS;

    private static final Set<RetrievalRecordType> CAREGIVER_DEFAULTS = ALL;

    private static final Set<RetrievalRecordType> FAMILY_MEMBER_DEFAULTS;
    private static final Set<RetrievalRecordType> SUMMARY_TYPES =
            Collections.unmodifiableSet(EnumSet.of(
                    CALL_SUMMARY,
                    VISIT_SUMMARY,
                    SUMMARY_ACTION_ITEM,
                    SUMMARY_APPOINTMENT,
                    SUMMARY_CARE_INSTRUCTION,
                    SUMMARY_CONDITION,
                    SUMMARY_SOAP,
                    SUMMARY_CLINICAL_OBSERVATION,
                    MEDICATION_TIMELINE_EVENT));
    private static final Set<String> SUMMARY_TYPE_NAMES = SUMMARY_TYPES.stream()
            .map(Enum::name)
            .collect(Collectors.toUnmodifiableSet());

    static {
        EnumSet<RetrievalRecordType> patient = EnumSet.copyOf(ALL);
        patient.remove(USPS_MAIL);
        PATIENT_DEFAULTS = Collections.unmodifiableSet(patient);

        FAMILY_MEMBER_DEFAULTS = Collections.unmodifiableSet(EnumSet.of(
                TRANSCRIPT_SEGMENT,
                CALL_SUMMARY,
                VISIT_SUMMARY,
                UPLOADED_DOCUMENT,
                CLINICAL_NOTE,
                SUMMARY_ACTION_ITEM,
                SUMMARY_APPOINTMENT,
                SUMMARY_CARE_INSTRUCTION,
                SUMMARY_CONDITION,
                SUMMARY_SOAP,
                SUMMARY_CLINICAL_OBSERVATION,
                MEDICATION_TIMELINE_EVENT,
                MEDICATION,
                TASK,
                VITAL_SIGN
        ));
    }

    public static Set<RetrievalRecordType> all() {
        return EnumSet.copyOf(ALL);
    }

    public static Set<RetrievalRecordType> summaryTypes() {
        return EnumSet.copyOf(SUMMARY_TYPES);
    }

    public static Set<String> summaryTypeNames() {
        return Set.copyOf(SUMMARY_TYPE_NAMES);
    }

    public static Set<RetrievalRecordType> defaultsForRole(Role role) {
        if (role == null) {
            return Set.of();
        }
        return switch (role) {
            case ADMIN -> EnumSet.copyOf(ALL);
            case PATIENT -> EnumSet.copyOf(PATIENT_DEFAULTS);
            case CAREGIVER -> EnumSet.copyOf(CAREGIVER_DEFAULTS);
            case FAMILY_MEMBER -> EnumSet.copyOf(FAMILY_MEMBER_DEFAULTS);
        };
    }
}
