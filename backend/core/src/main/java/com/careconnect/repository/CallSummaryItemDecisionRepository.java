package com.careconnect.repository;

import com.careconnect.model.CallSummaryItemDecision;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;

/**
 * Repository for {@link CallSummaryItemDecision} audit rows. The backing
 * table is append-only, so this repository deliberately exposes no update or
 * delete operations.
 */
public interface CallSummaryItemDecisionRepository
        extends JpaRepository<CallSummaryItemDecision, Long> {

    /**
     * Returns every decision recorded against a summary, newest first.
     *
     * @param summaryId identifier of the parent {@code CallSummary}
     * @return decision history for the summary
     */
    List<CallSummaryItemDecision> findBySummaryIdOrderByDecidedAtDesc(Long summaryId);

    /**
     * Returns every decision recorded against a single extracted item, newest
     * first.
     *
     * @param summaryId identifier of the parent {@code CallSummary}
     * @param itemId    identifier of the extracted item within the summary
     * @return decision history for the item
     */
    List<CallSummaryItemDecision> findBySummaryIdAndItemIdOrderByDecidedAtDesc(
            Long summaryId,
            String itemId);

    /**
     * Returns the most recent decision recorded against a single extracted
     * item. Used by the UI to render confirm/dismiss state per item and by
     * the confirmation endpoint to inspect prior decisions.
     *
     * @param summaryId identifier of the parent {@code CallSummary}
     * @param itemId    identifier of the extracted item within the summary
     * @return latest decision when present
     */
    Optional<CallSummaryItemDecision> findTopBySummaryIdAndItemIdOrderByDecidedAtDesc(
            Long summaryId,
            String itemId);

    /**
     * Counts decisions recorded against a summary. Useful for dashboard
     * displays such as &quot;3 of 5 items confirmed.&quot;
     *
     * @param summaryId identifier of the parent {@code CallSummary}
     * @return number of decisions recorded
     */
    long countBySummaryId(Long summaryId);

    /**
     * Returns the paginated history of decisions made by a single user,
     * newest first. Useful for user-facing audit views.
     *
     * @param decidedByUserId identifier of the deciding user
     * @param pageable        pagination parameters
     * @return paginated decision history for the user
     */
    List<CallSummaryItemDecision> findByDecidedByUserIdOrderByDecidedAtDesc(
            Long decidedByUserId,
            Pageable pageable);
}
