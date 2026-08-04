package com.careconnect.summary.safety;

import java.util.List;
import java.util.Objects;

/**
 * DTO passed into {@link SummarySafetyGateway}. Small on purpose — the caller extracts
 * only the fields the safety layer needs so the gateway does not couple to the full
 * {@code CallSummary} aggregate shape.
 *
 * @param summaryId    the persisted summary PK. Doubles as the correlation key
 *                     across the audit chain (ledger.summaryId ==
 *                     confirmationItem.referenceId == this.summaryId).
 * @param userId       the user who triggered the extraction (caregiver session
 *                     user, not the patient). Attributed on ledger + confirmation.
 * @param patientId    the patient the summary is about. Attributed on ledger.
 * @param sessionId    conversation / call session identifier for the ledger.
 *                     Nullable — pass {@code null} when there is no session anchor.
 * @param confirmables list of items to hold PENDING for reviewer confirm/dismiss.
 *                     Empty list is allowed (no gates created, still emits the
 *                     RESPONSE audit event when {@code logExtractionResponse} is
 *                     called).
 */
public record SummarySafetyContext(
        Long summaryId,
        Long userId,
        Long patientId,
        String sessionId,
        List<Confirmable> confirmables
) {
    public SummarySafetyContext {
        Objects.requireNonNull(summaryId, "summaryId");
        Objects.requireNonNull(userId, "userId");
        Objects.requireNonNull(patientId, "patientId");
        confirmables = confirmables == null ? List.of() : List.copyOf(confirmables);
    }

    /**
     * One confirmable summary item.
     *
     * @param type     one of {@code ACTION_ITEM}, {@code CARE_INSTRUCTION},
     *                 {@code CONDITION}. Carried into the reviewer-facing payload so
     *                 the Flutter card can render a type chip.
     * @param headline short reviewer-facing headline (required in practice, but
     *                 permissively nullable so a malformed extraction still gates).
     * @param detail   optional longer reviewer-facing detail text.
     */
    public record Confirmable(
            String type,
            String headline,
            String detail
    ) {}
}
