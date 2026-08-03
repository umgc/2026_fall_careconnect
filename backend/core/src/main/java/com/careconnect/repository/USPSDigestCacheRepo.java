package com.careconnect.repository;

import com.careconnect.model.USPSDigestCache;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;

public interface USPSDigestCacheRepo extends JpaRepository<USPSDigestCache, Long> {
    Optional<USPSDigestCache> findFirstByUserIdAndExpiresAtAfterOrderByDigestDateDesc(String userId, Instant now);

    Optional<USPSDigestCache> findFirstByUserIdAndDigestDateBetweenAndExpiresAtAfterOrderByDigestDateDesc(
            String userId,
            Instant startInclusive,
            Instant endExclusive,
            Instant now);

    List<USPSDigestCache> findByUserIdOrderByDigestDateDesc(String userId);

    void deleteByUserId(String userId);
}
