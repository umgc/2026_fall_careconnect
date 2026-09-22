package com.careconnect.model;

import com.fasterxml.jackson.annotation.JsonProperty;
import lombok.*;

import java.time.OffsetDateTime;

@Data
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class MailPiece {
    private String id;
    private String sender;

    @JsonProperty("summary")
    private String subject;

    @JsonProperty("imageDataUrl")
    private String thumbnailUrl;        // data: URL or https link

    private OffsetDateTime receivedAt;  // when the digest says it's from

    @JsonProperty("actions")
    private ActionLinks actionLinks;
}
