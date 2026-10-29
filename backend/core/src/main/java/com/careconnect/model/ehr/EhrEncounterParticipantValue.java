package com.careconnect.model.ehr;

import java.util.List;

/** A normalized Encounter participant without flattening multiple roles into one string. */
public record EhrEncounterParticipantValue(
        List<EhrCodeValue> types,
        String reference,
        String display,
        String periodStart,
        String periodEnd) {

    public EhrEncounterParticipantValue {
        types = types == null ? List.of() : List.copyOf(types);
    }
}
