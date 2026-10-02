package com.careconnect.service.ehr;

import com.careconnect.model.ehr.EhrSource;
import com.careconnect.repository.ehr.EhrSourceRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;

import java.util.concurrent.ConcurrentHashMap;

/**
 * Resolves a seeded {@code ehr_source.code} (e.g. {@code "EPIC"}) to its generated id and caches
 * it for the service lifetime, so a connector joins canonical rows by source id rather than by a
 * string literal in a column (Team E brief S1 / S2).
 *
 * <p>The seed itself is applied idempotently at boot by {@code SchemaPatchRunner}
 * ({@code applyEhrCanonicalSchemaPatches}); this bean only reads it.
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class EhrSourceResolver {

    private final EhrSourceRepository sources;
    private final ConcurrentHashMap<String, Long> cache = new ConcurrentHashMap<>();

    /**
     * The generated id for a seeded source code, or {@code null} when the source row is not present
     * (in which case the caller must skip its canonical writes rather than invent a source id).
     */
    public Long idForCode(final String code) {
        final Long cached = cache.get(code);
        if (cached != null) {
            return cached;
        }
        final Long id = sources.findByCode(code).map(EhrSource::getId).orElse(null);
        if (id != null) {
            cache.put(code, id);
        } else {
            log.warn("ehr_source code '{}' is not seeded; canonical writes for it are skipped", code);
        }
        return id;
    }
}
