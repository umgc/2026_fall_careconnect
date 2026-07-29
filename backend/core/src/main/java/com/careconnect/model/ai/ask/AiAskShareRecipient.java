package com.careconnect.model.ai.ask;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.IdClass;
import jakarta.persistence.Table;
import java.io.Serializable;
import java.util.Objects;
import java.util.UUID;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

/** Normalized recipient row for Ask AI conversation share ACL queries. */
@Entity
@Table(name = "ai_ask_share_recipient")
@IdClass(AiAskShareRecipient.Pk.class)
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class AiAskShareRecipient {

    @Id
    @Column(name = "share_id", nullable = false, updatable = false)
    private UUID shareId;

    @Id
    @Column(name = "user_id", nullable = false, updatable = false)
    private Long userId;

    @Data
    @NoArgsConstructor
    @AllArgsConstructor
    public static class Pk implements Serializable {
        private UUID shareId;
        private Long userId;

        @Override
        public boolean equals(final Object o) {
            if (this == o) {
                return true;
            }
            if (!(o instanceof Pk pk)) {
                return false;
            }
            return Objects.equals(shareId, pk.shareId) && Objects.equals(userId, pk.userId);
        }

        @Override
        public int hashCode() {
            return Objects.hash(shareId, userId);
        }
    }
}
