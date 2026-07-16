package com.careconnect.service.ai.retrieval;

import com.careconnect.security.Role;

import java.util.Collections;
import java.util.EnumSet;
import java.util.Set;

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
    MEDICATION,
    TASK,
    EVV_RECORD,
    VITAL_SIGN;

    private static final Set<RetrievalRecordType> ALL = Collections.unmodifiableSet(EnumSet.allOf(RetrievalRecordType.class));

    private static final Set<RetrievalRecordType> PATIENT_DEFAULTS;

    private static final Set<RetrievalRecordType> CAREGIVER_DEFAULTS = ALL;

    private static final Set<RetrievalRecordType> FAMILY_MEMBER_DEFAULTS;

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
                MEDICATION,
                TASK,
                VITAL_SIGN
        ));
    }

    public static Set<RetrievalRecordType> all() {
        return EnumSet.copyOf(ALL);
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
