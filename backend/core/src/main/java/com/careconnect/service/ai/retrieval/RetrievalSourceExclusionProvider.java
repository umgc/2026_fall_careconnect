package com.careconnect.service.ai.retrieval;

import java.util.Set;

/**
 * Supplies patient-owned source type exclusions (REQ-SC-7).
 */
public interface RetrievalSourceExclusionProvider {

    Set<RetrievalRecordType> getExcludedSourceTypes(Long patientEntityId);
}
