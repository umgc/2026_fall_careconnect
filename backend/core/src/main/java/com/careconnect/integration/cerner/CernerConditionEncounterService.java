package com.careconnect.integration.cerner;

import com.careconnect.model.ehr.EhrConditionRecord;
import com.careconnect.model.ehr.EhrEncounterRecord;
import java.util.List;

/** Application boundary for synchronizing canonical Condition and Encounter records from Cerner. */
public interface CernerConditionEncounterService {

    List<EhrConditionRecord> synchronizeConditions(long patientId);

    List<EhrEncounterRecord> synchronizeEncounters(long patientId);
}
