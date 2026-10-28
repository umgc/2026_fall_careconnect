package com.careconnect.dto.v2;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

class TaskDtoV2Test {
    @Test
    void cadenceAnchorRoundTripsAsAnOptionalIsoDate() throws Exception {
        final ObjectMapper mapper = new ObjectMapper();
        final TaskDtoV2 dto = TaskDtoV2.builder().date("2025-02-28")
                .recurrenceAnchorDate("2024-02-29").build();
        final TaskDtoV2 restored = mapper.readValue(mapper.writeValueAsString(dto), TaskDtoV2.class);
        assertThat(restored.getRecurrenceAnchorDate()).isEqualTo("2024-02-29");
        assertThat(mapper.readValue("{}", TaskDtoV2.class).getRecurrenceAnchorDate()).isNull();
    }
}
