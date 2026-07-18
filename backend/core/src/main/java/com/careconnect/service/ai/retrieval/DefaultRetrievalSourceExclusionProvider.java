package com.careconnect.service.ai.retrieval;

import org.springframework.stereotype.Component;

import java.util.Set;

/** Default REQ-SC-7 provider until persistent patient indexing preferences are implemented. */
@Component
public class DefaultRetrievalSourceExclusionProvider implements RetrievalSourceExclusionProvider {

    @Override
    public Set<RetrievalRecordType> getExcludedSourceTypes(Long patientEntityId) {
        return Set.of();
    }
}
