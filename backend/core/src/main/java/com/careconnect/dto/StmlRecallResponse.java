package com.careconnect.dto;

import lombok.Builder;
import lombok.Data;
import java.time.LocalDateTime;
import java.util.List;

@Data
@Builder
public class StmlRecallResponse {
    private String answer;
    private List<StmlRecallSourceDTO> sources;
    private String disclaimer;
    private LocalDateTime generatedAt;

    @Data
    @Builder
    public static class StmlRecallSourceDTO {
        private String sourceType;
        private String summary;
        private String date;
    }
}
