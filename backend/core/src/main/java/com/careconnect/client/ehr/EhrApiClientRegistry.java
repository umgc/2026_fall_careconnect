package com.careconnect.client.ehr;

import java.util.List;
import java.util.Map;
import java.util.function.Function;
import java.util.stream.Collectors;
import org.springframework.stereotype.Component;

/**
 * Resolves the {@link EhrApiClient} adapter for a given {@code ehr_source.code}.
 *
 * <p>Callers (controllers, sync services) should depend on this registry rather than autowiring
 * a concrete adapter type or a bare {@code EhrApiClient}. Spring can inject every
 * {@code EhrApiClient} bean into a {@code List} regardless of how many exist, so registering a
 * second adapter (e.g. an Epic or Medicare client) here never breaks — whereas asking Spring to
 * inject a single {@code EhrApiClient} directly becomes ambiguous the moment more than one
 * implementation is registered, since Spring has no way to know which one a caller means.
 */
@Component
public class EhrApiClientRegistry {

    private final Map<String, EhrApiClient> clientsBySourceCode;

    public EhrApiClientRegistry(final List<EhrApiClient> clients) {
        this.clientsBySourceCode = clients.stream()
                .collect(Collectors.toUnmodifiableMap(
                        EhrApiClient::sourceCode,
                        Function.identity(),
                        (first, second) -> {
                            throw new IllegalStateException(
                                    "Multiple EhrApiClient beans registered for source code: "
                                            + first.sourceCode());
                        }));
    }

    /**
     * The adapter for {@code sourceCode}, for example {@code "ATHENAHEALTH"}.
     *
     * @throws IllegalArgumentException if no adapter is registered for that code
     */
    public EhrApiClient get(final String sourceCode) {
        final EhrApiClient client = clientsBySourceCode.get(sourceCode);
        if (client == null) {
            throw new IllegalArgumentException(
                    "No EhrApiClient registered for source code: " + sourceCode);
        }
        return client;
    }
}
