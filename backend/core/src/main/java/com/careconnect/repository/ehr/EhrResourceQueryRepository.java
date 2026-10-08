package com.careconnect.repository.ehr;

import com.careconnect.model.ehr.EhrResource;
import org.springframework.data.domain.Pageable;
import org.springframework.data.domain.Slice;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.Repository;
import org.springframework.data.repository.query.Param;

import java.util.List;

/**
 * Reads over the {@code ehr_resource} mirror beyond those in {@link EhrResourceRepository}.
 *
 * <p>Kept separate because {@link EhrResourceRepository} is shared with the Epic integration
 * (PR #234) and is kept identical to that branch's copy so the two merge cleanly.
 */
public interface EhrResourceQueryRepository extends Repository<EhrResource, Long> {

    /**
     * One page of a user's records from one source, newest first, without a total count.
     *
     * <p>{@code occurredAt} is an ISO-8601 string, so a date bound compares as text: "2024-05-01"
     * sorts before every timestamp on that day. Records with no date sort last and are excluded
     * whenever a bound is given. The Patient row is excluded; it is demographics, not a record.
     *
     * @param fromInclusive ISO date, or null for no lower bound
     * @param toExclusive   ISO date of the day after the last day wanted, or null for no upper bound
     */
    @Query("select e from EhrResource e "
            + "where e.userId = :userId and e.source = :source "
            + "and e.resourceType <> 'Patient' "
            + "and (:fromInclusive is null or e.occurredAt >= :fromInclusive) "
            + "and (:toExclusive is null or e.occurredAt < :toExclusive) "
            + "order by e.occurredAt desc nulls last, e.id desc")
    Slice<EhrResource> findPage(@Param("userId") Long userId,
                                @Param("source") String source,
                                @Param("fromInclusive") String fromInclusive,
                                @Param("toExclusive") String toExclusive,
                                Pageable pageable);

    /** A user's records of one type from one source, for reconciling them after a sync. */
    List<EhrResource> findByUserIdAndSourceAndResourceType(Long userId, String source, String resourceType);
}
